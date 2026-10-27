import { Hono, type Context } from "hono";
import * as z from "zod";
import { AppContext } from "./schemas.js";
import type { Store, User } from "./store.js";

type Env = { Variables: { user: User; store: Store; publicUrl: string } };

export function connectorUrl(publicUrl: string, user: User) {
  return `${publicUrl.replace(/\/$/, "")}/mcp/${user.connectorToken}`;
}

async function parse<T>(c: Context, schema: z.ZodType<T>): Promise<T | Response> {
  const body = await c.req.json().catch(() => undefined);
  const result = schema.safeParse(body);
  if (!result.success) return c.json({ error: "invalid_body", issues: result.error.issues }, 400);
  return result.data;
}

const MealRequestBody = z.object({
  meal: z.string().optional(),
  description: z.string().max(2000).optional(),
  photoBase64: z.string().max(4_000_000).optional(),
}).refine((b) => !!(b.description?.trim() || b.photoBase64), { message: "description or photo required" });

const Ack = z.object({ mealRequests: z.array(z.string()).optional(), recipes: z.array(z.string()).optional() });

/** REST API used by the iOS app. Auth: `Authorization: Bearer <appToken>`. */
export function apiRouter() {
  const api = new Hono<Env>();

  // Anonymous registration: one account per app install.
  api.post("/register", async (c) => {
    const user = await c.var.store.createUser();
    return c.json({ appToken: user.appToken, connectorUrl: connectorUrl(c.var.publicUrl, user) }, 201);
  });

  api.use("*", async (c, next) => {
    const header = c.req.header("authorization") ?? "";
    const user = header.startsWith("Bearer ") ? await c.var.store.userByAppToken(header.slice(7)) : undefined;
    if (!user) return c.json({ error: "unauthorized" }, 401);
    c.set("user", user);
    await next();
  });

  api.get("/me", (c) => {
    const user = c.var.user;
    return c.json({
      connectorUrl: connectorUrl(c.var.publicUrl, user),
      claude: { connectedAt: user.claudeConnectedAt, lastSeenAt: user.claudeLastSeenAt },
    });
  });

  api.put("/context", async (c) => {
    const body = await parse(c, AppContext);
    if (body instanceof Response) return body;
    await c.var.store.setContext(c.var.user.id, body);
    return c.json({ ok: true });
  });

  api.post("/meal-requests", async (c) => {
    const body = await parse(c, MealRequestBody);
    if (body instanceof Response) return body;
    const id = await c.var.store.createMealRequest(c.var.user.id, body);
    return c.json({ id }, 201);
  });

  /** Meal analyses and recipes written by Claude that the app hasn't picked up yet. */
  api.get("/inbox", async (c) => c.json(await c.var.store.inbox(c.var.user.id)));

  api.post("/inbox/ack", async (c) => {
    const body = await parse(c, Ack);
    if (body instanceof Response) return body;
    await c.var.store.acknowledge(c.var.user.id, body);
    return c.json({ ok: true });
  });

  return api;
}
