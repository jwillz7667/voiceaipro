/**
 * Call Session Database Queries
 *
 * CRUD operations for call_sessions and call_events tables
 */

import { query, transaction } from '../pool.js';
import { createLogger } from '../../utils/logger.js';

const logger = createLogger('db:calls');

/**
 * Create a new call session
 *
 * @param {Object} data - Call session data
 * @param {string} data.callSid - Twilio Call SID
 * @param {string} data.direction - 'inbound' or 'outbound'
 * @param {string} data.phoneNumber - Phone number
 * @param {string} [data.userId] - User ID
 * @param {string} [data.promptId] - Prompt ID used for this call
 * @param {Object} [data.configSnapshot] - Configuration snapshot
 * @returns {Promise<Object>} Created call session
 */
export async function createCallSession(data) {
  const {
    callSid,
    direction,
    phoneNumber,
    userId,
    promptId,
    configSnapshot,
  } = data;

  const result = await query(
    `INSERT INTO call_sessions (call_sid, direction, phone_number, user_id, prompt_id, config_snapshot, status)
     VALUES ($1, $2, $3, $4, $5, $6, 'initializing')
     RETURNING id, call_sid, direction, phone_number, user_id, prompt_id, status,
               started_at, ended_at, duration_seconds, config_snapshot`,
    [callSid, direction, phoneNumber, userId || null, promptId || null, configSnapshot || null]
  );

  logger.info('Call session created', { callSid, id: result.rows[0].id });

  return result.rows[0];
}

/**
 * Update a call session
 *
 * @param {string} callSid - Twilio Call SID
 * @param {Object} updates - Fields to update
 * @returns {Promise<Object|null>} Updated call session or null if not found
 */
export async function updateCallSession(callSid, updates) {
  const allowedFields = ['status', 'ended_at', 'duration_seconds', 'config_snapshot'];
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

  params.push(callSid);

  const result = await query(
    `UPDATE call_sessions SET ${updateParts.join(', ')}
     WHERE call_sid = $${paramIndex}
     RETURNING id, call_sid, direction, phone_number, user_id, prompt_id, status,
               started_at, ended_at, duration_seconds, config_snapshot`,
    params
  );

  if (result.rows.length === 0) {
    return null;
  }

  logger.debug('Call session updated', { callSid, updates: Object.keys(updates) });

  return result.rows[0];
}

/**
 * Get a call session by Call SID
 *
 * @param {string} callSid - Twilio Call SID
 * @returns {Promise<Object|null>} Call session or null if not found
 */
export async function getCallSession(callSid) {
  const result = await query(
    `SELECT cs.id, cs.call_sid, cs.direction, cs.phone_number, cs.user_id,
            cs.prompt_id, cs.status, cs.started_at, cs.ended_at,
            cs.duration_seconds, cs.config_snapshot,
            p.name as prompt_name, p.instructions as prompt_instructions
     FROM call_sessions cs
     LEFT JOIN prompts p ON cs.prompt_id = p.id
     WHERE cs.call_sid = $1`,
    [callSid]
  );

  return result.rows.length > 0 ? result.rows[0] : null;
}

/**
 * Get a call session by ID
 *
 * @param {string} id - Call session UUID
 * @returns {Promise<Object|null>} Call session or null if not found
 */
export async function getCallSessionById(id) {
  const result = await query(
    `SELECT cs.id, cs.call_sid, cs.direction, cs.phone_number, cs.user_id,
            cs.prompt_id, cs.status, cs.started_at, cs.ended_at,
            cs.duration_seconds, cs.config_snapshot,
            p.name as prompt_name, p.instructions as prompt_instructions
     FROM call_sessions cs
     LEFT JOIN prompts p ON cs.prompt_id = p.id
     WHERE cs.id = $1`,
    [id]
  );

  return result.rows.length > 0 ? result.rows[0] : null;
}

/**
 * Get call history with pagination
 *
 * @param {Object} options - Query options
 * @param {string} [options.userId] - Filter by user ID
 * @param {string} [options.direction] - Filter by direction ('inbound' or 'outbound')
 * @param {string} [options.status] - Filter by status
 * @param {number} [options.limit=50] - Maximum results
 * @param {number} [options.offset=0] - Offset for pagination
 * @returns {Promise<{calls: Object[], total: number}>} Paginated call history
 */
export async function getCallHistory(options = {}) {
  const {
    userId,
    direction,
    status,
    limit = 50,
    offset = 0,
  } = options;

  let queryText = `
    SELECT cs.id, cs.call_sid, cs.direction, cs.phone_number, cs.user_id,
           cs.status, cs.started_at, cs.ended_at, cs.duration_seconds,
           p.name as prompt_name
    FROM call_sessions cs
    LEFT JOIN prompts p ON cs.prompt_id = p.id
    WHERE 1=1
  `;

  let countQuery = 'SELECT COUNT(*) as total FROM call_sessions WHERE 1=1';
  const params = [];
  const countParams = [];
  let paramIndex = 1;
  let countParamIndex = 1;

  if (userId) {
    queryText += ` AND cs.user_id = $${paramIndex++}`;
    countQuery += ` AND user_id = $${countParamIndex++}`;
    params.push(userId);
    countParams.push(userId);
  }

  if (direction) {
    queryText += ` AND cs.direction = $${paramIndex++}`;
    countQuery += ` AND direction = $${countParamIndex++}`;
    params.push(direction);
    countParams.push(direction);
  }

  if (status) {
    queryText += ` AND cs.status = $${paramIndex++}`;
    countQuery += ` AND status = $${countParamIndex++}`;
    params.push(status);
    countParams.push(status);
  }

  queryText += ` ORDER BY cs.started_at DESC LIMIT $${paramIndex++} OFFSET $${paramIndex++}`;
  params.push(limit, offset);

  const [callsResult, countResult] = await Promise.all([
    query(queryText, params),
    query(countQuery, countParams),
  ]);

  return {
    calls: callsResult.rows,
    total: parseInt(countResult.rows[0].total, 10),
  };
}

