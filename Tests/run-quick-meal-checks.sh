#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
quick_check_dir=$(mktemp -d /tmp/homey-quick-checks.XXXXXX)
trap 'rm -rf "$quick_check_dir"' EXIT
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path "$quick_check_dir/cache" \
 Homey/Features/Meals/Models/MealType.swift \
 Homey/Features/Meals/Models/QuickPlannedMeal.swift \
 Homey/Features/Meals/Models/QuickMealError.swift \
 Homey/Features/Meals/Models/ClearHomeMealsResult.swift \
 Tests/QuickMealChecks.swift -o "$quick_check_dir/checks"
"$quick_check_dir/checks"
xcrun swiftc -module-cache-path "$quick_check_dir/cache" \
 Homey/Features/Meals/Models/MealType.swift \
 Homey/Features/Meals/Models/QuickPlannedMeal.swift \
 Homey/Features/Meals/Models/Meal.swift \
 Homey/Features/Meals/Models/MealDifficulty.swift \
 Homey/Features/Meals/Models/MealModelDecoding.swift \
 Homey/Features/Meals/Models/MealEventDetail.swift \
 Homey/Features/Meals/Models/MealLoadFailure.swift \
 Homey/Features/Meals/Models/AutoPlanModels.swift \
 Homey/Features/Calendar/Models/CalendarModels.swift \
 Homey/Features/Meals/Services/AutoPlanEngine.swift \
 Tests/QuickMealAutoPlanChecks.swift -o "$quick_check_dir/auto-plan-checks"
"$quick_check_dir/auto-plan-checks"
python3 Tests/check-quick-meal-contracts.py

xcrun swiftc -module-cache-path "$quick_check_dir/cache" \
 Homey/Features/Meals/Models/MealType.swift \
 Homey/Features/Meals/Models/MealSlotAddRoute.swift \
 Tests/MealSlotAddRouteChecks.swift -o "$quick_check_dir/menu-route-checks"
"$quick_check_dir/menu-route-checks"

xcrun swiftc -module-cache-path "$quick_check_dir/cache" \
 Homey/Features/Meals/Models/MealType.swift \
 Homey/Features/Meals/Models/QuickPlannedMeal.swift \
 Homey/Features/Meals/Models/MealLoadFailure.swift \
 Tests/MealLoadingChecks.swift -o "$quick_check_dir/loading-checks"
"$quick_check_dir/loading-checks"
