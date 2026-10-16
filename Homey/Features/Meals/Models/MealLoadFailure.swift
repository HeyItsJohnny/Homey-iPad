import Foundation

/// Safe diagnostics only: never includes server messages, response values, titles, IDs or tokens.
struct MealLoadFailure: LocalizedError, Equatable, Sendable {
    let operation: String
    let kind: String
    let code: String?
    let path: String?

    static func capture(operation: String, error: Error, postgrestCode: String? = nil) -> MealLoadFailure {
        if let failure = error as? MealLoadFailure { return failure }
        var kind = String(describing: type(of: error))
        var path: String?
        switch error {
        case DecodingError.keyNotFound(let key, let context):
            kind = "DecodingError.keyNotFound"
            path = codingPath(context.codingPath + [key])
        case DecodingError.valueNotFound(_, let context):
            kind = "DecodingError.valueNotFound"
            path = codingPath(context.codingPath)
        case DecodingError.typeMismatch(_, let context):
            kind = "DecodingError.typeMismatch"
            path = codingPath(context.codingPath)
        case DecodingError.dataCorrupted(let context):
            kind = "DecodingError.dataCorrupted"
            path = codingPath(context.codingPath)
        default: break
        }
        let rawCode = postgrestCode ?? ((error as NSError).domain == NSURLErrorDomain ? String((error as NSError).code) : nil)
        let code = rawCode.map { String($0.prefix(16).filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) }
        return MealLoadFailure(operation: operation, kind: kind, code: code, path: path)
    }

    private static func codingPath(_ keys: [CodingKey]) -> String {
        let fields: Set<String> = ["entry_id", "home_id", "calendar_event_id", "meal_id", "title", "planned_date", "meal_type",
            "created_at", "updated_at", "created_by", "updated_by", "planned_servings", "meal_notes", "sort_order",
            "shopping_generated", "is_leftover", "leftover_from_entry_id"]
        return keys.map { key in
            if let index = key.intValue { return "[\(index)]" }
            return fields.contains(key.stringValue) ? key.stringValue : "field"
        }.joined(separator: ".")
    }

    var errorDescription: String? {
        let detail = [operation, kind, code.map { "code \($0)" }, path.map { "field \($0)" }].compactMap { $0 }.joined(separator: "; ")
        return "Unable to load this part of the meal plan (\(detail)). Please retry."
    }
}

/// Captures one load independently; failure in one channel never cancels the other.
enum MealLoadResult<Value> {
    case success(Value)
    case failure(MealLoadFailure)
    case cancelled

    static func fetch(operation: String, _ fetch: () async throws -> Value) async -> Self {
        do { return .success(try await fetch()) }
        catch is CancellationError { return .cancelled }
        catch { return .failure(MealLoadFailure.capture(operation: operation, error: error)) }
    }
}
