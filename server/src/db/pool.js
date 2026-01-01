import pg from 'pg';
import config from '../config/environment.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('db');

const poolConfig = {
  connectionString: config.database.url,
  min: config.database.poolMin,
  max: config.database.poolMax,
  idleTimeoutMillis: config.database.idleTimeoutMs,
  connectionTimeoutMillis: config.database.connectionTimeoutMs,
  ssl: config.isProduction() ? { rejectUnauthorized: false } : false,
};

const pool = new pg.Pool(poolConfig);

pool.on('connect', (client) => {
  logger.debug('New database connection established', {
    totalCount: pool.totalCount,
    idleCount: pool.idleCount,
    waitingCount: pool.waitingCount,
  });
});

pool.on('error', (err, client) => {
  logger.error('Unexpected database pool error', err);
});

pool.on('remove', (client) => {
  logger.debug('Database connection removed from pool', {
    totalCount: pool.totalCount,
    idleCount: pool.idleCount,
  });
});

export async function query(text, params) {
  const start = Date.now();
  try {
    const result = await pool.query(text, params);
    const duration = Date.now() - start;

    logger.trace('Database query executed', {
      query: text.substring(0, 100),
      duration: `${duration}ms`,
      rowCount: result.rowCount,
    });

    return result;
  } catch (error) {
    logger.error('Database query failed', {
      query: text.substring(0, 100),
      error: error.message,
    });
    throw error;
  }
}

export async function getClient() {
  const client = await pool.connect();
  const originalQuery = client.query.bind(client);
  const originalRelease = client.release.bind(client);

  let released = false;

  client.query = async (text, params) => {
    const start = Date.now();
    try {
      const result = await originalQuery(text, params);
      const duration = Date.now() - start;

      logger.trace('Transaction query executed', {
        query: text.substring(0, 100),
        duration: `${duration}ms`,
        rowCount: result.rowCount,
      });

      return result;
    } catch (error) {
      logger.error('Transaction query failed', {
        query: text.substring(0, 100),
        error: error.message,
      });
      throw error;
    }
  };

  client.release = () => {
    if (released) {
      logger.warn('Client already released, ignoring duplicate release');
      return;
    }
    released = true;
    originalRelease();
  };

  return client;
}

export async function transaction(callback) {
  const client = await getClient();
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function testConnection() {
  try {
    const result = await query('SELECT NOW() as now');
    logger.info('Database connection test successful', {
      serverTime: result.rows[0].now,
    });
    return true;
  } catch (error) {
    logger.error('Database connection test failed', error);
    return false;
  }
}

export async function closePool() {
  logger.info('Closing database pool');
  await pool.end();
  logger.info('Database pool closed');
}

export function getPoolStats() {
  return {
    totalCount: pool.totalCount,
    idleCount: pool.idleCount,
    waitingCount: pool.waitingCount,
  };
}

export default pool;
