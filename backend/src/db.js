// One tiny query() interface over two drivers:
//  - DATABASE_URL set  -> real Postgres (Neon in production) via `pg`
//  - otherwise         -> PGlite, Postgres compiled to WASM, in-process (local dev/tests)
// Both speak the same SQL, so nothing else in the app knows which one it's on.
import { readFile } from 'node:fs/promises';

let driver;

export async function initDb() {
  if (process.env.DATABASE_URL) {
    const { default: pg } = await import('pg');
    const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
    driver = { query: (sql, params) => pool.query(sql, params), exec: (sql) => pool.query(sql), close: () => pool.end() };
  } else {
    const { PGlite } = await import('@electric-sql/pglite');
    const db = new PGlite(process.env.PGLITE_DIR || undefined); // undefined = in-memory
    driver = { query: (sql, params) => db.query(sql, params), exec: (sql) => db.exec(sql), close: () => db.close() };
  }
  await driver.exec(await readFile(new URL('./schema.sql', import.meta.url), 'utf8'));
}

export async function query(sql, params = []) {
  const res = await driver.query(sql, params);
  return res.rows;
}

export async function one(sql, params) {
  return (await query(sql, params))[0];
}

export const closeDb = () => driver?.close();
