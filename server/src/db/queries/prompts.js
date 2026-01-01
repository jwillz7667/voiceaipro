/**
 * Prompts Database Queries
 *
 * CRUD operations for prompts table
 */

import { query, transaction } from '../pool.js';
import { createLogger } from '../../utils/logger.js';

const logger = createLogger('db:prompts');

/**
 * Create a new prompt
 *
 * @param {Object} data - Prompt data
 * @param {string} data.name - Prompt name
 * @param {string} data.instructions - AI instructions
 * @param {string} [data.userId] - Owner user ID
 * @param {string} [data.voice='marin'] - Voice to use
 * @param {Object} [data.vadConfig] - VAD configuration
 * @param {boolean} [data.isDefault=false] - Is default prompt
 * @returns {Promise<Object>} Created prompt
 */
export async function createPrompt(data) {
  const {
    name,
    instructions,
    userId,
    voice = 'marin',
    vadConfig,
    isDefault = false,
  } = data;

  const result = await query(
    `INSERT INTO prompts (user_id, name, instructions, voice, vad_config, is_default)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id, user_id, name, instructions, voice, vad_config, is_default, created_at, updated_at`,
    [userId || null, name, instructions, voice, vadConfig || null, isDefault]
  );

  logger.info('Prompt created', { id: result.rows[0].id, name });

  return result.rows[0];
}

/**
 * Update a prompt
 *
 * @param {string} id - Prompt UUID
 * @param {Object} updates - Fields to update
 * @returns {Promise<Object|null>} Updated prompt or null if not found
 */
export async function updatePrompt(id, updates) {
  const allowedFields = ['name', 'instructions', 'voice', 'vad_config', 'is_default'];
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

  // updated_at is handled by trigger, but include explicitly for safety
  updateParts.push('updated_at = CURRENT_TIMESTAMP');
  params.push(id);

  const result = await query(
    `UPDATE prompts SET ${updateParts.join(', ')}
     WHERE id = $${paramIndex}
     RETURNING id, user_id, name, instructions, voice, vad_config, is_default, created_at, updated_at`,
    params
  );

  if (result.rows.length > 0) {
    logger.debug('Prompt updated', { id, updates: Object.keys(updates) });
    return result.rows[0];
  }

  return null;
}

/**
 * Delete a prompt
 *
 * @param {string} id - Prompt UUID
 * @returns {Promise<{id: string, name: string}|null>} Deleted prompt info or null
 */
export async function deletePrompt(id) {
  const result = await query(
    'DELETE FROM prompts WHERE id = $1 RETURNING id, name',
    [id]
  );

  if (result.rows.length > 0) {
    logger.info('Prompt deleted', { id, name: result.rows[0].name });
    return result.rows[0];
  }

  return null;
}

/**
 * Get a prompt by ID
 *
 * @param {string} id - Prompt UUID
 * @returns {Promise<Object|null>} Prompt or null if not found
 */
export async function getPrompt(id) {
  const result = await query(
    `SELECT id, user_id, name, instructions, voice, vad_config, is_default, created_at, updated_at
     FROM prompts
     WHERE id = $1`,
    [id]
  );

  return result.rows.length > 0 ? result.rows[0] : null;
}

/**
 * Get prompts for a user (including system defaults)
 *
 * @param {string} userId - User UUID
 * @param {Object} [options] - Query options
 * @param {boolean} [options.includeDefaults=true] - Include system default prompts
 * @returns {Promise<Object[]>} User's prompts
 */
export async function getPromptsByUser(userId, options = {}) {
  const { includeDefaults = true } = options;

  let queryText = `
    SELECT id, user_id, name, instructions, voice, vad_config, is_default, created_at, updated_at
    FROM prompts
    WHERE user_id = $1
  `;

  if (includeDefaults) {
    queryText += ` OR (user_id IS NULL AND is_default = true)`;
  }

  queryText += ' ORDER BY is_default DESC, name ASC';

  const result = await query(queryText, [userId]);

  return result.rows;
}

/**
 * Get all prompts (admin function)
 *
 * @param {Object} [options] - Query options
 * @param {number} [options.limit=100] - Maximum results
 * @param {number} [options.offset=0] - Offset for pagination
 * @returns {Promise<{prompts: Object[], total: number}>} Paginated prompts
 */
export async function getAllPrompts(options = {}) {
  const { limit = 100, offset = 0 } = options;

  const [promptsResult, countResult] = await Promise.all([
    query(
      `SELECT id, user_id, name, instructions, voice, vad_config, is_default, created_at, updated_at
       FROM prompts
       ORDER BY is_default DESC, name ASC
       LIMIT $1 OFFSET $2`,
      [limit, offset]
    ),
    query('SELECT COUNT(*) as total FROM prompts'),
  ]);

  return {
    prompts: promptsResult.rows,
    total: parseInt(countResult.rows[0].total, 10),
  };
}

/**
 * Get default prompts (system-wide)
 *
 * @returns {Promise<Object[]>} Default prompts
 */
export async function getDefaultPrompts() {
  const result = await query(
    `SELECT id, user_id, name, instructions, voice, vad_config, is_default, created_at, updated_at
     FROM prompts
     WHERE is_default = true
     ORDER BY name ASC`
  );

  return result.rows;
}

/**
 * Get the user's selected default prompt
 *
 * @param {string} userId - User UUID
 * @returns {Promise<Object|null>} User's default prompt or system default
 */
