import { Router } from 'express';
import { createLogger } from '../utils/logger.js';
import { query } from '../db/pool.js';
import * as recordingService from '../services/recordingService.js';

const router = Router();
const logger = createLogger('routes:recordings');

router.get('/', async (req, res) => {
  try {
    const {
      limit = 50,
      offset = 0,
      user_id,
      call_sid,
    } = req.query;

    let queryText = `
      SELECT r.id, r.call_session_id, r.storage_path, r.duration_seconds,
             r.file_size_bytes, r.format, r.created_at,
             cs.call_sid, cs.phone_number, cs.direction
      FROM recordings r
      JOIN call_sessions cs ON r.call_session_id = cs.id
      WHERE 1=1
    `;
    const params = [];
    let paramIndex = 1;

    if (user_id) {
      queryText += ` AND cs.user_id = $${paramIndex++}`;
      params.push(user_id);
    }

    if (call_sid) {
      queryText += ` AND cs.call_sid = $${paramIndex++}`;
      params.push(call_sid);
    }

    queryText += ` ORDER BY r.created_at DESC LIMIT $${paramIndex++} OFFSET $${paramIndex++}`;
    params.push(parseInt(limit), parseInt(offset));

    const result = await query(queryText, params);

    const countResult = await query('SELECT COUNT(*) as total FROM recordings');

    res.json({
      recordings: result.rows.map((row) => ({
        id: row.id,
        call_session_id: row.call_session_id,
        call_sid: row.call_sid,
        phone_number: row.phone_number,
        direction: row.direction,
        duration: row.duration_seconds,        // iOS expects 'duration'
        file_size: row.file_size_bytes,        // iOS expects 'file_size'
        format: row.format,
        sample_rate: 24000,                     // PCM16 sample rate
        channels: 1,                            // Mono audio
        has_transcript: false,                  // Placeholder for future
        created_at: row.created_at,
      })),
      total: parseInt(countResult.rows[0].total),
      limit: parseInt(limit),
      offset: parseInt(offset),
    });
  } catch (error) {
    logger.error('Failed to list recordings', error);
    res.status(500).json({
      error: {
        code: 'LIST_RECORDINGS_FAILED',
        message: 'Failed to list recordings',
        details: error.message,
      },
    });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const result = await query(
      `SELECT r.id, r.call_session_id, r.storage_path, r.duration_seconds,
              r.file_size_bytes, r.format, r.created_at,
              cs.call_sid, cs.phone_number, cs.direction, cs.started_at, cs.ended_at
       FROM recordings r
       JOIN call_sessions cs ON r.call_session_id = cs.id
       WHERE r.id = $1`,
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: {
          code: 'RECORDING_NOT_FOUND',
          message: `Recording not found: ${id}`,
        },
      });
    }

    const row = result.rows[0];
    res.json({
      recording: {
        id: row.id,
        call_session_id: row.call_session_id,
        call_sid: row.call_sid,
        phone_number: row.phone_number,
        direction: row.direction,
        duration: row.duration_seconds,         // iOS expects 'duration'
        file_size: row.file_size_bytes,         // iOS expects 'file_size'
        format: row.format,
        sample_rate: 24000,                      // PCM16 sample rate
        channels: 1,                             // Mono audio
        has_transcript: false,                   // Placeholder for future
        created_at: row.created_at,
        call_started_at: row.started_at,
        call_ended_at: row.ended_at,
      },
    });
  } catch (error) {
    logger.error('Failed to get recording', { id: req.params.id, error });
    res.status(500).json({
      error: {
        code: 'GET_RECORDING_FAILED',
        message: 'Failed to retrieve recording',
        details: error.message,
      },
    });
  }
});

router.get('/:id/audio', async (req, res) => {
  try {
    const { id } = req.params;

    const result = await query(
      'SELECT storage_path, format FROM recordings WHERE id = $1',
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: {
          code: 'RECORDING_NOT_FOUND',
          message: `Recording not found: ${id}`,
        },
      });
    }

    const { storage_path, format } = result.rows[0];

    const audioStream = await recordingService.getRecordingStream(storage_path);

    const contentType = format === 'wav' ? 'audio/wav' : 'audio/mpeg';
    res.set('Content-Type', contentType);
    res.set('Content-Disposition', `inline; filename="recording-${id}.${format}"`);

    audioStream.pipe(res);
  } catch (error) {
    logger.error('Failed to stream recording', { id: req.params.id, error });
    res.status(500).json({
      error: {
        code: 'STREAM_RECORDING_FAILED',
        message: 'Failed to stream recording',
        details: error.message,
      },
    });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const result = await query(
      'SELECT storage_path FROM recordings WHERE id = $1',
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: {
          code: 'RECORDING_NOT_FOUND',
          message: `Recording not found: ${id}`,
        },
      });
    }

    const { storage_path } = result.rows[0];

    await recordingService.deleteRecording(storage_path);

    await query('DELETE FROM recordings WHERE id = $1', [id]);

    logger.info('Recording deleted', { id, storagePath: storage_path });

    res.json({
      success: true,
      deleted_id: id,
    });
  } catch (error) {
    logger.error('Failed to delete recording', { id: req.params.id, error });
    res.status(500).json({
      error: {
        code: 'DELETE_RECORDING_FAILED',
        message: 'Failed to delete recording',
        details: error.message,
      },
    });
  }
});

router.get('/:id/download', async (req, res) => {
  try {
    const { id } = req.params;

    const result = await query(
      `SELECT r.storage_path, r.format, cs.call_sid
       FROM recordings r
       JOIN call_sessions cs ON r.call_session_id = cs.id
       WHERE r.id = $1`,
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: {
          code: 'RECORDING_NOT_FOUND',
          message: `Recording not found: ${id}`,
        },
      });
    }

    const { storage_path, format, call_sid } = result.rows[0];

    const audioStream = await recordingService.getRecordingStream(storage_path);

    const contentType = format === 'wav' ? 'audio/wav' : 'audio/mpeg';
    const filename = `recording-${call_sid}-${id}.${format}`;

    res.set('Content-Type', contentType);
    res.set('Content-Disposition', `attachment; filename="${filename}"`);

    audioStream.pipe(res);
  } catch (error) {
    logger.error('Failed to download recording', { id: req.params.id, error });
    res.status(500).json({
      error: {
        code: 'DOWNLOAD_RECORDING_FAILED',
        message: 'Failed to download recording',
        details: error.message,
      },
    });
  }
});

export default router;
