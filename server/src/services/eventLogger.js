import { v4 as uuidv4 } from 'uuid';
import { createLogger } from '../utils/logger.js';
import { query, transaction } from '../db/pool.js';

const logger = createLogger('event-logger');

export async function logEvent(callSessionId, eventType, direction, payload = null) {
  try {
    const result = await query(
      `INSERT INTO call_events (id, call_session_id, event_type, direction, payload)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, event_type, direction, payload, created_at`,
      [uuidv4(), callSessionId, eventType, direction, payload ? JSON.stringify(payload) : null]
    );

    return result.rows[0];
  } catch (error) {
    logger.error('Failed to log event', {
      callSessionId,
      eventType,
      error: error.message,
    });
    throw error;
  }
}

export async function logBatchEvents(events) {
  if (!events || events.length === 0) {
    return [];
  }

  try {
    const values = events.map((e) => ({
      id: uuidv4(),
      callSessionId: e.callSessionId,
      eventType: e.eventType,
      direction: e.direction,
      payload: e.payload ? JSON.stringify(e.payload) : null,
    }));

    const placeholders = values.map((_, i) => {
      const base = i * 5;
      return `($${base + 1}, $${base + 2}, $${base + 3}, $${base + 4}, $${base + 5})`;
    }).join(', ');

    const params = values.flatMap((v) => [
      v.id,
      v.callSessionId,
      v.eventType,
      v.direction,
      v.payload,
    ]);

    const result = await query(
      `INSERT INTO call_events (id, call_session_id, event_type, direction, payload)
       VALUES ${placeholders}
       RETURNING id, event_type, direction, payload, created_at`,
      params
    );

    logger.debug('Batch events logged', { count: result.rows.length });
    return result.rows;
  } catch (error) {
    logger.error('Failed to log batch events', { error: error.message });
    throw error;
  }
}

export async function getEvents(callSessionId, options = {}) {
  const { limit = 100, offset = 0, eventType, direction } = options;

  let queryText = `
    SELECT id, event_type, direction, payload, created_at
    FROM call_events
    WHERE call_session_id = $1
  `;
  const params = [callSessionId];
  let paramIndex = 2;

  if (eventType) {
    queryText += ` AND event_type = $${paramIndex++}`;
    params.push(eventType);
  }

  if (direction) {
    queryText += ` AND direction = $${paramIndex++}`;
    params.push(direction);
  }

  queryText += ` ORDER BY created_at ASC LIMIT $${paramIndex++} OFFSET $${paramIndex++}`;
  params.push(limit, offset);

  const result = await query(queryText, params);
  return result.rows;
}

export async function getEventsByCallSid(callSid, options = {}) {
  const { limit = 100, offset = 0, eventType, direction } = options;

  let queryText = `
    SELECT ce.id, ce.event_type, ce.direction, ce.payload, ce.created_at
    FROM call_events ce
    JOIN call_sessions cs ON ce.call_session_id = cs.id
    WHERE cs.call_sid = $1
  `;
  const params = [callSid];
  let paramIndex = 2;

  if (eventType) {
    queryText += ` AND ce.event_type = $${paramIndex++}`;
    params.push(eventType);
  }

  if (direction) {
    queryText += ` AND ce.direction = $${paramIndex++}`;
    params.push(direction);
  }

  queryText += ` ORDER BY ce.created_at ASC LIMIT $${paramIndex++} OFFSET $${paramIndex++}`;
  params.push(limit, offset);

  const result = await query(queryText, params);
  return result.rows;
}

export async function getEventCount(callSessionId) {
  const result = await query(
    'SELECT COUNT(*) as count FROM call_events WHERE call_session_id = $1',
    [callSessionId]
  );
  return parseInt(result.rows[0].count);
}

