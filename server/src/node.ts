// Local / self-hosted entry point: Node + SQLite file.
import { serve } from "@hono/node-server";
import { createApp } from "./app.js";
import { SqliteDb } from "./sqlite.js";
import { Store } from "./store.js";

const port = Number(process.env.PORT ?? 8788);
const store = new Store(new SqliteDb(process.env.DATABASE_PATH ?? "popote.db"));
const app = createApp(() => store, { publicUrl: process.env.PUBLIC_URL, logRequests: !!process.env.LOG_REQUESTS });

serve({ fetch: app.fetch, port }, () => {
  console.log(`Popote server on :${port} (public URL: ${process.env.PUBLIC_URL ?? "request origin"})`);
});
