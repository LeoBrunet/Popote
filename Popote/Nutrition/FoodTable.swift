import Foundation

enum Aisle: String, CaseIterable, Codable {
    case produce, herbs, meatFish, dairy, bakery, pantry, world, spices, frozen, drinks, other

    var name: String {
        switch self {
        case .produce: String(localized: "Fruit & vegetables")
        case .herbs: String(localized: "Fresh herbs")
        case .meatFish: String(localized: "Meat & fish")
        case .dairy: String(localized: "Dairy & eggs")
        case .bakery: String(localized: "Bakery")
        case .pantry: String(localized: "Pantry")
        case .world: String(localized: "World foods")
        case .spices: String(localized: "Spices & condiments")
        case .frozen: String(localized: "Frozen")
        case .drinks: String(localized: "Drinks")
        case .other: String(localized: "Other")
        }
    }

    var icon: String {
        switch self {
        case .produce: "carrot"
        case .herbs: "leaf"
        case .meatFish: "fish"
        case .dairy: "drop"
        case .bakery: "birthday.cake"
        case .pantry: "takeoutbag.and.cup.and.straw"
        case .world: "globe.asia.australia"
        case .spices: "flame"
        case .frozen: "snowflake"
        case .drinks: "wineglass"
        case .other: "basket"
        }
    }
}

/// A generic food with average values per 100 g (Ciqual / USDA order of magnitude).
struct Food: Identifiable, Hashable {
    let id: String
    let en: String
    let fr: String
    let aliases: [String]
    let per100g: Nutrition
    let aisle: Aisle
    var pieceGrams: Double? = nil    // one unit ("1 onion", "2 eggs", "1 clove")
    var density: Double = 1          // g per ml, for spoons and cups
    var staple = false               // salt, pepper, water: never on the shopping list

    var name: String { Locale.current.language.languageCode?.identifier == "fr" ? fr : en }
}

enum FoodTable {
    private static func f(_ id: String, _ en: String, _ fr: String, _ aliases: [String] = [], _ kcal: Double, _ p: Double, _ c: Double, _ fat: Double,
                          _ aisle: Aisle, piece: Double? = nil, density: Double = 1, staple: Bool = false) -> Food {
        Food(id: id, en: en, fr: fr, aliases: aliases, per100g: Nutrition(kcal: kcal, protein: p, carbs: c, fat: fat),
             aisle: aisle, pieceGrams: piece, density: density, staple: staple)
    }

