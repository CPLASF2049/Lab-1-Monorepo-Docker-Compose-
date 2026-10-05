'use strict';

const express = require('express');
const { Pool } = require('pg');

const PORT = Number(process.env.PORT || 3000);
const DB_HOST = process.env.DB_HOST || 'db';
const DB_PORT = Number(process.env.DB_PORT || 5432);
const DB_NAME = process.env.DB_NAME || 'counterdb';
const DB_USER = process.env.DB_USER || 'counter';
const DB_PASSWORD = process.env.DB_PASSWORD || 'counter';
const DB_CONNECT_RETRIES = Number(process.env.DB_CONNECT_RETRIES || 30);
const DB_CONNECT_RETRY_DELAY_MS = Number(process.env.DB_CONNECT_RETRY_DELAY_MS || 2000);

const pool = new Pool({
  host: DB_HOST,
  port: DB_PORT,
  database: DB_NAME,
  user: DB_USER,
  password: DB_PASSWORD,
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

pool.on('error', (err) => {
  console.error('[db] idle client error:', err.message);
});

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Creates the counter table and seeds the single counter row if it does not exist.
 * Must stay idempotent: it never overwrites an existing value.
 */
async function initDatabase() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS counter (
      id    INTEGER     PRIMARY KEY,
      value BIGINT      NOT NULL DEFAULT 0,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);
  await pool.query(`
    INSERT INTO counter (id, value)
    VALUES (1, 0)
    ON CONFLICT (id) DO NOTHING
  `);
}

/** Waits until PostgreSQL accepts connections, then initializes the schema. */
async function connectWithRetry() {
  for (let attempt = 1; attempt <= DB_CONNECT_RETRIES; attempt += 1) {
    try {
      await pool.query('SELECT 1');
      await initDatabase();
      console.log(`[db] connected to ${DB_HOST}:${DB_PORT}/${DB_NAME} and schema is ready`);
      return;
    } catch (err) {
      console.warn(
        `[db] attempt ${attempt}/${DB_CONNECT_RETRIES} failed: ${err.message}; retrying in ${DB_CONNECT_RETRY_DELAY_MS}ms`
      );
      await sleep(DB_CONNECT_RETRY_DELAY_MS);
    }
  }
  throw new Error(
    `could not connect to PostgreSQL at ${DB_HOST}:${DB_PORT}/${DB_NAME} after ${DB_CONNECT_RETRIES} attempts`
  );
}

async function currentValue(queryable) {
  const { rows } = await queryable.query('SELECT value FROM counter WHERE id = 1');
  if (rows.length === 0) {
    // Self-healing: only possible if the seed row was removed outside the app.
    await queryable.query('INSERT INTO counter (id, value) VALUES (1, 0) ON CONFLICT (id) DO NOTHING');
    return 0n;
  }
  return BigInt(rows[0].value);
}

const app = express();
app.disable('x-powered-by');
app.use(express.json());

// Small request log so `docker compose logs backend` shows the request flow.
app.use((req, res, next) => {
  const started = Date.now();
  res.on('finish', () => {
    console.log(`${req.method} ${req.originalUrl} -> ${res.statusCode} (${Date.now() - started}ms)`);
  });
  next();
});

app.get('/healthz', (req, res) => {
  res.json({ status: 'ok' });
});

app.get('/api/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', database: 'up' });
  } catch (err) {
    res.status(503).json({ status: 'error', database: 'down', message: err.message });
  }
});

// Read the counter. Reading never modifies the value.
app.get('/api/counter', async (req, res) => {
  try {
    const value = await currentValue(pool);
    res.json({ value: Number(value) });
  } catch (err) {
    console.error('[api] GET /api/counter failed:', err.message);
    res.status(500).json({ error: 'failed to read counter from database', message: err.message });
  }
});

/**
 * Applies a delta with a single atomic UPDATE inside a transaction, then reads the
 * committed value back in the same transaction. Concurrent increments therefore
 * cannot overwrite each other and the returned value is the stored one.
 */
async function applyDelta(delta) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await currentValue(client); // guarantees the row exists inside this transaction
    const { rows } = await client.query(
      `UPDATE counter
          SET value = value + $1,
              updated_at = now()
        WHERE id = 1
      RETURNING value`,
      [delta]
    );
    await client.query('COMMIT');
    return Number(rows[0].value);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (rollbackErr) {
      console.error('[db] rollback failed:', rollbackErr.message);
    }
    throw err;
  } finally {
    client.release();
  }
}

app.post('/api/counter/increment', async (req, res) => {
  try {
    res.json({ value: await applyDelta(1) });
  } catch (err) {
    console.error('[api] POST /api/counter/increment failed:', err.message);
    res.status(500).json({ error: 'failed to increment counter', message: err.message });
  }
});

app.post('/api/counter/decrement', async (req, res) => {
  try {
    res.json({ value: await applyDelta(-1) });
  } catch (err) {
    console.error('[api] POST /api/counter/decrement failed:', err.message);
    res.status(500).json({ error: 'failed to decrement counter', message: err.message });
  }
});

app.use('/api', (req, res) => {
  res.status(404).json({ error: 'not found', path: req.originalUrl });
});

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error('[api] unhandled error:', err.message);
  res.status(500).json({ error: 'internal server error' });
});

let server;

async function main() {
  await connectWithRetry();
  server = app.listen(PORT, '0.0.0.0', () => {
    console.log(`[api] listening on 0.0.0.0:${PORT}`);
  });
}

function shutdown(signal) {
  console.log(`[api] received ${signal}, shutting down`);
  const done = () => {
    pool.end().catch(() => {});
    process.exit(0);
  };
  if (server) {
    server.close(done);
    setTimeout(done, 5000).unref();
  } else {
    done();
  }
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

main().catch((err) => {
  console.error('[api] fatal startup error:', err.message);
  process.exit(1);
});
