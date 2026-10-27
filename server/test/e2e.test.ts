import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { serve, type ServerType } from "@hono/node-server";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { createApp } from "../src/app.js";
import { SqliteDb } from "../src/sqlite.js";
import { Store } from "../src/store.js";

let server: ServerType | undefined;
// Set POPOTE_TEST_URL to run the same scenario against another deployment (e.g. `wrangler dev`).
let base = process.env.POPOTE_TEST_URL ?? "";

beforeAll(async () => {
  if (base) return;
  const store = new Store(new SqliteDb(":memory:"));
  const app = createApp(() => store);
  await new Promise<void>((resolve) => {
    server = serve({ fetch: app.fetch, port: 0 }, (info) => {
      base = `http://127.0.0.1:${info.port}`;
      resolve();
    });
  });
});

afterAll(() => server?.close());

const call = async (path: string, init: RequestInit & { token?: string } = {}) => {
  const res = await fetch(base + path, {
    ...init,
    headers: { "content-type": "application/json", ...(init.token ? { authorization: `Bearer ${init.token}` } : {}) },
  });
  return { status: res.status, body: await res.json() };
};

// 1×1 JPEG, enough to check the photo reaches Claude as an image.
const tinyJpeg = "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=";

describe("app ↔ server ↔ Claude", () => {
  it("analyses a described meal and saves a recipe", async () => {
    // App registers, gets its connector URL, shares its context.
    const reg = await call("/api/register", { method: "POST" });
    expect(reg.status).toBe(201);
    const { appToken, connectorUrl } = reg.body;
    expect(connectorUrl).toMatch(/\/mcp\/[\w-]+$/);
    expect((await call("/api/inbox")).status).toBe(401);

    await call("/api/context", {
      method: "PUT", token: appToken,
      body: JSON.stringify({
        language: "fr", today: "2026-10-27", pantry: ["Riz", "Œufs"], recipes: ["Dahl de lentilles"],
        targets: { kcal: 2200, protein: 126, carbs: 259, fat: 73 }, eaten: { kcal: 720, protein: 37, carbs: 86, fat: 23 },
      }),
    });

    // App sends a meal (text + photo).
    const req = await call("/api/meal-requests", {
      method: "POST", token: appToken,
      body: JSON.stringify({ meal: "lunch", description: "pâtes tomate parmesan", photoBase64: tinyJpeg }),
    });
    expect(req.status).toBe(201);
    const requestId: string = req.body.id;

    // Claude, through the connector.
    const client = new Client({ name: "test-claude", version: "1.0.0" });
    await client.connect(new StreamableHTTPClientTransport(new URL(connectorUrl)));
    const tools = (await client.listTools()).tools.map((t) => t.name).sort();
    expect(tools).toEqual(["get_context", "get_meal_request", "save_meal_analysis", "save_recipe"]);

    const context = JSON.parse(((await client.callTool({ name: "get_context", arguments: {} })).content as any)[0].text);
    expect(context.remainingToday.kcal).toBe(1480);
    expect(context.pendingMealRequests[0].id).toBe(requestId);

    const meal = await client.callTool({ name: "get_meal_request", arguments: {} });
    const content = meal.content as any[];
    expect(JSON.parse(content[0].text).description).toBe("pâtes tomate parmesan");
    expect(content[1]).toMatchObject({ type: "image", mimeType: "image/jpeg" });

    const saved = await client.callTool({
      name: "save_meal_analysis",
      arguments: {
        requestId, title: "Pâtes à la tomate",
        ingredients: [
          { name: "Pâtes cuites", quantity: 220, unit: "g", grams: 220, kcal: 345, protein: 12, carbs: 68, fat: 2 },
          { name: "Parmesan", quantity: 15, unit: "g", grams: 15, kcal: 60, protein: 5, carbs: 0, fat: 4 },
        ],
      },
    });
    expect(saved.isError).toBeFalsy();

    const recipe = await client.callTool({
      name: "save_recipe",
      arguments: {
        title: "Riz sauté aux œufs", servings: 2, minutes: 15,
        ingredients: [{ quantity: 200, unit: "g", name: "Riz", inPantry: true }, { quantity: 3, unit: "", name: "Œufs", inPantry: true }],
        steps: ["Cuire le riz.", "Brouiller les œufs.", "Mélanger."],
      },
    });
    expect(recipe.isError).toBeFalsy();
    await client.close();

    // App picks both up, then acknowledges them.
    const inbox = await call("/api/inbox", { token: appToken });
    expect(inbox.body.mealAnalyses).toHaveLength(1);
    expect(inbox.body.mealAnalyses[0]).toMatchObject({ requestId, title: "Pâtes à la tomate" });
    expect(inbox.body.recipes[0].title).toBe("Riz sauté aux œufs");

    await call("/api/inbox/ack", {
      method: "POST", token: appToken,
      body: JSON.stringify({ mealRequests: [requestId], recipes: [inbox.body.recipes[0].id] }),
    });
    const empty = await call("/api/inbox", { token: appToken });
    expect(empty.body).toEqual({ mealAnalyses: [], recipes: [] });

    const me = await call("/api/me", { token: appToken });
    expect(me.body.claude.connectedAt).toBeTruthy();
  }, 30_000);
});
