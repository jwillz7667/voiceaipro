import { Router } from 'express';
import twilio from 'twilio';
import config from '../config/environment.js';
import { createLogger } from '../utils/logger.js';
import connectionManager from '../websocket/connectionManager.js';
import * as callService from '../services/twilioService.js';
import { query } from '../db/pool.js';

const router = Router();
const logger = createLogger('routes:calls');

router.post('/outgoing', async (req, res) => {
  try {
    const {
      to,
      from,
      user_id,
      prompt_id,
      config: sessionConfig,
    } = req.body;

    if (!to) {
      return res.status(400).json({
        error: {
          code: 'MISSING_TO',
          message: 'Destination phone number (to) is required',
        },
      });
    }

    const fromNumber = from || config.twilio.phoneNumber;

    logger.info('Initiating outgoing call', {
      to,
      from: fromNumber,
      userId: user_id,
      promptId: prompt_id,
    });

    const call = await callService.initiateOutgoingCall({
      to,
      from: fromNumber,
      userId: user_id,
      promptId: prompt_id,
      sessionConfig,
    });

    res.json({
      success: true,
      call_sid: call.sid,
      status: call.status,
      to: call.to,
      from: call.from,
      direction: 'outbound',
    });
  } catch (error) {
    logger.error('Failed to initiate outgoing call', error);
    res.status(500).json({
      error: {
        code: 'CALL_INITIATION_FAILED',
        message: 'Failed to initiate outgoing call',
        details: error.message,
      },
    });
  }
});

router.post('/:callSid/end', async (req, res) => {
  try {
    const { callSid } = req.params;
    const { reason } = req.body;

    logger.info('Ending call', { callSid, reason });

    await callService.endCall(callSid, reason);

    connectionManager.destroySession(callSid, reason || 'api_end');

    res.json({
      success: true,
      call_sid: callSid,
      ended_at: new Date().toISOString(),
    });
  } catch (error) {
    logger.error('Failed to end call', { callSid: req.params.callSid, error });
    res.status(500).json({
      error: {
        code: 'CALL_END_FAILED',
        message: 'Failed to end call',
        details: error.message,
      },
    });
  }
});

router.get('/active', (req, res) => {
  const activeSessions = connectionManager.getActiveSessions();

  res.json({
    count: activeSessions.length,
    calls: activeSessions.map((session) => ({
      id: session.id,
      call_sid: session.callSid,
      direction: session.direction,
      phone_number: session.phoneNumber,
      status: session.status,
      started_at: session.createdAt.toISOString(),
      duration_seconds: Math.floor((Date.now() - session.createdAt.getTime()) / 1000),
    })),
  });
});

// Call history - must be before /:callSid to avoid route conflict
router.get('/history', async (req, res) => {
  try {
    const {
      limit = 50,
      offset = 0,
      user_id,
      direction,
      status,
    } = req.query;

    let queryText = `
      SELECT id, call_sid, direction, phone_number, status,
             started_at, ended_at, duration_seconds
      FROM call_sessions
      WHERE 1=1
    `;
    const params = [];
    let paramIndex = 1;

    if (user_id) {
      queryText += ` AND user_id = $${paramIndex++}`;
      params.push(user_id);
    }

    if (direction) {
      queryText += ` AND direction = $${paramIndex++}`;
      params.push(direction);
    }

    if (status) {
      queryText += ` AND status = $${paramIndex++}`;
      params.push(status);
    }

    queryText += ` ORDER BY started_at DESC LIMIT $${paramIndex++} OFFSET $${paramIndex++}`;
    params.push(parseInt(limit), parseInt(offset));

    const result = await query(queryText, params);

    const countResult = await query(
      'SELECT COUNT(*) as total FROM call_sessions WHERE 1=1'
    );

    res.json({
      calls: result.rows.map((row) => ({
        id: row.id,
        call_sid: row.call_sid,
        direction: row.direction,
        phone_number: row.phone_number,
        status: row.status,
        started_at: row.started_at,
        ended_at: row.ended_at,
        duration_seconds: row.duration_seconds,
      })),
      pagination: {
        total: parseInt(countResult.rows[0].total),
        limit: parseInt(limit),
        offset: parseInt(offset),
      },
    });
  } catch (error) {
    logger.error('Failed to get call history', error);
    res.status(500).json({
      error: {
        code: 'GET_HISTORY_FAILED',
        message: 'Failed to retrieve call history',
        details: error.message,
      },
    });
  }
});