    static let all: [Food] = [
        // Fruit & vegetables
        f("tomato", "Tomato", "Tomate", [], 18, 0.9, 3.9, 0.2, .produce, piece: 120),
        f("cherry-tomato", "Cherry tomatoes", "Tomates cerises", ["cherry tomato", "tomate cerise"], 20, 0.9, 3.5, 0.3, .produce, piece: 15),
        f("onion", "Onion", "Oignon", ["yellow onion", "oignon jaune"], 40, 1.1, 9.3, 0.1, .produce, piece: 110),
        f("red-onion", "Red onion", "Oignon rouge", [], 40, 1.1, 9, 0.1, .produce, piece: 110),
        f("spring-onion", "Spring onions", "Oignons nouveaux", ["scallion", "green onion", "cebette", "oignon vert"], 32, 1.8, 7.3, 0.2, .produce, piece: 15),
        f("shallot", "Shallot", "Échalote", [], 72, 2.5, 16.8, 0.1, .produce, piece: 30),
        f("garlic", "Garlic", "Ail", ["gousse ail"], 149, 6.4, 33, 0.5, .produce, piece: 5),
        f("ginger", "Ginger", "Gingembre", [], 80, 1.8, 18, 0.8, .produce, piece: 15),
        f("carrot", "Carrot", "Carotte", [], 41, 0.9, 9.6, 0.2, .produce, piece: 80),
        f("potato", "Potatoes", "Pommes de terre", ["potato", "pomme de terre", "patate"], 77, 2, 17, 0.1, .produce, piece: 170),
        f("sweet-potato", "Sweet potato", "Patate douce", [], 86, 1.6, 20, 0.1, .produce, piece: 250),
        f("zucchini", "Zucchini", "Courgette", ["courgette"], 17, 1.2, 3.1, 0.3, .produce, piece: 200),
        f("eggplant", "Eggplant", "Aubergine", ["aubergine"], 25, 1, 6, 0.2, .produce, piece: 300),
        f("bell-pepper", "Bell pepper", "Poivron", ["pepper red", "red pepper", "poivron rouge", "poivron vert", "poivron jaune"], 31, 1, 6, 0.3, .produce, piece: 160),
        f("cucumber", "Cucumber", "Concombre", [], 15, 0.7, 3.6, 0.1, .produce, piece: 300),
        f("avocado", "Avocado", "Avocat", [], 160, 2, 8.5, 14.7, .produce, piece: 150),
        f("lemon", "Lemon", "Citron", ["citron jaune"], 29, 1.1, 9.3, 0.3, .produce, piece: 100),
        f("lemon-juice", "Lemon juice", "Jus de citron", [], 22, 0.4, 6.9, 0.2, .produce),
        f("lime", "Lime", "Citron vert", [], 30, 0.7, 10.5, 0.2, .produce, piece: 60),
        f("orange", "Orange", "Orange", [], 47, 0.9, 11.8, 0.1, .produce, piece: 180),
        f("apple", "Apple", "Pomme", [], 52, 0.3, 13.8, 0.2, .produce, piece: 150),
        f("banana", "Banana", "Banane", [], 89, 1.1, 22.8, 0.3, .produce, piece: 120),
        f("strawberry", "Strawberries", "Fraises", ["strawberry", "fraise"], 32, 0.7, 7.7, 0.3, .produce, piece: 15),
        f("blueberry", "Blueberries", "Myrtilles", ["blueberry", "myrtille"], 57, 0.7, 14.5, 0.3, .produce),
        f("raspberry", "Raspberries", "Framboises", ["raspberry", "framboise"], 52, 1.2, 12, 0.7, .produce),
        f("mango", "Mango", "Mangue", [], 60, 0.8, 15, 0.4, .produce, piece: 300),
        f("spinach", "Spinach", "Épinards", ["epinard", "pousse epinard", "baby spinach"], 23, 2.9, 3.6, 0.4, .produce),
        f("lettuce", "Lettuce", "Salade", ["laitue", "salad", "batavia", "romaine", "sucrine"], 15, 1.4, 2.9, 0.2, .produce, piece: 300),
        f("rocket", "Rocket", "Roquette", ["arugula"], 25, 2.6, 3.7, 0.7, .produce),
        f("broccoli", "Broccoli", "Brocoli", [], 34, 2.8, 6.6, 0.4, .produce, piece: 400),
        f("cauliflower", "Cauliflower", "Chou-fleur", ["chou fleur"], 25, 1.9, 5, 0.3, .produce, piece: 600),
        f("cabbage", "Cabbage", "Chou", ["chou blanc", "chou rouge", "red cabbage"], 25, 1.3, 5.8, 0.1, .produce, piece: 800),
        f("mushroom", "Mushrooms", "Champignons", ["mushroom", "champignon de paris", "champignon"], 22, 3.1, 3.3, 0.3, .produce, piece: 20),
        f("leek", "Leek", "Poireau", [], 61, 1.5, 14, 0.3, .produce, piece: 150),
        f("celery", "Celery", "Céleri", ["celery stalk", "branche celeri"], 16, 0.7, 3, 0.2, .produce, piece: 40),
        f("peas", "Peas", "Petits pois", ["pea", "petit poi"], 81, 5.4, 14.5, 0.4, .produce),
        f("green-beans", "Green beans", "Haricots verts", ["haricot vert", "green bean"], 31, 1.8, 7, 0.2, .produce),
        f("corn", "Sweetcorn", "Maïs", ["corn", "mai", "sweet corn"], 86, 3.3, 19, 1.4, .produce),
        f("butternut", "Butternut squash", "Butternut", ["courge butternut", "courge", "squash"], 45, 1, 11.7, 0.1, .produce, piece: 1000),
        f("pumpkin", "Pumpkin", "Potiron", ["citrouille", "potimarron"], 26, 1, 6.5, 0.1, .produce),
        f("chili", "Chili", "Piment", ["red chili", "piment rouge", "piment oiseau"], 40, 1.9, 8.8, 0.4, .produce, piece: 15),
        f("radish", "Radishes", "Radis", ["radish"], 16, 0.7, 3.4, 0.1, .produce, piece: 10),
        f("beetroot", "Beetroot", "Betterave", ["beet"], 43, 1.6, 9.6, 0.2, .produce, piece: 150),
        f("fennel", "Fennel", "Fenouil", [], 31, 1.2, 7.3, 0.2, .produce, piece: 250),
        f("kale", "Kale", "Chou kale", ["kale"], 49, 4.3, 8.8, 0.9, .produce),
        // Fresh herbs
        f("parsley", "Parsley", "Persil", [], 36, 3, 6.3, 0.8, .herbs),
        f("coriander", "Coriander", "Coriandre", ["cilantro"], 23, 2.1, 3.7, 0.5, .herbs),
        f("basil", "Basil", "Basilic", [], 23, 3.2, 2.7, 0.6, .herbs),
        f("mint", "Mint", "Menthe", [], 70, 3.8, 15, 0.9, .herbs),
        f("chives", "Chives", "Ciboulette", [], 30, 3.3, 4.4, 0.7, .herbs),
        f("dill", "Dill", "Aneth", [], 43, 3.5, 7, 1.1, .herbs),
        f("thyme", "Thyme", "Thym", [], 101, 5.6, 24, 1.7, .herbs),
        f("rosemary", "Rosemary", "Romarin", [], 131, 3.3, 21, 5.9, .herbs),
        // Meat & fish
        f("chicken-breast", "Chicken breast", "Blanc de poulet", ["filet poulet", "escalope poulet", "chicken fillet", "poulet blanc", "poitrine poulet"], 110, 23, 0, 1.5, .meatFish, piece: 150),
        f("chicken-thigh", "Chicken thighs", "Cuisses de poulet", ["chicken thigh", "cuisse poulet", "haut cuisse poulet"], 177, 18, 0, 11.5, .meatFish, piece: 120),
        f("chicken", "Chicken", "Poulet", ["whole chicken", "poulet entier"], 190, 19, 0, 12.5, .meatFish, piece: 1500),
        f("ground-beef", "Ground beef", "Bœuf haché", ["minced beef", "beef mince", "viande hachee", "steak hache", "boeuf hache"], 175, 20, 0, 10, .meatFish, piece: 125),
        f("beef", "Beef", "Bœuf", ["steak", "boeuf", "rumsteck", "bavette", "entrecote"], 150, 22, 0, 7, .meatFish, piece: 180),
        f("pork", "Pork", "Porc", ["filet mignon", "pork loin", "echine porc"], 140, 21, 0, 6, .meatFish),
        f("bacon", "Bacon", "Lardons", ["lardon", "poitrine fumee", "pancetta"], 260, 15, 0.5, 22, .meatFish, piece: 15),
        f("ham", "Ham", "Jambon", ["jambon blanc", "jambon cru", "prosciutto"], 115, 20, 1, 3.5, .meatFish, piece: 40),
        f("chorizo", "Chorizo", "Chorizo", [], 455, 24, 2, 39, .meatFish),
        f("sausage", "Sausages", "Saucisses", ["sausage", "saucisse"], 270, 14, 2, 23, .meatFish, piece: 80),
        f("turkey", "Turkey", "Dinde", ["escalope dinde", "turkey breast"], 105, 23, 0, 1.5, .meatFish, piece: 150),
        f("lamb", "Lamb", "Agneau", [], 230, 18, 0, 17, .meatFish),
        f("salmon", "Salmon", "Saumon", ["pave saumon", "salmon fillet", "filet saumon"], 200, 20, 0, 13, .meatFish, piece: 130),
        f("smoked-salmon", "Smoked salmon", "Saumon fumé", [], 180, 22, 0, 10, .meatFish, piece: 25),
        f("tuna", "Tuna (canned)", "Thon en conserve", ["thon", "tuna", "thon naturel"], 116, 26, 0, 1, .meatFish, piece: 140),
        f("cod", "Cod", "Cabillaud", ["dos cabillaud", "white fish", "poisson blanc", "colin", "lieu"], 82, 18, 0, 0.7, .meatFish, piece: 150),
        f("shrimp", "Prawns", "Crevettes", ["shrimp", "prawn", "crevette", "gambas"], 85, 19, 0, 1, .meatFish, piece: 15),
        // Dairy & eggs
        f("egg", "Eggs", "Œufs", ["egg", "oeuf", "jaune oeuf", "blanc oeuf"], 140, 12.5, 0.7, 9.8, .dairy, piece: 55),
        f("milk", "Milk", "Lait", ["lait demi ecreme", "whole milk", "lait entier"], 46, 3.3, 4.8, 1.6, .dairy, density: 1.03),
        f("butter", "Butter", "Beurre", ["beurre doux", "beurre demi sel", "unsalted butter"], 740, 0.6, 0.6, 82, .dairy, density: 0.95),
        f("creme-fraiche", "Crème fraîche", "Crème fraîche", ["creme epaisse", "sour cream"], 300, 2.4, 3, 30, .dairy),
        f("cream", "Cream", "Crème liquide", ["heavy cream", "creme entiere", "creme liquide entiere", "whipping cream", "double cream", "creme"], 290, 2.1, 3, 30, .dairy),
        f("light-cream", "Light cream", "Crème légère", ["creme legere", "creme 15", "single cream"], 160, 2.8, 3.9, 15, .dairy),
        f("greek-yogurt", "Greek yogurt", "Yaourt grec", ["yaourt grec", "greek yoghurt"], 120, 4, 4, 10, .dairy, piece: 150),
        f("skyr", "Skyr", "Skyr", ["fromage blanc 0", "yaourt 0"], 60, 10, 4, 0.2, .dairy, piece: 150),
        f("yogurt", "Yogurt", "Yaourt nature", ["yaourt", "yoghurt", "plain yogurt"], 60, 4, 5, 2.5, .dairy, piece: 125),
        f("fromage-blanc", "Fromage blanc", "Fromage blanc", ["quark"], 75, 7.5, 4, 3, .dairy),
        f("feta", "Feta", "Feta", [], 265, 14, 4, 21, .dairy, piece: 200),
        f("mozzarella", "Mozzarella", "Mozzarella", ["burrata"], 250, 18, 2, 19, .dairy, piece: 125),
        f("parmesan", "Parmesan", "Parmesan", ["parmigiano", "grana padano", "pecorino"], 400, 33, 0, 29, .dairy),
        f("cheddar", "Cheddar", "Cheddar", [], 400, 25, 1.3, 33, .dairy),
        f("gruyere", "Grated cheese", "Gruyère râpé", ["gruyere", "emmental", "comte", "fromage rape", "grated cheese"], 390, 28, 0, 30, .dairy),
        f("goat-cheese", "Goat cheese", "Fromage de chèvre", ["chevre", "buche chevre", "goat cheese"], 300, 18, 2, 25, .dairy),
        f("ricotta", "Ricotta", "Ricotta", [], 140, 9, 4, 10, .dairy),
        f("cream-cheese", "Cream cheese", "Fromage frais", ["philadelphia", "st moret", "cream cheese", "fromage a tartiner"], 250, 6, 4, 24, .dairy),
        f("coconut-milk", "Coconut milk", "Lait de coco", ["creme de coco", "coconut cream"], 190, 1.8, 3, 19, .world, piece: 400),
        f("plant-milk", "Plant milk", "Lait végétal", ["lait amande", "almond milk", "oat milk", "lait avoine", "lait soja", "soy milk"], 40, 1, 6, 1.3, .dairy),
        // Bakery
        f("bread", "Bread", "Pain", ["baguette", "pain de campagne", "sourdough", "pain complet"], 260, 9, 51, 1.5, .bakery, piece: 250),
        f("sandwich-bread", "Sandwich bread", "Pain de mie", ["toast", "brioche"], 270, 8, 49, 4, .bakery, piece: 25),
        f("burger-bun", "Burger buns", "Pains burger", ["bun", "pain burger"], 280, 9, 50, 5, .bakery, piece: 60),
        f("tortilla", "Tortillas", "Tortillas", ["wrap", "tortilla"], 300, 8, 50, 7, .bakery, piece: 60),
        f("pita", "Pita bread", "Pain pita", ["pita", "naan"], 275, 9, 55, 1.2, .bakery, piece: 70),
        // Pantry
        f("rice", "Rice", "Riz", ["basmati", "riz basmati", "jasmine rice", "riz thai", "riz complet", "arborio", "riz rond", "brown rice"], 355, 7, 78, 0.6, .pantry, density: 0.85),
        f("sushi-rice", "Sushi rice", "Riz à sushi", ["riz sushi"], 355, 6.5, 79, 0.5, .world, density: 0.85),
        f("pasta", "Pasta", "Pâtes", ["pate", "spaghetti", "penne", "tagliatelle", "fusilli", "linguine", "rigatoni", "macaroni", "coquillette", "farfalle", "orzo"], 355, 12.5, 71, 1.5, .pantry),
        f("noodles", "Noodles", "Nouilles", ["nouille", "nouilles riz", "rice noodles", "udon", "ramen", "soba", "vermicelle"], 360, 9, 78, 1, .world),
        f("quinoa", "Quinoa", "Quinoa", [], 368, 14, 64, 6, .pantry, density: 0.8),
        f("couscous", "Couscous", "Semoule", ["semoule", "couscous"], 360, 12.5, 72, 1.5, .pantry, density: 0.75),
        f("bulgur", "Bulgur", "Boulgour", ["boulgour", "bulgur"], 345, 12, 70, 1.5, .pantry, density: 0.75),
        f("oats", "Rolled oats", "Flocons d'avoine", ["oat", "avoine", "porridge oats", "flocon avoine"], 370, 13.5, 58.7, 7, .pantry, density: 0.4),
        f("flour", "Flour", "Farine", ["farine de ble", "all purpose flour", "plain flour", "farine t55", "farine t45"], 345, 10, 72, 1.2, .pantry, density: 0.55),
        f("cornstarch", "Cornstarch", "Maïzena", ["maizena", "fecule", "corn starch"], 360, 0.3, 88, 0.1, .pantry, density: 0.6),
        f("breadcrumbs", "Breadcrumbs", "Chapelure", ["panko"], 395, 13, 72, 5, .pantry, density: 0.45),
        f("lentils", "Lentils", "Lentilles", ["lentille", "lentille verte", "green lentils"], 340, 24, 50, 1.5, .pantry, density: 0.8),
        f("red-lentils", "Red lentils", "Lentilles corail", ["lentille corail", "red lentil"], 345, 24, 52, 1.5, .pantry, density: 0.8),
        f("chickpeas", "Chickpeas", "Pois chiches", ["chickpea", "pois chiche"], 140, 7.5, 18, 2.5, .pantry, piece: 240),
        f("kidney-beans", "Kidney beans", "Haricots rouges", ["haricot rouge", "black beans", "haricot noir"], 115, 8, 15, 0.5, .pantry, piece: 250),
        f("white-beans", "White beans", "Haricots blancs", ["haricot blanc", "cannellini"], 110, 7, 16, 0.5, .pantry, piece: 250),
        f("tofu", "Tofu", "Tofu", ["tofu ferme", "firm tofu", "tofu fume"], 125, 13, 2, 7.5, .world, piece: 200),
        f("puff-pastry", "Puff pastry", "Pâte feuilletée", ["pate feuilletee"], 400, 6, 38, 25, .dairy, piece: 230),
        f("shortcrust", "Shortcrust pastry", "Pâte brisée", ["pate brisee", "pate sablee", "pie crust"], 430, 6, 45, 25, .dairy, piece: 230),
        f("pizza-dough", "Pizza dough", "Pâte à pizza", ["pate pizza"], 260, 7, 50, 3, .dairy, piece: 260),
        f("olive-oil", "Olive oil", "Huile d'olive", ["huile olive", "extra virgin olive oil"], 900, 0, 0, 100, .pantry, density: 0.92),
        f("oil", "Vegetable oil", "Huile", ["huile tournesol", "huile colza", "huile neutre", "sunflower oil", "vegetable oil", "canola oil", "oil"], 900, 0, 0, 100, .pantry, density: 0.92),
        f("sesame-oil", "Sesame oil", "Huile de sésame", ["huile sesame"], 900, 0, 0, 100, .world, density: 0.92),
        f("sugar", "Sugar", "Sucre", ["sucre en poudre", "caster sugar", "sucre blanc", "sucre glace", "icing sugar"], 400, 0, 100, 0, .pantry, density: 0.85),
        f("brown-sugar", "Brown sugar", "Sucre roux", ["cassonade", "vergeoise", "sucre complet"], 390, 0, 98, 0, .pantry, density: 0.8),
        f("honey", "Honey", "Miel", [], 320, 0.3, 80, 0, .pantry, density: 1.4),
        f("maple-syrup", "Maple syrup", "Sirop d'érable", ["sirop erable", "agave"], 260, 0, 67, 0, .pantry, density: 1.3),
        f("dark-chocolate", "Dark chocolate", "Chocolat noir", ["chocolat", "chocolate", "pepite chocolat", "chocolate chips"], 550, 7, 45, 37, .pantry),
        f("cocoa", "Cocoa powder", "Cacao en poudre", ["cacao", "cocoa"], 360, 20, 25, 14, .pantry, density: 0.5),
        f("baking-powder", "Baking powder", "Levure chimique", ["levure", "bicarbonate", "baking soda", "yeast", "levure boulangere"], 100, 0, 25, 0, .pantry, piece: 11, density: 0.9),
        f("vanilla", "Vanilla", "Vanille", ["extrait vanille", "sucre vanille", "vanilla extract", "gousse vanille"], 290, 0, 13, 0, .pantry, piece: 8),
        f("peanut-butter", "Peanut butter", "Beurre de cacahuète", ["beurre cacahuete", "peanut butter"], 600, 25, 16, 50, .pantry),
        f("tahini", "Tahini", "Tahini", ["tahin", "puree sesame"], 600, 17, 21, 54, .world),
        f("almonds", "Almonds", "Amandes", ["almond", "amande", "poudre amande", "ground almonds"], 600, 21, 9, 52, .pantry, density: 0.5),
        f("walnuts", "Walnuts", "Noix", ["walnut", "cerneaux noix", "noix"], 700, 15, 7, 65, .pantry),
        f("cashews", "Cashews", "Noix de cajou", ["cashew", "cajou"], 590, 18, 27, 47, .pantry),
        f("peanuts", "Peanuts", "Cacahuètes", ["peanut", "cacahuete", "arachide"], 590, 25, 16, 49, .pantry),
        f("pine-nuts", "Pine nuts", "Pignons de pin", ["pignon", "pine nut"], 670, 14, 13, 68, .pantry),
        f("sesame", "Sesame seeds", "Graines de sésame", ["sesame", "graine sesame", "sesame seed"], 600, 18, 12, 50, .pantry, density: 0.6),
        f("chia", "Chia seeds", "Graines de chia", ["chia", "graine chia"], 490, 17, 42, 31, .pantry, density: 0.65),
        f("raisins", "Raisins", "Raisins secs", ["raisin sec", "dried fruit", "cranberries"], 300, 3, 79, 0.5, .pantry),
        f("tomato-paste", "Tomato paste", "Concentré de tomate", ["concentre tomate", "double concentre"], 82, 4.3, 19, 0.5, .pantry),
        f("canned-tomatoes", "Canned tomatoes", "Tomates concassées", ["tomate concassee", "coulis tomate", "passata", "pulpe tomate", "chopped tomatoes", "crushed tomatoes", "sauce tomate", "tomato sauce"], 25, 1.2, 4, 0.2, .pantry),
        f("stock", "Stock", "Bouillon", ["broth", "fond", "bouillon volaille", "bouillon legume", "chicken stock", "vegetable stock"], 5, 0.5, 0.5, 0.1, .pantry),
        f("stock-cube", "Stock cube", "Cube de bouillon", ["cube bouillon", "bouillon cube", "kub"], 250, 10, 20, 15, .pantry, piece: 10),
        f("olives", "Olives", "Olives", ["olive"], 145, 1, 4, 15, .pantry, piece: 4),
        f("capers", "Capers", "Câpres", ["capre"], 23, 2.4, 4.9, 0.9, .pantry),
        // World foods
        f("soy-sauce", "Soy sauce", "Sauce soja", ["sauce soja", "tamari", "shoyu", "soy"], 55, 8, 5, 0.5, .world, density: 1.1),
        f("miso", "Miso", "Miso", ["miso blanc", "white miso", "pate miso"], 200, 12, 26, 6, .world, density: 1.2),
        f("rice-vinegar", "Rice vinegar", "Vinaigre de riz", ["vinaigre riz"], 20, 0, 4, 0, .world),
        f("fish-sauce", "Fish sauce", "Sauce poisson", ["nuoc mam", "nam pla"], 35, 5, 3.6, 0, .world, density: 1.2),
        f("curry-paste", "Curry paste", "Pâte de curry", ["pate curry", "red curry paste", "green curry paste"], 150, 3, 12, 10, .world, density: 1.1),
        f("sriracha", "Sriracha", "Sriracha", ["harissa", "hot sauce", "sauce piquante", "gochujang", "sambal"], 95, 2, 19, 1, .world),
        f("nori", "Nori", "Algue nori", ["nori"], 35, 6, 5, 0.3, .world, piece: 3),
        // Spices & condiments
        f("salt", "Salt", "Sel", ["fleur de sel", "gros sel", "sea salt"], 0, 0, 0, 0, .spices, density: 1.2, staple: true),
        f("pepper", "Black pepper", "Poivre", ["poivre noir", "pepper", "black pepper"], 250, 10, 64, 3, .spices, density: 0.5, staple: true),
        f("water", "Water", "Eau", ["eau", "water"], 0, 0, 0, 0, .other, staple: true),
        f("mustard", "Mustard", "Moutarde", ["moutarde dijon", "dijon mustard"], 150, 7, 5, 11, .spices),
        f("mayonnaise", "Mayonnaise", "Mayonnaise", ["mayo"], 700, 1, 1, 76, .spices, density: 0.95),
        f("ketchup", "Ketchup", "Ketchup", [], 110, 1.2, 25, 0.2, .spices, density: 1.1),
        f("vinegar", "Vinegar", "Vinaigre", ["vinaigre vin", "white wine vinegar", "cider vinegar", "vinaigre cidre"], 20, 0, 1, 0, .spices),
        f("balsamic", "Balsamic vinegar", "Vinaigre balsamique", ["balsamique", "balsamic"], 110, 0.5, 17, 0, .spices, density: 1.1),
        f("cumin", "Cumin", "Cumin", [], 375, 18, 44, 22, .spices, density: 0.5),
        f("paprika", "Paprika", "Paprika", ["paprika fume", "smoked paprika"], 280, 14, 54, 13, .spices, density: 0.5),
        f("curry", "Curry powder", "Curry", ["curry powder", "curry poudre", "garam masala", "ras el hanout"], 325, 14, 56, 14, .spices, density: 0.5),
        f("turmeric", "Turmeric", "Curcuma", [], 312, 10, 67, 3.3, .spices, density: 0.5),
        f("ground-coriander", "Ground coriander", "Coriandre moulue", ["coriandre en poudre", "coriander powder", "graine coriandre"], 298, 12, 55, 18, .spices, density: 0.5),
        f("ground-ginger", "Ground ginger", "Gingembre moulu", ["gingembre en poudre", "ginger powder"], 335, 9, 72, 4, .spices, density: 0.5),
        f("cinnamon", "Cinnamon", "Cannelle", [], 247, 4, 81, 1.2, .spices, density: 0.5),
        f("chili-flakes", "Chili flakes", "Piment en poudre", ["piment espelette", "chili powder", "cayenne", "chili flake"], 280, 13, 50, 14, .spices, density: 0.5),
        f("dried-herbs", "Dried herbs", "Herbes de Provence", ["herbe provence", "origan", "oregano", "dried oregano", "italian herbs", "laurier", "bay leaf"], 270, 9, 69, 4, .spices, piece: 0.2, density: 0.3),
        f("pesto", "Pesto", "Pesto", ["pesto"], 450, 5, 6, 45, .spices),
        // Frozen
        f("frozen-veg", "Frozen vegetables", "Légumes surgelés", ["frozen vegetables", "poelee legume"], 50, 2.5, 8, 0.5, .frozen),
        // Drinks
        f("white-wine", "White wine", "Vin blanc", ["dry white wine", "vin blanc sec"], 80, 0.1, 2.6, 0, .drinks),
        f("red-wine", "Red wine", "Vin rouge", ["vin"], 85, 0.1, 2.6, 0, .drinks),
        f("beer", "Beer", "Bière", ["biere"], 43, 0.5, 3.6, 0, .drinks),
    ]

    static let byID: [String: Food] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Every name a food answers to, as normalized keys, longest first.
    private static let index: [(key: String, words: [String], food: Food)] = {
        all.flatMap { food in
            ([food.en, food.fr] + food.aliases).map { name -> (String, [String], Food) in
                let words = TextKey.words(name)
                return (words.joined(separator: " "), words, food)
            }
        }
        .filter { !$0.0.isEmpty }
        .sorted { $0.0.count > $1.0.count }
    }()

    /// Best generic food for an ingredient name ("2 pavés de saumon" → Salmon).
    static func match(_ name: String) -> Food? {
        let words = TextKey.words(name)
        guard !words.isEmpty else { return nil }
        let text = " " + words.joined(separator: " ") + " "
        return index.first { text.contains(" " + $0.key + " ") }?.food
    }

    static func search(_ query: String) -> [Food] {
        let key = TextKey.key(query)
        guard !key.isEmpty else { return all.sorted { $0.name < $1.name } }
        return all.filter { food in
            ([food.en, food.fr] + food.aliases).contains { TextKey.key($0).contains(key) }
        }
    }
}
