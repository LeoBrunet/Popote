import type { Db } from "./db.js";
import type { AppContext, MealAnalysis, RecipeInput } from "./schemas.js";

export interface User {
  id: string;
  appToken: string;
  connectorToken: string;
  createdAt: string;
  claudeConnectedAt: string | null;
  claudeLastSeenAt: string | null;
  context: AppContext;
}

export interface MealRequest {
  id: string;
  meal: string | null;
  description: string | null;
  photoBase64: string | null;
  createdAt: string;
  analysis: MealAnalysis | null;
}

export interface StoredRecipe extends RecipeInput {
  id: string;
  createdAt: string;
}

type Row = Record<string, any>;

const now = () => new Date().toISOString();
const json = <T>(text: string | null, fallback: T): T => (text ? (JSON.parse(text) as T) : fallback);

/** Random URL-safe secret (Web Crypto: works in Node and Workers). */
function token(bytes = 24) {
  const data = crypto.getRandomValues(new Uint8Array(bytes));
  let binary = "";
  for (const b of data) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export class Store {
  constructor(private readonly db: Db) {}

  // MARK: Users

  async createUser(): Promise<User> {
    const id = crypto.randomUUID();
    await this.db.run(
      "INSERT INTO users (id, app_token, connector_token, created_at) VALUES (?, ?, ?, ?)",
      id, token(), token(), now()
    );
    return (await this.userById(id))!;
  }

  private rowToUser(row: Row | undefined): User | undefined {
    if (!row) return undefined;
    return {
      id: row.id,
      appToken: row.app_token,
      connectorToken: row.connector_token,
      createdAt: row.created_at,
      claudeConnectedAt: row.claude_connected_at,
      claudeLastSeenAt: row.claude_last_seen_at,
      context: json(row.context_json, {}),
    };
  }

  async userById(id: string) {
    return this.rowToUser(await this.db.get<Row>("SELECT * FROM users WHERE id = ?", id));
  }
  async userByAppToken(t: string) {
    return this.rowToUser(await this.db.get<Row>("SELECT * FROM users WHERE app_token = ?", t));
  }
  async userByConnectorToken(t: string) {
    return this.rowToUser(await this.db.get<Row>("SELECT * FROM users WHERE connector_token = ?", t));
  }

  async markClaudeSeen(userId: string) {
    const t = now();
    await this.db.run(
      "UPDATE users SET claude_last_seen_at = ?, claude_connected_at = COALESCE(claude_connected_at, ?) WHERE id = ?",
      t, t, userId
    );
  }

  /** What the app shares with Claude: pantry, recipe titles, today's targets and what's been eaten. */
  async setContext(userId: string, context: AppContext) {
    await this.db.run("UPDATE users SET context_json = ? WHERE id = ?", JSON.stringify(context), userId);
  }

  // MARK: Meal requests (describe / photo a meal → Claude lists the ingredients)

  async createMealRequest(userId: string, input: { meal?: string; description?: string; photoBase64?: string }) {
    const id = `meal_${crypto.randomUUID().slice(0, 8)}`;
    await this.db.run(
      "INSERT INTO meal_requests (id, user_id, meal, description, photo_base64, created_at) VALUES (?, ?, ?, ?, ?, ?)",
      id, userId, input.meal ?? null, input.description ?? null, input.photoBase64 ?? null, now()
    );
    return id;
  }

  private rowToMealRequest(row: Row): MealRequest {
    return {
      id: row.id,
      meal: row.meal,
      description: row.description,
      photoBase64: row.photo_base64,
      createdAt: row.created_at,
      analysis: json(row.analysis_json, null),
    };
  }

  async mealRequest(userId: string, id: string) {
    const row = await this.db.get<Row>("SELECT * FROM meal_requests WHERE user_id = ? AND id = ?", userId, id);
    return row ? this.rowToMealRequest(row) : undefined;
  }

  /** Requests Claude hasn't answered yet, newest first. */
  async pendingMealRequests(userId: string) {
    const rows = await this.db.all<Row>(
      "SELECT * FROM meal_requests WHERE user_id = ? AND analysis_json IS NULL AND delivered_at IS NULL ORDER BY created_at DESC LIMIT 10", userId
    );
    return rows.map((r) => this.rowToMealRequest(r));
  }

  async saveMealAnalysis(userId: string, id: string, analysis: MealAnalysis) {
    const { changes } = await this.db.run(
      "UPDATE meal_requests SET analysis_json = ?, analyzed_at = ? WHERE user_id = ? AND id = ?",
      JSON.stringify(analysis), now(), userId, id
    );
    return changes > 0;
  }

  // MARK: Recipes written by Claude

  async saveRecipe(userId: string, recipe: RecipeInput) {
    const id = `rcp_${crypto.randomUUID().slice(0, 8)}`;
    await this.db.run(
      "INSERT INTO recipes (id, user_id, json, created_at) VALUES (?, ?, ?, ?)",
      id, userId, JSON.stringify(recipe), now()
    );
    return id;
  }

  // MARK: Inbox (what the app hasn't picked up yet)

  async inbox(userId: string) {
    const meals = await this.db.all<Row>(
      "SELECT * FROM meal_requests WHERE user_id = ? AND analysis_json IS NOT NULL AND delivered_at IS NULL", userId
    );
    const recipes = await this.db.all<Row>(
      "SELECT * FROM recipes WHERE user_id = ? AND delivered_at IS NULL ORDER BY created_at", userId
    );
    return {
      mealAnalyses: meals.map((r) => ({ requestId: r.id, meal: r.meal, ...json<MealAnalysis>(r.analysis_json, { title: "", ingredients: [] }) })),
      recipes: recipes.map((r): StoredRecipe => ({ id: r.id, createdAt: r.created_at, ...json<RecipeInput>(r.json, {} as RecipeInput) })),
    };
  }

  async acknowledge(userId: string, ids: { mealRequests?: string[]; recipes?: string[] }) {
    const t = now();
    // Photos are only kept until the analysis reaches the app.
    for (const id of ids.mealRequests ?? []) {
      await this.db.run("UPDATE meal_requests SET delivered_at = ?, photo_base64 = NULL WHERE user_id = ? AND id = ?", t, userId, id);
    }
    for (const id of ids.recipes ?? []) {
      await this.db.run("UPDATE recipes SET delivered_at = ? WHERE user_id = ? AND id = ?", t, userId, id);
    }
  }
}