/**
 * Get full call details including events and transcripts
 *
 * @param {string} callSid - Twilio Call SID
 * @returns {Promise<Object|null>} Full call details or null if not found
 */
export async function getFullCallDetails(callSid) {
  const session = await getCallSession(callSid);

  if (!session) {
    return null;
  }

  // Get events and transcripts in parallel
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

  return {
    ...session,
    events: eventsResult.rows,
    transcripts: transcriptsResult.rows,
    recordings: recordingsResult.rows,
  };
}

/**
 * Get events for a call session
 *
 * @param {string} callSessionId - Call session UUID
 * @param {Object} [options] - Query options
 * @param {string} [options.eventType] - Filter by event type
 * @param {number} [options.limit=100] - Maximum results
 * @param {number} [options.offset=0] - Offset for pagination
 * @returns {Promise<Object[]>} Call events
 */
export async function getCallEvents(callSessionId, options = {}) {
  const { eventType, limit = 100, offset = 0 } = options;

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

  queryText += ` ORDER BY created_at ASC LIMIT $${paramIndex++} OFFSET $${paramIndex++}`;
  params.push(limit, offset);

  const result = await query(queryText, params);
  return result.rows;
}

/**
 * Log a call event
 *
 * @param {Object} data - Event data
 * @param {string} data.callSessionId - Call session UUID
 * @param {string} data.eventType - Type of event
 * @param {string} data.direction - 'incoming' or 'outgoing'
 * @param {Object} [data.payload] - Event payload
 * @returns {Promise<Object>} Created event
 */
export async function logCallEvent(data) {
  const { callSessionId, eventType, direction, payload } = data;

  const result = await query(
    `INSERT INTO call_events (call_session_id, event_type, direction, payload)
     VALUES ($1, $2, $3, $4)
     RETURNING id, event_type, direction, payload, created_at`,
    [callSessionId, eventType, direction, payload || null]
  );

  return result.rows[0];
}

/**
 * End a call session
 *
 * @param {string} callSid - Twilio Call SID
 * @param {number} [durationSeconds] - Call duration in seconds
 * @returns {Promise<Object|null>} Updated call session or null if not found
 */
export async function endCallSession(callSid, durationSeconds) {
  return updateCallSession(callSid, {
    status: 'completed',
    ended_at: new Date(),
    duration_seconds: durationSeconds || null,
  });
}

/**
 * Get call statistics
 *
 * @param {Object} [options] - Filter options
 * @param {string} [options.userId] - Filter by user ID
 * @param {Date} [options.startDate] - Start date filter
 * @param {Date} [options.endDate] - End date filter
 * @returns {Promise<Object>} Call statistics
 */
export async function getCallStats(options = {}) {
  const { userId, startDate, endDate } = options;

  let queryText = `
    SELECT
      COUNT(*) as total_calls,
      COUNT(*) FILTER (WHERE direction = 'inbound') as inbound_calls,
      COUNT(*) FILTER (WHERE direction = 'outbound') as outbound_calls,
      COUNT(*) FILTER (WHERE status = 'completed') as completed_calls,
      COUNT(*) FILTER (WHERE status = 'failed') as failed_calls,
      COALESCE(AVG(duration_seconds) FILTER (WHERE duration_seconds IS NOT NULL), 0) as avg_duration,
      COALESCE(SUM(duration_seconds) FILTER (WHERE duration_seconds IS NOT NULL), 0) as total_duration
    FROM call_sessions
    WHERE 1=1
  `;
  const params = [];
  let paramIndex = 1;

  if (userId) {
    queryText += ` AND user_id = $${paramIndex++}`;
    params.push(userId);
  }

  if (startDate) {
    queryText += ` AND started_at >= $${paramIndex++}`;
    params.push(startDate);
  }

  if (endDate) {
    queryText += ` AND started_at <= $${paramIndex++}`;
    params.push(endDate);
  }

  const result = await query(queryText, params);

  return {
    totalCalls: parseInt(result.rows[0].total_calls, 10),
    inboundCalls: parseInt(result.rows[0].inbound_calls, 10),
    outboundCalls: parseInt(result.rows[0].outbound_calls, 10),
    completedCalls: parseInt(result.rows[0].completed_calls, 10),
    failedCalls: parseInt(result.rows[0].failed_calls, 10),
    avgDuration: parseFloat(result.rows[0].avg_duration),
    totalDuration: parseInt(result.rows[0].total_duration, 10),
  };
}

/**
 * Delete old call sessions
 *
 * @param {number} daysOld - Delete sessions older than this many days
 * @returns {Promise<number>} Number of deleted sessions
 */
export async function deleteOldCallSessions(daysOld = 90) {
  const result = await query(
    `DELETE FROM call_sessions
     WHERE started_at < NOW() - INTERVAL '${daysOld} days'
     RETURNING id`,
    []
  );

  logger.info('Old call sessions deleted', { count: result.rowCount, daysOld });

  return result.rowCount;
}

export default {
  createCallSession,
  updateCallSession,
  getCallSession,
  getCallSessionById,
  getCallHistory,
  getFullCallDetails,
  getCallEvents,
  logCallEvent,
  endCallSession,
  getCallStats,
  deleteOldCallSessions,
};
