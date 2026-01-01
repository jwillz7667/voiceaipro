/**
 * Transcripts Database Queries
 *
 * CRUD operations for transcripts table
 */

import { query } from '../pool.js';
import { createLogger } from '../../utils/logger.js';

const logger = createLogger('db:transcripts');

/**
 * Add a transcript entry
 *
 * @param {Object} data - Transcript data
 * @param {string} data.callSessionId - Call session UUID
 * @param {string} data.speaker - 'user' or 'assistant'
 * @param {string} data.content - Transcript text
 * @param {number} [data.timestampMs] - Milliseconds from call start
 * @returns {Promise<Object>} Created transcript
 */
export async function addTranscript(data) {
  const { callSessionId, speaker, content, timestampMs } = data;

  const result = await query(
    `INSERT INTO transcripts (call_session_id, speaker, content, timestamp_ms)
     VALUES ($1, $2, $3, $4)
     RETURNING id, call_session_id, speaker, content, timestamp_ms, created_at`,
    [callSessionId, speaker, content, timestampMs || null]
  );

  logger.debug('Transcript added', {
    id: result.rows[0].id,
    speaker,
    contentLength: content.length,
  });

  return result.rows[0];
}

/**
 * Add multiple transcripts in batch
 *
 * @param {Object[]} transcripts - Array of transcript data
 * @returns {Promise<Object[]>} Created transcripts
 */
export async function addTranscriptsBatch(transcripts) {
  if (!transcripts || transcripts.length === 0) {
    return [];
  }

  const values = transcripts.map((t, i) => {
    const offset = i * 4;
    return `($${offset + 1}, $${offset + 2}, $${offset + 3}, $${offset + 4})`;
  });

  const params = transcripts.flatMap(t => [
    t.callSessionId,
    t.speaker,
    t.content,
    t.timestampMs || null,
  ]);

  const result = await query(
    `INSERT INTO transcripts (call_session_id, speaker, content, timestamp_ms)
     VALUES ${values.join(', ')}
     RETURNING id, call_session_id, speaker, content, timestamp_ms, created_at`,
    params
  );

  logger.debug('Transcripts batch added', { count: result.rows.length });

  return result.rows;
}

/**
 * Get transcripts for a call session
 *
 * @param {string} callSessionId - Call session UUID
 * @param {Object} [options] - Query options
 * @param {string} [options.speaker] - Filter by speaker
 * @param {number} [options.limit] - Maximum results
 * @param {number} [options.offset=0] - Offset for pagination
 * @returns {Promise<Object[]>} Transcripts for the call
 */
export async function getTranscriptsByCall(callSessionId, options = {}) {
  const { speaker, limit, offset = 0 } = options;

  let queryText = `
    SELECT id, call_session_id, speaker, content, timestamp_ms, created_at
    FROM transcripts
    WHERE call_session_id = $1
  `;
  const params = [callSessionId];
  let paramIndex = 2;

  if (speaker) {
    queryText += ` AND speaker = $${paramIndex++}`;
    params.push(speaker);
  }

  queryText += ' ORDER BY timestamp_ms ASC, created_at ASC';

  if (limit) {
    queryText += ` LIMIT $${paramIndex++}`;
    params.push(limit);
  }

  if (offset) {
    queryText += ` OFFSET $${paramIndex++}`;
    params.push(offset);
  }

  const result = await query(queryText, params);

  return result.rows;
}

/**
 * Get transcripts by Call SID
 *
 * @param {string} callSid - Twilio Call SID
 * @param {Object} [options] - Query options
 * @returns {Promise<Object[]>} Transcripts for the call
 */
export async function getTranscriptsByCallSid(callSid, options = {}) {
  const { speaker } = options;

  let queryText = `
    SELECT t.id, t.call_session_id, t.speaker, t.content, t.timestamp_ms, t.created_at
    FROM transcripts t
    JOIN call_sessions cs ON t.call_session_id = cs.id
    WHERE cs.call_sid = $1
  `;
  const params = [callSid];
  let paramIndex = 2;

  if (speaker) {
    queryText += ` AND t.speaker = $${paramIndex++}`;
    params.push(speaker);
  }

  queryText += ' ORDER BY t.timestamp_ms ASC, t.created_at ASC';

  const result = await query(queryText, params);

  return result.rows;
}

/**
 * Get a single transcript by ID
 *
 * @param {string} id - Transcript UUID
 * @returns {Promise<Object|null>} Transcript or null if not found
 */
export async function getTranscript(id) {
  const result = await query(
    `SELECT id, call_session_id, speaker, content, timestamp_ms, created_at
     FROM transcripts
     WHERE id = $1`,
    [id]
  );

  return result.rows.length > 0 ? result.rows[0] : null;
}

/**
 * Update a transcript
 *
 * @param {string} id - Transcript UUID
 * @param {Object} updates - Fields to update
 * @returns {Promise<Object|null>} Updated transcript or null if not found
 */
