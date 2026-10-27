import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as z from "zod";
import { MealIngredient, RecipeIngredient } from "./schemas.js";
import type { Store, User } from "./store.js";

const INSTRUCTIONS = `You are the cooking and nutrition assistant of Popote, the user's personal recipe and food-journal app.
Language: write everything that will show in the app (meal names, ingredients, recipe titles, steps) in the app's language, context.language ("fr" → French, "en" → English); otherwise the language the user writes in. In French, use "tu".
This connector links you to Popote: what you save here appears in the app.

How to work:
- Start with get_context: the user's pantry, the recipes they already have, and today's calorie and macro targets and what they've eaten.
- Whenever the user refers to something in Popote ("what I ate yesterday", "the pasta from Tuesday", "my lasagna recipe", "this week's protein", "the yogurt I scanned"), look it up instead of guessing: get_journal for logged meals (with their ingredients, scanned products and times), get_recipes for their recipes (ingredients, steps, macros). Quote the actual entries.
- When the user asks you to analyse a meal (they give a meal request id, or just say "my meal"), call get_meal_request — it returns their description and, when there is one, the photo of their plate. List each ingredient of the portion actually eaten with a realistic quantity, unit, weight in grams and calories/protein/carbs/fat for that weight (typical home portions when the amount isn't stated), then call save_meal_analysis. In the chat, answer in one or two sentences (meal name, total kcal and protein) and tell them it's ready in Popote, where they can edit it.
- When the user wants a recipe, create one practical home recipe: metric quantities or spoons, short steps (one action each). Use their pantry and remaining macros when relevant, and mark inPantry for what they already have. Show it briefly in the chat, adjust it if they ask, and save it with save_recipe once they're happy (or right away if they asked you to add it to Popote).
- Never invent that something was saved: only save_meal_analysis and save_recipe write to the app.`;

const text = (value: unknown) => ({
  content: [{ type: "text" as const, text: typeof value === "string" ? value : JSON.stringify(value, null, 2) }],
});