export async function getEventStats(callSessionId) {
  const result = await query(
    `SELECT
       event_type,
       direction,
       COUNT(*) as count,
       MIN(created_at) as first_at,
       MAX(created_at) as last_at
     FROM call_events
     WHERE call_session_id = $1
     GROUP BY event_type, direction
     ORDER BY count DESC`,
    [callSessionId]
  );

  return result.rows;
}

export async function deleteEvents(callSessionId) {
  const result = await query(
    'DELETE FROM call_events WHERE call_session_id = $1',
    [callSessionId]
  );

  logger.info('Events deleted', {
    callSessionId,
    deletedCount: result.rowCount,
  });

  return result.rowCount;
}

export async function logTranscript(callSessionId, speaker, content, timestampMs = null) {
  try {
    const result = await query(
      `INSERT INTO transcripts (id, call_session_id, speaker, content, timestamp_ms)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, speaker, content, timestamp_ms, created_at`,
      [uuidv4(), callSessionId, speaker, content, timestampMs]
    );

    return result.rows[0];
  } catch (error) {
    logger.error('Failed to log transcript', {
      callSessionId,
      speaker,
      error: error.message,
    });
    throw error;
  }
}

export async function getTranscripts(callSessionId, options = {}) {
  const { limit = 500, offset = 0, speaker } = options;

  let queryText = `
    SELECT id, speaker, content, timestamp_ms, created_at
    FROM transcripts
    WHERE call_session_id = $1
  `;
  const params = [callSessionId];
  let paramIndex = 2;

  if (speaker) {
    queryText += ` AND speaker = $${paramIndex++}`;
    params.push(speaker);
  }

  queryText += ` ORDER BY timestamp_ms ASC, created_at ASC LIMIT $${paramIndex++} OFFSET $${paramIndex++}`;
  params.push(limit, offset);

  const result = await query(queryText, params);
  return result.rows;
}

export async function getFullTranscript(callSessionId) {
  const transcripts = await getTranscripts(callSessionId, { limit: 10000 });

  return transcripts.map((t) => ({
    speaker: t.speaker === 'user' ? 'User' : 'Assistant',
    content: t.content,
    timestamp: t.timestamp_ms,
  }));
}

export async function exportCallData(callSid) {
  const sessionResult = await query(
    `SELECT id, call_sid, direction, phone_number, status,
            started_at, ended_at, duration_seconds, config_snapshot
     FROM call_sessions
     WHERE call_sid = $1`,
    [callSid]
  );

  if (sessionResult.rows.length === 0) {
    return null;
  }

  const session = sessionResult.rows[0];
  const callSessionId = session.id;

  const [events, transcripts, recordings] = await Promise.all([
    getEvents(callSessionId, { limit: 10000 }),
    getTranscripts(callSessionId, { limit: 10000 }),
    query('SELECT id, duration_seconds, file_size_bytes, format, created_at FROM recordings WHERE call_session_id = $1', [callSessionId]),
  ]);

  return {
    call: {
      callSid: session.call_sid,
      direction: session.direction,
      phoneNumber: session.phone_number,
      status: session.status,
      startedAt: session.started_at,
      endedAt: session.ended_at,
      durationSeconds: session.duration_seconds,
      config: session.config_snapshot,
    },
    events: events.map((e) => ({
      type: e.event_type,
      direction: e.direction,
      payload: e.payload,
      timestamp: e.created_at,
    })),
    transcripts: transcripts.map((t) => ({
      speaker: t.speaker,
      content: t.content,
      timestampMs: t.timestamp_ms,
    })),
    recordings: recordings.rows.map((r) => ({
      id: r.id,
      durationSeconds: r.duration_seconds,
      fileSizeBytes: r.file_size_bytes,
      format: r.format,
      createdAt: r.created_at,
    })),
  };
}

export default {
  logEvent,
  logBatchEvents,
  getEvents,
  getEventsByCallSid,
  getEventCount,
  getEventStats,
  deleteEvents,
  logTranscript,
  getTranscripts,
  getFullTranscript,
  exportCallData,
};
