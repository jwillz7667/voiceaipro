import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import pg from 'pg';
import 'dotenv/config';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const MIGRATIONS_DIR = path.join(__dirname, 'migrations');

async function getMigrationsConnection() {
  const connectionString = process.env.DATABASE_URL;

  if (!connectionString) {
    console.error('ERROR: DATABASE_URL environment variable is not set');
    process.exit(1);
  }

  const pool = new pg.Pool({
    connectionString,
    ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
  });

  return pool;
}

async function ensureMigrationsTable(pool) {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id SERIAL PRIMARY KEY,
      filename VARCHAR(255) NOT NULL UNIQUE,
      applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    )
  `);
}

async function getAppliedMigrations(pool) {
  const result = await pool.query(
    'SELECT filename FROM schema_migrations ORDER BY filename'
  );
  return new Set(result.rows.map((row) => row.filename));
}

async function getMigrationFiles() {
  try {
    const files = await fs.promises.readdir(MIGRATIONS_DIR);
    return files
      .filter((f) => f.endsWith('.sql'))
      .sort();
  } catch (error) {
    if (error.code === 'ENOENT') {
      console.log('No migrations directory found');
      return [];
    }
    throw error;
  }
}

async function runMigration(pool, filename) {
  const filePath = path.join(MIGRATIONS_DIR, filename);
  const sql = await fs.promises.readFile(filePath, 'utf-8');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    console.log(`Applying migration: ${filename}`);

    const statements = sql
      .split(/;\s*$/m)
      .map((s) => s.trim())
      .filter((s) => s.length > 0 && !s.startsWith('--'));

    for (const statement of statements) {
      if (statement.length > 0) {
        await client.query(statement);
      }
    }

    await client.query(
      'INSERT INTO schema_migrations (filename) VALUES ($1)',
      [filename]
    );

    await client.query('COMMIT');
    console.log(`Migration applied successfully: ${filename}`);
  } catch (error) {
    await client.query('ROLLBACK');
    console.error(`Migration failed: ${filename}`);
    throw error;
  } finally {
    client.release();
  }
}

async function migrate() {
  console.log('Starting database migration...');

  const pool = await getMigrationsConnection();

  try {
    await ensureMigrationsTable(pool);

    const appliedMigrations = await getAppliedMigrations(pool);
    const migrationFiles = await getMigrationFiles();

    const pendingMigrations = migrationFiles.filter(
      (f) => !appliedMigrations.has(f)
    );

    if (pendingMigrations.length === 0) {
      console.log('No pending migrations');
      return;
    }

    console.log(`Found ${pendingMigrations.length} pending migration(s)`);

    for (const filename of pendingMigrations) {
      await runMigration(pool, filename);
    }

    console.log('All migrations completed successfully');
  } catch (error) {
    console.error('Migration error:', error.message);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

async function rollback(count = 1) {
  console.log(`Rolling back ${count} migration(s)...`);

  const pool = await getMigrationsConnection();

  try {
    const result = await pool.query(
      'SELECT filename FROM schema_migrations ORDER BY filename DESC LIMIT $1',
      [count]
    );

    if (result.rows.length === 0) {
      console.log('No migrations to rollback');
      return;
    }

    for (const row of result.rows) {
      console.log(`Removing migration record: ${row.filename}`);
      await pool.query(
        'DELETE FROM schema_migrations WHERE filename = $1',
        [row.filename]
      );
    }

    console.log('Rollback completed. Note: This only removes migration records.');
    console.log('You may need to manually reverse schema changes.');
  } finally {
    await pool.end();
  }
}

async function status() {
  const pool = await getMigrationsConnection();

  try {
    await ensureMigrationsTable(pool);

    const appliedMigrations = await getAppliedMigrations(pool);
    const migrationFiles = await getMigrationFiles();

    console.log('\nMigration Status:');
    console.log('=================\n');

    for (const filename of migrationFiles) {
      const status = appliedMigrations.has(filename) ? '[APPLIED]' : '[PENDING]';
      console.log(`${status} ${filename}`);
    }

    const pending = migrationFiles.filter((f) => !appliedMigrations.has(f));
    console.log(`\nTotal: ${migrationFiles.length} migration(s), ${pending.length} pending`);
  } finally {
    await pool.end();
  }
}

const command = process.argv[2] || 'up';

switch (command) {
  case 'up':
  case 'migrate':
    migrate();
    break;
  case 'down':
  case 'rollback':
    const count = parseInt(process.argv[3]) || 1;
    rollback(count);
    break;
  case 'status':
    status();
    break;
  default:
    console.log('Usage: node migrate.js [up|down|status]');
    console.log('  up, migrate  - Apply pending migrations');
    console.log('  down [n]     - Rollback n migrations (default: 1)');
    console.log('  status       - Show migration status');
    process.exit(1);
}
