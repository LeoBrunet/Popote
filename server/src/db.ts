// Minimal async database interface, implemented by SQLite (local / Node) and Cloudflare D1.

export type Param = string | number | null;

export interface Statement {
  sql: string;
  params?: Param[];
}

export interface Db {
  all<T = Record<string, unknown>>(sql: string, ...params: Param[]): Promise<T[]>;
  get<T = Record<string, unknown>>(sql: string, ...params: Param[]): Promise<T | undefined>;
  run(sql: string, ...params: Param[]): Promise<{ changes: number }>;
  /** Runs statements atomically (a transaction / D1 batch). */
  batch(statements: Statement[]): Promise<void>;
}

// MARK: Cloudflare D1

interface D1PreparedStatementLike {
  bind(...values: unknown[]): D1PreparedStatementLike;
  all<T>(): Promise<{ results: T[] }>;
  first<T>(): Promise<T | null>;
  run(): Promise<{ meta: { changes?: number } }>;
}

export interface D1DatabaseLike {
  prepare(sql: string): D1PreparedStatementLike;
  batch(statements: D1PreparedStatementLike[]): Promise<unknown>;
}

export class D1Db implements Db {
  constructor(private readonly d1: D1DatabaseLike) {}

  private stmt(sql: string, params: Param[]) {
    const prepared = this.d1.prepare(sql);
    return params.length ? prepared.bind(...params) : prepared;
  }

  async all<T>(sql: string, ...params: Param[]) {
    return (await this.stmt(sql, params).all<T>()).results;
  }

  async get<T>(sql: string, ...params: Param[]) {
    return (await this.stmt(sql, params).first<T>()) ?? undefined;
  }

  async run(sql: string, ...params: Param[]) {
    const result = await this.stmt(sql, params).run();
    return { changes: result.meta.changes ?? 0 };
  }

  async batch(statements: Statement[]) {
    if (statements.length === 0) return;
    // D1 batches are transactional; keep them reasonably small.
    for (let i = 0; i < statements.length; i += 50) {
      await this.d1.batch(statements.slice(i, i + 50).map((s) => this.stmt(s.sql, s.params ?? [])));
    }
  }
}

export const SCHEMA: string[] = [
  `CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    app_token TEXT UNIQUE NOT NULL,
    connector_token TEXT UNIQUE NOT NULL,
    created_at TEXT NOT NULL,
    claude_connected_at TEXT,
    claude_last_seen_at TEXT,
    context_json TEXT NOT NULL DEFAULT '{}'
  )`,
  `CREATE TABLE IF NOT EXISTS meal_requests (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    meal TEXT,
    description TEXT,
    photo_base64 TEXT,
    created_at TEXT NOT NULL,
    analysis_json TEXT,
    analyzed_at TEXT,
    delivered_at TEXT
  )`,
  `CREATE INDEX IF NOT EXISTS meal_requests_by_user ON meal_requests(user_id, created_at)`,
  `CREATE TABLE IF NOT EXISTS recipes (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    delivered_at TEXT
  )`,
  `CREATE INDEX IF NOT EXISTS recipes_by_user ON recipes(user_id, created_at)`,
];
