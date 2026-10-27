// Plays Claude through the MCP connector, for local testing (Claude can't reach localhost).
//   npx tsx scripts/play-claude.ts <connectorUrl> meal     → answers the latest meal request with a sample analysis
//   npx tsx scripts/play-claude.ts <connectorUrl> recipe   → saves a sample recipe built from the pantry
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

const [url, mode = "meal"] = process.argv.slice(2);
if (!url) {
  console.error("usage: play-claude.ts <connectorUrl> [meal|recipe]");
  process.exit(1);
}

const client = new Client({ name: "popote-demo", version: "1.0.0" });
await client.connect(new StreamableHTTPClientTransport(new URL(url)));

const call = async (name: string, args: Record<string, unknown> = {}) => {
  const result = await client.callTool({ name, arguments: args });
  const first = (result.content as { type: string; text?: string }[])[0];
  if (result.isError) throw new Error(`${name}: ${first?.text}`);
  const text = first?.text ?? "";
  return text.startsWith("{") || text.startsWith("[") ? JSON.parse(text) : text;
};

const context = await call("get_context");
const fr = context.language !== "en";

if (mode === "meal") {
  const request = await call("get_meal_request");
  console.log("Analysing", request.id, `"${request.description ?? "(photo)"}"`);
  console.log(await call("save_meal_analysis", {
    requestId: request.id,
    title: fr ? "Pâtes à la sauce tomate" : "Pasta with tomato sauce",
    ingredients: [
      { name: fr ? "Pâtes cuites" : "Cooked pasta", quantity: 220, unit: "g", grams: 220, kcal: 345, protein: 12, carbs: 68, fat: 2 },
      { name: fr ? "Sauce tomate" : "Tomato sauce", quantity: 120, unit: "g", grams: 120, kcal: 60, protein: 2, carbs: 9, fat: 2 },
      { name: "Parmesan", quantity: 15, unit: "g", grams: 15, kcal: 60, protein: 5, carbs: 0, fat: 4 },
      { name: fr ? "Huile d'olive" : "Olive oil", quantity: 1, unit: "tbsp", grams: 13, kcal: 117, protein: 0, carbs: 0, fat: 13 },
    ],
  }));
} else {
  const pantry: string[] = context.pantry ?? [];
  console.log(await call("save_recipe", {
    title: fr ? "Poulet rôti, patates douces & feta" : "Roast chicken, sweet potatoes & feta",
    servings: 2,
    minutes: 25,
    summary: fr ? "Une plaque au four, 44 g de protéines par portion." : "One tray in the oven, 44 g of protein per serving.",
    ingredients: [
      { quantity: 300, unit: "g", name: fr ? "Blanc de poulet" : "Chicken breast", inPantry: pantry.length > 0 },
      { quantity: 2, unit: "", name: fr ? "Patates douces" : "Sweet potatoes" },
      { quantity: 1, unit: "", name: fr ? "Oignon rouge" : "Red onion" },
      { quantity: 100, unit: "g", name: "Feta" },
      { quantity: 2, unit: "tbsp", name: fr ? "Huile d'olive" : "Olive oil" },
    ],
    steps: fr
      ? ["Préchauffer le four à 200 °C.", "Couper les patates douces en cubes et l'oignon en quartiers.", "Ajouter le poulet, l'huile et le paprika.", "Cuire 25 min, émietter la feta."]
      : ["Heat the oven to 200 °C.", "Dice the sweet potatoes, quarter the onion.", "Add the chicken, oil and paprika.", "Roast 25 min, crumble the feta on top."],
  }));
}
await client.close();
