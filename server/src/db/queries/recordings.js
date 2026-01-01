/**
 * Recordings Database Queries
 *
 * CRUD operations for recordings table
 */

import { query } from '../pool.js';
import { createLogger } from '../../utils/logger.js';

const logger = createLogger('db:recordings');

/**
 * Create a new recording entry
 *
 * @param {Object} data - Recording data
 * @param {string} data.callSessionId - Associated call session UUID
 * @param {string} data.storagePath - Path to the recording file
 * @param {number} [data.durationSeconds] - Recording duration
 * @param {number} [data.fileSizeBytes] - File size in bytes
 * @param {string} [data.format='wav'] - Audio format
 * @returns {Promise<Object>} Created recording
 */
export async function createRecording(data) {
  const {
    callSessionId,
    storagePath,
    durationSeconds,
    fileSizeBytes,
    format = 'wav',
  } = data;

  const result = await query(
    `INSERT INTO recordings (call_session_id, storage_path, duration_seconds, file_size_bytes, format)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING id, call_session_id, storage_path, duration_seconds, file_size_bytes, format, created_at`,
    [callSessionId, storagePath, durationSeconds || null, fileSizeBytes || null, format]
  );

  logger.info('Recording created', { id: result.rows[0].id, callSessionId });

  return result.rows[0];
}

/**
 * Get a recording by ID
 *
 * @param {string} id - Recording UUID
 * @returns {Promise<Object|null>} Recording or null if not found
 */
export async function getRecording(id) {
  const result = await query(
    `SELECT r.id, r.call_session_id, r.storage_path, r.duration_seconds,
            r.file_size_bytes, r.format, r.created_at,
            cs.call_sid, cs.phone_number, cs.direction, cs.started_at, cs.ended_at
     FROM recordings r
     JOIN call_sessions cs ON r.call_session_id = cs.id
     WHERE r.id = $1`,
    [id]
  );

  return result.rows.length > 0 ? result.rows[0] : null;
}

/**
 * Get recordings by call session ID
 *
 * @param {string} callSessionId - Call session UUID
 * @returns {Promise<Object[]>} Recordings for the call
 */
export async function getRecordingsByCall(callSessionId) {
  const result = await query(
    `SELECT id, call_session_id, storage_path, duration_seconds,
            file_size_bytes, format, created_at
     FROM recordings
     WHERE call_session_id = $1
     ORDER BY created_at ASC`,
    [callSessionId]
  );

  return result.rows;
}

/**
 * Get recordings by Call SID
 *
 * @param {string} callSid - Twilio Call SID
 * @returns {Promise<Object[]>} Recordings for the call
 */
export async function getRecordingsByCallSid(callSid) {
  const result = await query(
    `SELECT r.id, r.call_session_id, r.storage_path, r.duration_seconds,
            r.file_size_bytes, r.format, r.created_at
     FROM recordings r
     JOIN call_sessions cs ON r.call_session_id = cs.id
     WHERE cs.call_sid = $1
     ORDER BY r.created_at ASC`,
    [callSid]
  );

  return result.rows;
}

/**
 * Get recordings by user with pagination
 *
 * @param {string} userId - User UUID
 * @param {Object} [options] - Query options
 * @param {number} [options.limit=50] - Maximum results
 * @param {number} [options.offset=0] - Offset for pagination
 * @returns {Promise<{recordings: Object[], total: number}>} Paginated recordings
 */
export async function getRecordingsByUser(userId, options = {}) {
  const { limit = 50, offset = 0 } = options;

  const queryText = `
    SELECT r.id, r.call_session_id, r.storage_path, r.duration_seconds,
           r.file_size_bytes, r.format, r.created_at,
           cs.call_sid, cs.phone_number, cs.direction
    FROM recordings r
    JOIN call_sessions cs ON r.call_session_id = cs.id
    WHERE cs.user_id = $1
    ORDER BY r.created_at DESC
    LIMIT $2 OFFSET $3
  `;

  const countQuery = `
    SELECT COUNT(*) as total
    FROM recordings r
    JOIN call_sessions cs ON r.call_session_id = cs.id
    WHERE cs.user_id = $1
  `;

  const [recordingsResult, countResult] = await Promise.all([
    query(queryText, [userId, limit, offset]),
    query(countQuery, [userId]),
  ]);

  return {
    recordings: recordingsResult.rows,
    total: parseInt(countResult.rows[0].total, 10),
  };
}

/**
 * List all recordings with optional filters
 *
 * @param {Object} [options] - Query options
 * @param {string} [options.userId] - Filter by user ID
 * @param {string} [options.callSid] - Filter by call SID
 * @param {number} [options.limit=50] - Maximum results
 * @param {number} [options.offset=0] - Offset for pagination
 * @returns {Promise<{recordings: Object[], total: number}>} Paginated recordings
 */
