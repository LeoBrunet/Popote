import * as z from "zod";

const Macros = {
  kcal: z.number().min(0),
  protein: z.number().min(0),
  carbs: z.number().min(0),
  fat: z.number().min(0),
};

const SharedIngredient = z.object({
  name: z.string(),
  quantity: z.number().optional(),
  unit: z.string().optional(),
  grams: z.number().optional(),
  kcal: z.number().optional(),
  product: z.string().optional().describe("scanned or picked product (brand · name), when there is one"),
});

/** A logged meal, with the ingredients actually eaten when Popote knows them. */
export const JournalEntry = z.object({
  date: z.string().describe("local date and time, YYYY-MM-DDTHH:mm"),
  meal: z.string(),
  title: z.string(),
  amount: z.string().optional(),
  recipe: z.string().optional().describe("title of the recipe it was logged from"),
  ...Macros,
  ingredients: z.array(SharedIngredient).max(80).optional(),
});

export const RecipeDetail = z.object({
  title: z.string(),
  servings: z.number(),
  minutes: z.number().optional(),
  source: z.string().optional(),
  url: z.string().optional(),
  createdAt: z.string().optional(),
  inShoppingList: z.boolean().optional(),
  perServing: z.object(Macros).optional(),
  ingredients: z.array(SharedIngredient).max(80),
  steps: z.array(z.string()).max(60),
});

/** Shared by the app on each launch so Claude can take it into account. */
export const AppContext = z.object({
  language: z.string().optional(),
  timezone: z.string().optional(),
  today: z.string().optional(),
  pantry: z.array(z.string()).max(500).optional(),
  recipes: z.array(z.string()).max(1000).optional().describe("titles of the recipes already in Popote"),
  targets: z.object(Macros).optional(),
  eaten: z.object(Macros).optional(),
  goal: z.string().optional().describe("weight goal, e.g. 'Lose 0.25 kg/week'"),
  journal: z.array(JournalEntry).max(3000).optional().describe("meals logged over the last weeks"),
  recipeDetails: z.array(RecipeDetail).max(1000).optional(),
});
export type AppContext = z.infer<typeof AppContext>;

export const MealIngredient = z.object({
  name: z.string().min(1).describe("short ingredient name, in the app language"),
  quantity: z.number().min(0).describe("amount as people say it, e.g. 2 (eggs), 1.5 (tbsp), 200 (g)"),
  unit: z.string().describe("g, ml, tbsp, tsp, piece, slice… empty for a count"),
  grams: z.number().min(0).describe("estimated weight in grams of what was eaten"),
  ...Macros,
});

export const MealAnalysis = z.object({
  title: z.string().min(1).describe("short name for the meal, in the app language"),
  ingredients: z.array(MealIngredient).min(1).max(40),
});
export type MealAnalysis = z.infer<typeof MealAnalysis>;

export const RecipeIngredient = z.object({
  quantity: z.number().min(0),
  unit: z.string().describe("g, ml, tbsp, tsp, piece… empty for a count"),
  name: z.string().min(1),
  inPantry: z.boolean().optional().describe("true when the user already has it (from get_context)"),
});

export const RecipeInput = z.object({
  title: z.string().min(1),
  servings: z.number().int().min(1).max(30),
  minutes: z.number().int().min(0).max(1440).optional(),
  summary: z.string().optional().describe("one or two sentences shown above the recipe"),
  ingredients: z.array(RecipeIngredient).min(1).max(60),
  steps: z.array(z.string().min(1)).min(1).max(40),
  fromMealRequest: z.string().optional().describe("id of the meal request this recipe comes from, if any"),
});
export type RecipeInput = z.infer<typeof RecipeInput>;