router.get('/:callSid', async (req, res) => {
  try {
    const { callSid } = req.params;
    const { include } = req.query; // include=events,transcripts,recordings for full details

    const activeSession = connectionManager.getSession(callSid);

    if (activeSession) {
      const response = {
        source: 'active',
        call: {
          id: activeSession.id,
          call_sid: activeSession.callSid,
          direction: activeSession.direction,
          phone_number: activeSession.phoneNumber,
          status: activeSession.status,
          started_at: activeSession.createdAt.toISOString(),
          duration_seconds: Math.floor((Date.now() - activeSession.createdAt.getTime()) / 1000),
          config: activeSession.config,
          event_count: activeSession.events.length,
          transcript_count: activeSession.transcripts.length,
        },
      };

      // Include extra data if requested
      if (include) {
        const includes = include.split(',');
        if (includes.includes('events')) {
          response.events = activeSession.events;
        }
        if (includes.includes('transcripts')) {
          response.transcripts = activeSession.transcripts;
        }
      }

      return res.json(response);
    }

    // Get from database
    const result = await query(
      `SELECT cs.id, cs.call_sid, cs.direction, cs.phone_number, cs.status,
              cs.started_at, cs.ended_at, cs.duration_seconds, cs.config_snapshot,
              cs.user_id, cs.prompt_id,
              p.name as prompt_name, p.instructions as prompt_instructions, p.voice as prompt_voice
       FROM call_sessions cs
       LEFT JOIN prompts p ON cs.prompt_id = p.id
       WHERE cs.call_sid = $1`,
      [callSid]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: {
          code: 'CALL_NOT_FOUND',
          message: `Call not found: ${callSid}`,
        },
      });
    }

    const row = result.rows[0];
    const response = {
      source: 'database',
      call: {
        id: row.id,
        call_sid: row.call_sid,
        direction: row.direction,
        phone_number: row.phone_number,
        status: row.status,
        started_at: row.started_at,
        ended_at: row.ended_at,
        duration_seconds: row.duration_seconds,
        config: row.config_snapshot,
        user_id: row.user_id,
        prompt: row.prompt_id ? {
          id: row.prompt_id,
          name: row.prompt_name,
          instructions: row.prompt_instructions,
          voice: row.prompt_voice,
        } : null,
      },
    };

    // Include extra data if requested
    if (include) {
      const includes = include.split(',');
      const sessionId = row.id;

      const promises = [];

      if (includes.includes('events')) {
        promises.push(
          query(
            `SELECT id, event_type, direction, payload, created_at
             FROM call_events
             WHERE call_session_id = $1
             ORDER BY created_at ASC`,
            [sessionId]
          ).then(r => ({ events: r.rows }))
        );
      }

      if (includes.includes('transcripts')) {
        promises.push(
          query(
            `SELECT id, speaker, content, timestamp_ms, created_at
             FROM transcripts
             WHERE call_session_id = $1
             ORDER BY timestamp_ms ASC`,
            [sessionId]
          ).then(r => ({ transcripts: r.rows }))
        );
      }

      if (includes.includes('recordings')) {
        promises.push(
          query(
            `SELECT id, storage_path, duration_seconds, file_size_bytes, format, created_at
             FROM recordings
             WHERE call_session_id = $1`,
            [sessionId]
          ).then(r => ({ recordings: r.rows }))
        );
      }

      const extraData = await Promise.all(promises);
      extraData.forEach(data => Object.assign(response, data));
    }

    res.json(response);
  } catch (error) {
    logger.error('Failed to get call', { callSid: req.params.callSid, error });
    res.status(500).json({
      error: {
        code: 'GET_CALL_FAILED',
        message: 'Failed to retrieve call information',
        details: error.message,
      },
    });
  }
});

