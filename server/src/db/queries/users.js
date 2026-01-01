/**
 * Users Database Queries
 *
 * CRUD operations for users table
 */

import { query } from '../pool.js';
import { createLogger } from '../../utils/logger.js';

const logger = createLogger('db:users');

/**
 * Create or get a user by device ID
 * Uses upsert pattern - creates if not exists, updates last_active if exists
 *
 * @param {string} deviceId - Unique device identifier from iOS app
 * @returns {Promise<Object>} User record
 */
export async function getOrCreateUser(deviceId) {
  const result = await query(
    `INSERT INTO users (device_id, last_active)
     VALUES ($1, CURRENT_TIMESTAMP)
     ON CONFLICT (device_id)
     DO UPDATE SET last_active = CURRENT_TIMESTAMP
     RETURNING id, device_id, created_at, last_active`,
    [deviceId]
  );

  const user = result.rows[0];
  logger.debug('User accessed', { userId: user.id, deviceId });

  return user;
}

/**
 * Get a user by ID
 *
 * @param {string} id - User UUID
 * @returns {Promise<Object|null>} User or null if not found
 */
export async function getUser(id) {
  const result = await query(
    `SELECT id, device_id, created_at, last_active
     FROM users
     WHERE id = $1`,
    [id]
  );

  return result.rows.length > 0 ? result.rows[0] : null;
}

/**
 * Get a user by device ID
 *
 * @param {string} deviceId - Device identifier
 * @returns {Promise<Object|null>} User or null if not found
 */
export async function getUserByDeviceId(deviceId) {
  const result = await query(
    `SELECT id, device_id, created_at, last_active
     FROM users
     WHERE device_id = $1`,
    [deviceId]
  );

  return result.rows.length > 0 ? result.rows[0] : null;
}

/**
 * Update user's last active timestamp
 *
 * @param {string} id - User UUID
 * @returns {Promise<Object|null>} Updated user or null if not found
 */
export async function updateLastActive(id) {
  const result = await query(
    `UPDATE users SET last_active = CURRENT_TIMESTAMP
     WHERE id = $1
     RETURNING id, device_id, created_at, last_active`,
    [id]
  );

  return result.rows.length > 0 ? result.rows[0] : null;
}

/**
 * Delete a user
 *
 * @param {string} id - User UUID
 * @returns {Promise<boolean>} True if deleted, false if not found
 */
export async function deleteUser(id) {
  const result = await query(
    'DELETE FROM users WHERE id = $1 RETURNING id',
    [id]
  );

  if (result.rows.length > 0) {
    logger.info('User deleted', { userId: id });
    return true;
  }

  return false;
}

/**
 * List all users with pagination
 *
 * @param {Object} [options] - Query options
 * @param {number} [options.limit=50] - Maximum results
 * @param {number} [options.offset=0] - Offset for pagination
 * @param {string} [options.orderBy='last_active'] - Order by column
 * @param {string} [options.order='DESC'] - Sort order
 * @returns {Promise<{users: Object[], total: number}>} Paginated users
 */
export async function listUsers(options = {}) {
  const {
    limit = 50,
    offset = 0,
    orderBy = 'last_active',
    order = 'DESC',
  } = options;

  // Validate orderBy to prevent SQL injection
  const allowedOrderBy = ['id', 'device_id', 'created_at', 'last_active'];
  const safeOrderBy = allowedOrderBy.includes(orderBy) ? orderBy : 'last_active';
  const safeOrder = order.toUpperCase() === 'ASC' ? 'ASC' : 'DESC';

  const [usersResult, countResult] = await Promise.all([
    query(
      `SELECT id, device_id, created_at, last_active
       FROM users
       ORDER BY ${safeOrderBy} ${safeOrder}
       LIMIT $1 OFFSET $2`,
      [limit, offset]
    ),
    query('SELECT COUNT(*) as total FROM users'),
  ]);

  return {
    users: usersResult.rows,
    total: parseInt(countResult.rows[0].total, 10),
  };
}

/**
 * Get active users (active within specified days)
 *
 * @param {number} [daysActive=7] - Consider active if within this many days
 * @returns {Promise<Object[]>} Active users
 */
export async function getActiveUsers(daysActive = 7) {
  const result = await query(
    `SELECT id, device_id, created_at, last_active
     FROM users
     WHERE last_active > NOW() - INTERVAL '${daysActive} days'
     ORDER BY last_active DESC`
  );

  return result.rows;
}

/**
 * Get user statistics
 *
 * @param {string} userId - User UUID
 * @returns {Promise<Object>} User statistics
 */
export async function getUserStats(userId) {
  const result = await query(
    `SELECT
      (SELECT COUNT(*) FROM call_sessions WHERE user_id = $1) as total_calls,
      (SELECT COUNT(*) FROM call_sessions WHERE user_id = $1 AND direction = 'outbound') as outbound_calls,
      (SELECT COUNT(*) FROM call_sessions WHERE user_id = $1 AND direction = 'inbound') as inbound_calls,
      (SELECT COALESCE(SUM(duration_seconds), 0) FROM call_sessions WHERE user_id = $1) as total_duration,
      (SELECT COUNT(*) FROM prompts WHERE user_id = $1) as custom_prompts,
      (
        SELECT COUNT(*)
        FROM recordings r
        JOIN call_sessions cs ON r.call_session_id = cs.id
        WHERE cs.user_id = $1
      ) as recordings
    `,
    [userId]
  );

  const row = result.rows[0];
  return {
    totalCalls: parseInt(row.total_calls, 10),
    outboundCalls: parseInt(row.outbound_calls, 10),
    inboundCalls: parseInt(row.inbound_calls, 10),
    totalDurationSeconds: parseInt(row.total_duration, 10),
    customPrompts: parseInt(row.custom_prompts, 10),
    recordings: parseInt(row.recordings, 10),
  };
}

/**
 * Delete inactive users
 *
 * @param {number} daysInactive - Delete users inactive for this many days
 * @returns {Promise<number>} Number of deleted users
 */
export async function deleteInactiveUsers(daysInactive = 365) {
  const result = await query(
    `DELETE FROM users
     WHERE last_active < NOW() - INTERVAL '${daysInactive} days'
     RETURNING id`,
    []
  );

  if (result.rowCount > 0) {
    logger.info('Inactive users deleted', { count: result.rowCount, daysInactive });
  }

  return result.rowCount;
}

/**
 * Get global user statistics
 *
 * @returns {Promise<Object>} Global statistics
 */
export async function getGlobalStats() {
  const result = await query(`
    SELECT
      COUNT(*) as total_users,
      COUNT(*) FILTER (WHERE last_active > NOW() - INTERVAL '1 day') as active_today,
      COUNT(*) FILTER (WHERE last_active > NOW() - INTERVAL '7 days') as active_week,
      COUNT(*) FILTER (WHERE last_active > NOW() - INTERVAL '30 days') as active_month,
      COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 day') as new_today,
      COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days') as new_week
    FROM users
  `);

  const row = result.rows[0];
  return {
    totalUsers: parseInt(row.total_users, 10),
    activeToday: parseInt(row.active_today, 10),
    activeWeek: parseInt(row.active_week, 10),
    activeMonth: parseInt(row.active_month, 10),
    newToday: parseInt(row.new_today, 10),
    newWeek: parseInt(row.new_week, 10),
  };
}

export default {
  getOrCreateUser,
  getUser,
  getUserByDeviceId,
  updateLastActive,
  deleteUser,
  listUsers,
  getActiveUsers,
  getUserStats,
  deleteInactiveUsers,
  getGlobalStats,
};