export async function getUserDefaultPrompt(userId) {
  // First try to find user's specific default
  const userResult = await query(
    `SELECT id, user_id, name, instructions, voice, vad_config, is_default, created_at, updated_at
     FROM prompts
     WHERE user_id = $1 AND is_default = true
     LIMIT 1`,
    [userId]
  );

  if (userResult.rows.length > 0) {
    return userResult.rows[0];
  }

  // Fall back to system default
  const systemResult = await query(
    `SELECT id, user_id, name, instructions, voice, vad_config, is_default, created_at, updated_at
     FROM prompts
     WHERE user_id IS NULL AND is_default = true
     LIMIT 1`
  );

  return systemResult.rows.length > 0 ? systemResult.rows[0] : null;
}

/**
 * Set a prompt as the user's default
 * Clears any other default for the user first
 *
 * @param {string} userId - User UUID
 * @param {string} promptId - Prompt UUID to set as default
 * @returns {Promise<Object|null>} Updated prompt or null if not found
 */
export async function setDefaultPrompt(userId, promptId) {
  return transaction(async (client) => {
    // Clear existing user defaults
    await client.query(
      'UPDATE prompts SET is_default = false, updated_at = CURRENT_TIMESTAMP WHERE user_id = $1 AND is_default = true',
      [userId]
    );

    // Set new default
    const result = await client.query(
      `UPDATE prompts SET is_default = true, updated_at = CURRENT_TIMESTAMP
       WHERE id = $1 AND (user_id = $2 OR user_id IS NULL)
       RETURNING id, user_id, name, instructions, voice, vad_config, is_default, created_at, updated_at`,
      [promptId, userId]
    );

    if (result.rows.length > 0) {
      logger.info('Default prompt set', { userId, promptId });
      return result.rows[0];
    }

    return null;
  });
}

/**
 * Clear default prompt for a user
 *
 * @param {string} userId - User UUID
 * @returns {Promise<number>} Number of prompts updated
 */
export async function clearDefaultPrompt(userId) {
  const result = await query(
    'UPDATE prompts SET is_default = false, updated_at = CURRENT_TIMESTAMP WHERE user_id = $1 AND is_default = true',
    [userId]
  );

  return result.rowCount;
}

/**
 * Duplicate a prompt
 *
 * @param {string} id - Prompt UUID to duplicate
 * @param {Object} [options] - Options
 * @param {string} [options.newName] - New name for the duplicate
 * @param {string} [options.userId] - User ID for the duplicate
 * @returns {Promise<Object|null>} Duplicated prompt or null if original not found
 */
export async function duplicatePrompt(id, options = {}) {
  const original = await getPrompt(id);

  if (!original) {
    return null;
  }

  const { newName, userId } = options;

  const duplicatedName = newName || `${original.name} (Copy)`;

  return createPrompt({
    name: duplicatedName,
    instructions: original.instructions,
    userId: userId || original.user_id,
    voice: original.voice,
    vadConfig: original.vad_config,
    isDefault: false,
  });
}

/**
 * Search prompts by name
 *
 * @param {string} searchTerm - Search term
 * @param {Object} [options] - Query options
 * @param {string} [options.userId] - Filter by user ID
 * @param {number} [options.limit=20] - Maximum results
 * @returns {Promise<Object[]>} Matching prompts
 */
export async function searchPrompts(searchTerm, options = {}) {
  const { userId, limit = 20 } = options;

  let queryText = `
    SELECT id, user_id, name, instructions, voice, vad_config, is_default, created_at, updated_at
    FROM prompts
    WHERE name ILIKE $1
  `;
  const params = [`%${searchTerm}%`];
  let paramIndex = 2;

  if (userId) {
    queryText += ` AND (user_id = $${paramIndex++} OR user_id IS NULL)`;
    params.push(userId);
  }

  queryText += ` ORDER BY is_default DESC, name ASC LIMIT $${paramIndex}`;
  params.push(limit);

  const result = await query(queryText, params);

  return result.rows;
}

/**
 * Get prompt usage statistics
 *
 * @param {string} promptId - Prompt UUID
 * @returns {Promise<Object>} Usage statistics
 */
export async function getPromptUsageStats(promptId) {
  const result = await query(
    `SELECT
      COUNT(*) as total_calls,
      COUNT(*) FILTER (WHERE status = 'completed') as completed_calls,
      COALESCE(SUM(duration_seconds), 0) as total_duration,
      COALESCE(AVG(duration_seconds) FILTER (WHERE duration_seconds IS NOT NULL), 0) as avg_duration
     FROM call_sessions
     WHERE prompt_id = $1`,
    [promptId]
  );

  const row = result.rows[0];
  return {
    totalCalls: parseInt(row.total_calls, 10),
    completedCalls: parseInt(row.completed_calls, 10),
    totalDurationSeconds: parseInt(row.total_duration, 10),
    avgDurationSeconds: parseFloat(row.avg_duration),
  };
}

export default {
  createPrompt,
  updatePrompt,
  deletePrompt,
  getPrompt,
  getPromptsByUser,
  getAllPrompts,
  getDefaultPrompts,
  getUserDefaultPrompt,
  setDefaultPrompt,
  clearDefaultPrompt,
  duplicatePrompt,
  searchPrompts,
  getPromptUsageStats,
};