export async function listRecordings(options = {}) {
  const { userId, callSid, limit = 50, offset = 0 } = options;

  let queryText = `
    SELECT r.id, r.call_session_id, r.storage_path, r.duration_seconds,
           r.file_size_bytes, r.format, r.created_at,
           cs.call_sid, cs.phone_number, cs.direction
    FROM recordings r
    JOIN call_sessions cs ON r.call_session_id = cs.id
    WHERE 1=1
  `;

  let countQuery = `
    SELECT COUNT(*) as total
    FROM recordings r
    JOIN call_sessions cs ON r.call_session_id = cs.id
    WHERE 1=1
  `;

  const params = [];
  const countParams = [];
  let paramIndex = 1;
  let countParamIndex = 1;

  if (userId) {
    queryText += ` AND cs.user_id = $${paramIndex++}`;
    countQuery += ` AND cs.user_id = $${countParamIndex++}`;
    params.push(userId);
    countParams.push(userId);
  }

  if (callSid) {
    queryText += ` AND cs.call_sid = $${paramIndex++}`;
    countQuery += ` AND cs.call_sid = $${countParamIndex++}`;
    params.push(callSid);
    countParams.push(callSid);
  }

  queryText += ` ORDER BY r.created_at DESC LIMIT $${paramIndex++} OFFSET $${paramIndex++}`;
  params.push(limit, offset);

  const [recordingsResult, countResult] = await Promise.all([
    query(queryText, params),
    query(countQuery, countParams),
  ]);

  return {
    recordings: recordingsResult.rows,
    total: parseInt(countResult.rows[0].total, 10),
  };
}

/**
 * Update a recording
 *
 * @param {string} id - Recording UUID
 * @param {Object} updates - Fields to update
 * @returns {Promise<Object|null>} Updated recording or null if not found
 */
export async function updateRecording(id, updates) {
  const allowedFields = ['duration_seconds', 'file_size_bytes', 'format'];
  const updateParts = [];
  const params = [];
  let paramIndex = 1;

  for (const [key, value] of Object.entries(updates)) {
    if (allowedFields.includes(key)) {
      updateParts.push(`${key} = $${paramIndex++}`);
      params.push(value);
    }
  }

  if (updateParts.length === 0) {
    return null;
  }

  params.push(id);

  const result = await query(
    `UPDATE recordings SET ${updateParts.join(', ')}
     WHERE id = $${paramIndex}
     RETURNING id, call_session_id, storage_path, duration_seconds, file_size_bytes, format, created_at`,
    params
  );

  return result.rows.length > 0 ? result.rows[0] : null;
}

/**
 * Delete a recording
 *
 * @param {string} id - Recording UUID
 * @returns {Promise<{id: string, storage_path: string}|null>} Deleted recording info or null
 */
export async function deleteRecording(id) {
  const result = await query(
    'DELETE FROM recordings WHERE id = $1 RETURNING id, storage_path',
    [id]
  );

  if (result.rows.length > 0) {
    logger.info('Recording deleted', { id });
    return result.rows[0];
  }

  return null;
}

/**
 * Delete recordings by call session
 *
 * @param {string} callSessionId - Call session UUID
 * @returns {Promise<Object[]>} Deleted recordings with storage paths
 */
export async function deleteRecordingsByCall(callSessionId) {
  const result = await query(
    'DELETE FROM recordings WHERE call_session_id = $1 RETURNING id, storage_path',
    [callSessionId]
  );

  if (result.rows.length > 0) {
    logger.info('Recordings deleted for call', { callSessionId, count: result.rows.length });
  }

  return result.rows;
}

/**
 * Get recording storage statistics
 *
 * @param {Object} [options] - Filter options
 * @param {string} [options.userId] - Filter by user ID
 * @returns {Promise<Object>} Storage statistics
 */
export async function getStorageStats(options = {}) {
  const { userId } = options;

  let queryText = `
    SELECT
      COUNT(*) as total_recordings,
      COALESCE(SUM(duration_seconds), 0) as total_duration,
      COALESCE(SUM(file_size_bytes), 0) as total_size_bytes,
      COALESCE(AVG(duration_seconds) FILTER (WHERE duration_seconds IS NOT NULL), 0) as avg_duration,
      COALESCE(AVG(file_size_bytes) FILTER (WHERE file_size_bytes IS NOT NULL), 0) as avg_size
    FROM recordings r
  `;
  const params = [];

  if (userId) {
    queryText += `
      JOIN call_sessions cs ON r.call_session_id = cs.id
      WHERE cs.user_id = $1
    `;
    params.push(userId);
  }

  const result = await query(queryText, params);

  const row = result.rows[0];
  return {
    totalRecordings: parseInt(row.total_recordings, 10),
    totalDurationSeconds: parseInt(row.total_duration, 10),
    totalSizeBytes: parseInt(row.total_size_bytes, 10),
    totalSizeMB: (parseInt(row.total_size_bytes, 10) / (1024 * 1024)).toFixed(2),
    avgDurationSeconds: parseFloat(row.avg_duration),
    avgSizeBytes: parseFloat(row.avg_size),
  };
}

/**
 * Get orphaned recordings (DB entries with missing files)
 *
 * @returns {Promise<Object[]>} Orphaned recording entries
 */
export async function getOrphanedRecordings() {
  // This query returns all recordings - file existence must be checked in application code
  const result = await query(
    `SELECT id, storage_path, created_at
     FROM recordings
     ORDER BY created_at ASC`
  );

  return result.rows;
}

export default {
  createRecording,
  getRecording,
  getRecordingsByCall,
  getRecordingsByCallSid,
  getRecordingsByUser,
  listRecordings,
  updateRecording,
  deleteRecording,
  deleteRecordingsByCall,
  getStorageStats,
  getOrphanedRecordings,
};