router.get('/:callSid/full', async (req, res) => {
  try {
    const { callSid } = req.params;

    // Get call session with all related data
    const sessionResult = await query(
      `SELECT cs.id, cs.call_sid, cs.direction, cs.phone_number, cs.status,
              cs.started_at, cs.ended_at, cs.duration_seconds, cs.config_snapshot,
              cs.user_id, cs.prompt_id,
              p.name as prompt_name, p.instructions as prompt_instructions, p.voice as prompt_voice
       FROM call_sessions cs
       LEFT JOIN prompts p ON cs.prompt_id = p.id
       WHERE cs.call_sid = $1`,
      [callSid]
    );

    if (sessionResult.rows.length === 0) {
      return res.status(404).json({
        error: {
          code: 'CALL_NOT_FOUND',
          message: `Call not found: ${callSid}`,
        },
      });
    }

    const session = sessionResult.rows[0];

    // Get events, transcripts, and recordings in parallel
    const [eventsResult, transcriptsResult, recordingsResult] = await Promise.all([
      query(
        `SELECT id, event_type, direction, payload, created_at
         FROM call_events
         WHERE call_session_id = $1
         ORDER BY created_at ASC`,
        [session.id]
      ),
      query(
        `SELECT id, speaker, content, timestamp_ms, created_at
         FROM transcripts
         WHERE call_session_id = $1
         ORDER BY timestamp_ms ASC`,
        [session.id]
      ),
      query(
        `SELECT id, storage_path, duration_seconds, file_size_bytes, format, created_at
         FROM recordings
         WHERE call_session_id = $1`,
        [session.id]
      ),
    ]);

    res.json({
      call: {
        id: session.id,
        call_sid: session.call_sid,
        direction: session.direction,
        phone_number: session.phone_number,
        status: session.status,
        started_at: session.started_at,
        ended_at: session.ended_at,
        duration_seconds: session.duration_seconds,
        config: session.config_snapshot,
        user_id: session.user_id,
        prompt: session.prompt_id ? {
          id: session.prompt_id,
          name: session.prompt_name,
          instructions: session.prompt_instructions,
          voice: session.prompt_voice,
        } : null,
      },
      events: eventsResult.rows,
      transcripts: transcriptsResult.rows,
      recordings: recordingsResult.rows.map(r => ({
        id: r.id,
        duration_seconds: r.duration_seconds,
        file_size_bytes: r.file_size_bytes,
        format: r.format,
        created_at: r.created_at,
      })),
      statistics: {
        event_count: eventsResult.rows.length,
        transcript_count: transcriptsResult.rows.length,
        recording_count: recordingsResult.rows.length,
        user_message_count: transcriptsResult.rows.filter(t => t.speaker === 'user').length,
        assistant_message_count: transcriptsResult.rows.filter(t => t.speaker === 'assistant').length,
      },
    });
  } catch (error) {
    logger.error('Failed to get full call details', { callSid: req.params.callSid, error });
    res.status(500).json({
      error: {
        code: 'GET_CALL_FAILED',
        message: 'Failed to retrieve call information',
        details: error.message,
      },
    });
  }
});

router.get('/:callSid/events', async (req, res) => {
  try {
    const { callSid } = req.params;
    const { limit = 100, offset = 0, type } = req.query;

    const activeSession = connectionManager.getSession(callSid);

    if (activeSession) {
      let events = activeSession.events;

      if (type) {
        events = events.filter((e) => e.eventType === type);
      }

      const paginatedEvents = events.slice(
        parseInt(offset),
        parseInt(offset) + parseInt(limit)
      );

      return res.json({
        source: 'active',
        events: paginatedEvents,
        pagination: {
          total: events.length,
          limit: parseInt(limit),
          offset: parseInt(offset),
        },
      });
    }

    let queryText = `
      SELECT id, event_type, direction, payload, created_at
      FROM call_events
      WHERE call_session_id = (
        SELECT id FROM call_sessions WHERE call_sid = $1
      )
    `;
    const params = [callSid];
    let paramIndex = 2;

    if (type) {
      queryText += ` AND event_type = $${paramIndex++}`;
      params.push(type);
    }

    queryText += ` ORDER BY created_at ASC LIMIT $${paramIndex++} OFFSET $${paramIndex++}`;
    params.push(parseInt(limit), parseInt(offset));

    const result = await query(queryText, params);

    res.json({
      source: 'database',
      events: result.rows.map((row) => ({
        id: row.id,
        event_type: row.event_type,
        direction: row.direction,
        payload: row.payload,
        timestamp: row.created_at,
      })),
      pagination: {
        total: result.rows.length,
        limit: parseInt(limit),
        offset: parseInt(offset),
      },
    });
  } catch (error) {
    logger.error('Failed to get call events', { callSid: req.params.callSid, error });
    res.status(500).json({
      error: {
        code: 'GET_EVENTS_FAILED',
        message: 'Failed to retrieve call events',
        details: error.message,
      },
    });
  }
});

router.get('/:callSid/transcripts', async (req, res) => {
  try {
    const { callSid } = req.params;

    const activeSession = connectionManager.getSession(callSid);

    if (activeSession) {
      return res.json({
        source: 'active',
        transcripts: activeSession.transcripts,
      });
    }

    const result = await query(
      `SELECT id, speaker, content, timestamp_ms, created_at
       FROM transcripts
       WHERE call_session_id = (
         SELECT id FROM call_sessions WHERE call_sid = $1
       )
       ORDER BY timestamp_ms ASC`,
      [callSid]
    );

    res.json({
      source: 'database',
      transcripts: result.rows.map((row) => ({
        id: row.id,
        speaker: row.speaker,
        content: row.content,
        timestamp_ms: row.timestamp_ms,
        created_at: row.created_at,
      })),
    });
  } catch (error) {
    logger.error('Failed to get transcripts', { callSid: req.params.callSid, error });
    res.status(500).json({
      error: {
        code: 'GET_TRANSCRIPTS_FAILED',
        message: 'Failed to retrieve transcripts',
        details: error.message,
      },
    });
  }
});

export default router;
