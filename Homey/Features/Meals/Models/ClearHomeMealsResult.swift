import Foundation

struct ClearHomeMealsResult: Codable, Hashable, Sendable {
    let mealsDeleted: Int
    let mealRecipesDeleted: Int
    let recipeIngredientsDeleted: Int
    let recipeStepsDeleted: Int
    let mealPhotosDeleted: Int
    let mealFavoritesDeleted: Int
    let mealCollectionsDeleted: Int
    let mealCollectionItemsDeleted: Int
    let mealPlanEntriesDeleted: Int
    let quickMealsDeleted: Int

    enum CodingKeys: String, CodingKey {
        case mealsDeleted = "meals_deleted"
        case mealRecipesDeleted = "meal_recipes_deleted"
        case recipeIngredientsDeleted = "recipe_ingredients_deleted"
        case recipeStepsDeleted = "recipe_steps_deleted"
        case mealPhotosDeleted = "meal_photos_deleted"
        case mealFavoritesDeleted = "meal_favorites_deleted"
        case mealCollectionsDeleted = "meal_collections_deleted"
        case mealCollectionItemsDeleted = "meal_collection_items_deleted"
        case mealPlanEntriesDeleted = "meal_plan_entries_deleted"
        case quickMealsDeleted = "quick_meals_deleted"
    }
}