/** One MCP server per request, bound to the user owning the connector URL. */
export function buildMcpServer(store: Store, user: User) {
  const server = new McpServer({ name: "popote", version: "0.1.0" }, { instructions: INSTRUCTIONS });

  server.registerTool(
    "get_context",
    {
      title: "Popote context",
      description: "The user's language, today's date, pantry, titles of the recipes already in Popote, today's calorie/macro targets and what they've eaten so far, plus meal requests waiting for an analysis. Call it first.",
      inputSchema: {},
    },
    async () => {
      const fresh = (await store.userById(user.id))!;
      const { journal, recipeDetails, ...context } = fresh.context;
      const { targets, eaten } = context;
      const remaining = targets && eaten
        ? {
            kcal: Math.max(targets.kcal - eaten.kcal, 0),
            protein: Math.max(targets.protein - eaten.protein, 0),
            carbs: Math.max(targets.carbs - eaten.carbs, 0),
            fat: Math.max(targets.fat - eaten.fat, 0),
          }
        : undefined;
      const pending = await store.pendingMealRequests(user.id);
      return text({
        ...context,
        journalEntries: journal?.length ?? 0,
        recipeCount: recipeDetails?.length ?? context.recipes?.length ?? 0,
        remainingToday: remaining,
        pendingMealRequests: pending.map((r) => ({ id: r.id, meal: r.meal, description: r.description, hasPhoto: !!r.photoBase64, createdAt: r.createdAt })),
      });
    }
  );

  server.registerTool(
    "get_journal",
    {
      title: "Food journal",
      description: "Meals the user logged in Popote, day by day: time, meal, title, amount, calories and macros, and the ingredients eaten (with scanned products) when known. Defaults to the last 7 days. Filter with from/to (YYYY-MM-DD) and/or a search text matched against titles and ingredients.",
      inputSchema: {
        from: z.string().optional().describe("first day, YYYY-MM-DD"),
        to: z.string().optional().describe("last day, YYYY-MM-DD"),
        query: z.string().optional().describe("words to look for in meal titles and ingredients"),
      },
    },
    async ({ from, to, query }) => {
      const fresh = (await store.userById(user.id))!;
      const journal = fresh.context.journal ?? [];
      const today = fresh.context.today ?? new Date().toISOString().slice(0, 10);
      const start = from ?? (query ? "0000-00-00" : shiftDay(today, -6));
      const end = to ?? "9999-99-99";
      const words = query ? normalize(query).split(/\s+/).filter(Boolean) : [];
      const entries = journal.filter((e) => {
        const day = e.date.slice(0, 10);
        if (day < start || day > end) return false;
        if (!words.length) return true;
        const haystack = normalize([e.title, e.recipe, ...(e.ingredients ?? []).flatMap((i) => [i.name, i.product])].filter(Boolean).join(" "));
        return words.every((w) => haystack.includes(w));
      });
      const days = new Map<string, typeof entries>();
      for (const e of entries.sort((a, b) => a.date.localeCompare(b.date))) {
        const day = e.date.slice(0, 10);
        days.set(day, [...(days.get(day) ?? []), e]);
      }
      if (!days.size) return text(journal.length ? "No logged meal matches." : "The journal is empty, or Popote hasn't shared it yet (the user should open Popote once).");
      return text([...days].map(([day, list]) => ({
        day,
        total: sumMacros(list),
        meals: list.map(({ date, ...e }) => ({ time: date.slice(11, 16), ...e })),
      })));
    }
  );

  server.registerTool(
    "get_recipes",
    {
      title: "Recipes",
      description: "The user's Popote recipes. With a search text: the matching recipes in full (servings, ingredients with quantities and products, steps, macros per serving). Without: a short list of all recipes.",
      inputSchema: { query: z.string().optional().describe("words to look for in titles and ingredients") },
    },
    async ({ query }) => {
      const fresh = (await store.userById(user.id))!;
      const recipes = fresh.context.recipeDetails ?? [];
      if (!recipes.length) return text("No recipe shared yet (the user should open Popote once).");
      if (!query) {
        return text(recipes.map((r) => ({ title: r.title, servings: r.servings, minutes: r.minutes, kcalPerServing: r.perServing ? Math.round(r.perServing.kcal) : undefined, ingredients: r.ingredients.length, source: r.source })));
      }
      const words = normalize(query).split(/\s+/).filter(Boolean);
      const matches = recipes.filter((r) => {
        const haystack = normalize([r.title, ...r.ingredients.flatMap((i) => [i.name, i.product])].filter(Boolean).join(" "));
        return words.every((w) => haystack.includes(w));
      });
      return matches.length ? text(matches.slice(0, 10)) : text(`No recipe matches "${query}".`);
    }
  );

  server.registerTool(
    "get_meal_request",
    {
      title: "Meal to analyse",
      description: "A meal the user described or photographed in Popote: their words and the photo of the plate when there is one. Without an id, returns the latest one still waiting.",
      inputSchema: { id: z.string().optional().describe("meal request id, e.g. meal_1a2b3c4d") },
    },
    async ({ id }) => {
      const request = id ? await store.mealRequest(user.id, id) : (await store.pendingMealRequests(user.id))[0];
      if (!request) return { ...text(id ? `Meal request ${id} not found.` : "No meal is waiting for an analysis."), isError: true };
      const info = text({ id: request.id, meal: request.meal, description: request.description, createdAt: request.createdAt, alreadyAnalyzed: !!request.analysis });
      if (!request.photoBase64) return info;
      return { content: [...info.content, { type: "image" as const, data: request.photoBase64, mimeType: "image/jpeg" }] };
    }
  );

  server.registerTool(
    "save_meal_analysis",
    {
      title: "Save the ingredients of a meal",
      description: "Sends the ingredient list of an analysed meal to Popote, where the user reviews it before logging it. Each ingredient: name, quantity, unit, grams, kcal, protein, carbs, fat (for that portion).",
      inputSchema: {
        requestId: z.string(),
        title: z.string().min(1).describe("short name for the meal, in the app language"),
        ingredients: z.array(MealIngredient).min(1).max(40),
      },
    },
    async ({ requestId, title, ingredients }) => {
      const ok = await store.saveMealAnalysis(user.id, requestId, { title, ingredients });
      if (!ok) return { ...text(`Meal request ${requestId} not found.`), isError: true };
      const total = ingredients.reduce((sum, i) => sum + i.kcal, 0);
      return text(`Saved: "${title}", ${ingredients.length} ingredients, ${Math.round(total)} kcal. The user can review it in Popote.`);
    }
  );

  server.registerTool(
    "save_recipe",
    {
      title: "Add a recipe to Popote",
      description: "Saves a recipe to the user's Popote library (its macros are computed in the app from the ingredients).",
      inputSchema: {
        title: z.string().min(1),
        servings: z.number().int().min(1).max(30),
        minutes: z.number().int().min(0).max(1440).optional(),
        summary: z.string().optional().describe("one or two sentences shown above the recipe"),
        ingredients: z.array(RecipeIngredient).min(1).max(60),
        steps: z.array(z.string().min(1)).min(1).max(40),
        fromMealRequest: z.string().optional().describe("meal request id, when the recipe comes from an analysed meal"),
      },
    },
    async (recipe) => {
      const id = await store.saveRecipe(user.id, recipe);
      return text(`Saved "${recipe.title}" (${id}). It appears in the user's Popote recipes next time they open the app.`);
    }
  );

  return server;
}

function normalize(value: string) {
  return value.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/['’]/g, "");
}

function shiftDay(day: string, days: number) {
  const date = new Date(`${day}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function sumMacros(list: { kcal: number; protein: number; carbs: number; fat: number }[]) {
  const round = (n: number) => Math.round(n * 10) / 10;
  const t = list.reduce((s, e) => ({ kcal: s.kcal + e.kcal, protein: s.protein + e.protein, carbs: s.carbs + e.carbs, fat: s.fat + e.fat }), { kcal: 0, protein: 0, carbs: 0, fat: 0 });
  return { kcal: Math.round(t.kcal), protein: round(t.protein), carbs: round(t.carbs), fat: round(t.fat) };
}
