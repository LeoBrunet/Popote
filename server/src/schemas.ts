import * as z from "zod";

const Macros = {
  kcal: z.number().min(0),
  protein: z.number().min(0),
  carbs: z.number().min(0),
  fat: z.number().min(0),
};

/** Shared by the app on each launch so Claude can take it into account. */
export const AppContext = z.object({
  language: z.string().optional(),
  timezone: z.string().optional(),
  today: z.string().optional(),
  pantry: z.array(z.string()).max(500).optional(),
  recipes: z.array(z.string()).max(1000).optional().describe("titles of the recipes already in Popote"),
  targets: z.object(Macros).optional(),
  eaten: z.object(Macros).optional(),
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