export async function updateTranscript(id, updates) {
  const allowedFields = ['content', 'timestamp_ms'];
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
    `UPDATE transcripts SET ${updateParts.join(', ')}
     WHERE id = $${paramIndex}
     RETURNING id, call_session_id, speaker, content, timestamp_ms, created_at`,
    params
  );

  return result.rows.length > 0 ? result.rows[0] : null;
}

/**
 * Delete a transcript
 *
 * @param {string} id - Transcript UUID
 * @returns {Promise<boolean>} True if deleted, false if not found
 */
export async function deleteTranscript(id) {
  const result = await query(
    'DELETE FROM transcripts WHERE id = $1 RETURNING id',
    [id]
  );

  return result.rows.length > 0;
}

/**
 * Delete all transcripts for a call
 *
 * @param {string} callSessionId - Call session UUID
 * @returns {Promise<number>} Number of deleted transcripts
 */
export async function deleteTranscriptsByCall(callSessionId) {
  const result = await query(
    'DELETE FROM transcripts WHERE call_session_id = $1 RETURNING id',
    [callSessionId]
  );

  if (result.rowCount > 0) {
    logger.info('Transcripts deleted for call', { callSessionId, count: result.rowCount });
  }

  return result.rowCount;
}

/**
 * Get full transcript text for a call
 *
 * @param {string} callSessionId - Call session UUID
 * @param {Object} [options] - Options
 * @param {boolean} [options.includeTimestamps=false] - Include timestamps
 * @param {boolean} [options.includeSpeaker=true] - Include speaker labels
 * @returns {Promise<string>} Formatted transcript text
 */
export async function getFullTranscriptText(callSessionId, options = {}) {
  const { includeTimestamps = false, includeSpeaker = true } = options;

  const transcripts = await getTranscriptsByCall(callSessionId);

  return transcripts.map(t => {
    let line = '';

    if (includeTimestamps && t.timestamp_ms !== null) {
      const seconds = Math.floor(t.timestamp_ms / 1000);
      const minutes = Math.floor(seconds / 60);
      const secs = seconds % 60;
      line += `[${minutes}:${secs.toString().padStart(2, '0')}] `;
    }

    if (includeSpeaker) {
      line += `${t.speaker === 'user' ? 'User' : 'Assistant'}: `;
    }

    line += t.content;

    return line;
  }).join('\n');
}

/**
 * Search transcripts by content
 *
 * @param {string} searchTerm - Text to search for
 * @param {Object} [options] - Query options
 * @param {string} [options.userId] - Filter by user ID
 * @param {number} [options.limit=50] - Maximum results
 * @returns {Promise<Object[]>} Matching transcripts with call info
 */
export async function searchTranscripts(searchTerm, options = {}) {
  const { userId, limit = 50 } = options;

  let queryText = `
    SELECT t.id, t.call_session_id, t.speaker, t.content, t.timestamp_ms, t.created_at,
           cs.call_sid, cs.phone_number, cs.direction, cs.started_at
    FROM transcripts t
    JOIN call_sessions cs ON t.call_session_id = cs.id
    WHERE t.content ILIKE $1
  `;
  const params = [`%${searchTerm}%`];
  let paramIndex = 2;

  if (userId) {
    queryText += ` AND cs.user_id = $${paramIndex++}`;
    params.push(userId);
  }

  queryText += ` ORDER BY cs.started_at DESC, t.timestamp_ms ASC LIMIT $${paramIndex}`;
  params.push(limit);

  const result = await query(queryText, params);

  return result.rows;
}

/**
 * Get transcript statistics for a call
 *
 * @param {string} callSessionId - Call session UUID
 * @returns {Promise<Object>} Transcript statistics
 */
export async function getTranscriptStats(callSessionId) {
  const result = await query(
    `SELECT
      COUNT(*) as total_entries,
      COUNT(*) FILTER (WHERE speaker = 'user') as user_entries,
      COUNT(*) FILTER (WHERE speaker = 'assistant') as assistant_entries,
      COALESCE(SUM(LENGTH(content)), 0) as total_characters,
      COALESCE(SUM(LENGTH(content)) FILTER (WHERE speaker = 'user'), 0) as user_characters,
      COALESCE(SUM(LENGTH(content)) FILTER (WHERE speaker = 'assistant'), 0) as assistant_characters,
      COALESCE(MAX(timestamp_ms), 0) as last_timestamp_ms
     FROM transcripts
     WHERE call_session_id = $1`,
    [callSessionId]
  );

  const row = result.rows[0];
  return {
    totalEntries: parseInt(row.total_entries, 10),
    userEntries: parseInt(row.user_entries, 10),
    assistantEntries: parseInt(row.assistant_entries, 10),
    totalCharacters: parseInt(row.total_characters, 10),
    userCharacters: parseInt(row.user_characters, 10),
    assistantCharacters: parseInt(row.assistant_characters, 10),
    lastTimestampMs: parseInt(row.last_timestamp_ms, 10),
  };
}

export default {
  addTranscript,
  addTranscriptsBatch,
  getTranscriptsByCall,
  getTranscriptsByCallSid,
  getTranscript,
  updateTranscript,
  deleteTranscript,
  deleteTranscriptsByCall,
  getFullTranscriptText,
  searchTranscripts,
  getTranscriptStats,
};
