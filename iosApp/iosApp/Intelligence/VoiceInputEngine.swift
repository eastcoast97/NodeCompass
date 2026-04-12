import Foundation
import SwiftUI
import Speech

/// Structured action parsed from user voice input.
enum VoiceAction: Equatable {
    case foodLog(mealType: String, items: [String], location: String?, isHomeMade: Bool)
    case cashTransaction(amount: Double, merchant: String?, category: String?)
    case mood(level: Int, note: String?)
    case workout(type: String, durationMinutes: Int?)
    case habit(name: String, completed: Bool)
    case note(text: String)
    case unknown(text: String)

    /// Human-readable confirmation message for the parsed action.
    var confirmationMessage: String {
        switch self {
        case .foodLog(let meal, let items, let location, let homeMade):
            let itemsStr = items.joined(separator: ", ")
            let locStr = location.map { " at \($0)" } ?? ""
            let homeStr = homeMade ? " (home-cooked)" : ""
            return "Logged: \(itemsStr) for \(meal)\(locStr)\(homeStr)"
        case .cashTransaction(let amount, let merchant, let category):
            let merchantStr = merchant ?? "unknown"
            let catStr = category.map { " (\($0))" } ?? ""
            return "Spent \(NC.currencySymbol)\(String(format: "%.0f", amount)) at \(merchantStr)\(catStr)"
        case .mood(let level, let note):
            let labels = ["", "Terrible", "Bad", "Okay", "Good", "Great"]
            let label = level >= 1 && level <= 5 ? labels[level] : "Unknown"
            let noteStr = note.map { " - \($0)" } ?? ""
            return "Mood: \(label)\(noteStr)"
        case .workout(let type, let duration):
            let durStr = duration.map { " for \($0) min" } ?? ""
            return "Workout: \(type)\(durStr)"
        case .habit(let name, let completed):
            return "\(completed ? "Completed" : "Skipped"): \(name)"
        case .note(let text):
            let preview = text.prefix(60)
            return "Note: \(preview)\(text.count > 60 ? "..." : "")"
        case .unknown(let text):
            let preview = text.prefix(60)
            return "Couldn't parse: \(preview)\(text.count > 60 ? "..." : "")"
        }
    }

    /// SF Symbol icon for the action type.
    var icon: String {
        switch self {
        case .foodLog: return "fork.knife"
        case .cashTransaction: return NC.currencyIconCircle
        case .mood: return "face.smiling"
        case .workout: return "figure.run"
        case .habit: return "checkmark.circle.fill"
        case .note: return "note.text"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Voice Input Engine — transcribes speech and parses it into structured life-tracking actions.
///
/// Uses Apple Speech framework for transcription and Groq (Llama 3.3 70B) for
/// natural language understanding and structured data extraction.
actor VoiceInputEngine {
    static let shared = VoiceInputEngine()

    private init() {}

    // MARK: - Parse Text via Groq

    /// Send transcribed text to Groq to classify and extract structured data.
    func parseText(_ text: String) async -> VoiceAction {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown(text: text) }

        let prompt = """
        You are a life-tracking assistant. Parse the user's voice input into a structured action.
        Classify as one of: food_log, cash_transaction, mood, workout, habit, note

        Return JSON: {"type": "food_log", "data": {...}}

        For food_log: {"meal_type": "lunch/dinner/breakfast/snack", "items": ["item1", "item2"], "location": null or "place name", "is_home_made": true/false}
        For cash_transaction: {"amount": 15.0, "merchant": "Starbucks" or null, "category": "Food" or "Transport" etc}
        For mood: {"level": 1-5, "note": "optional note"}
        For workout: {"type": "gym/run/yoga/etc", "duration_minutes": 30 or null}
        For habit: {"name": "meditate", "completed": true}
        For note: {"text": "the full text"}

        User said: "\(trimmed)"
        """

        guard let jsonString = await GroqService.shared.generate(prompt: prompt, maxTokens: 512) else {
            return .unknown(text: trimmed)
        }

        return parseGroqResponse(jsonString, originalText: trimmed)
    }

    /// Parse the JSON response from Groq into a VoiceAction.
    private func parseGroqResponse(_ jsonString: String, originalText: String) -> VoiceAction {
        // Clean up markdown fences if present
        let cleaned = jsonString
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              let actionData = json["data"] as? [String: Any] else {
            return .unknown(text: originalText)
        }

        switch type {
        case "food_log":
            let mealType = actionData["meal_type"] as? String ?? inferMealType()
            let items = actionData["items"] as? [String] ?? []
            let location = actionData["location"] as? String
            let isHomeMade = actionData["is_home_made"] as? Bool ?? false
            guard !items.isEmpty else { return .unknown(text: originalText) }
            return .foodLog(mealType: mealType, items: items, location: location, isHomeMade: isHomeMade)

        case "cash_transaction":
            guard let amount = parseAmount(actionData["amount"]) else {
                return .unknown(text: originalText)
            }
            let merchant = actionData["merchant"] as? String
            let category = actionData["category"] as? String
            return .cashTransaction(amount: amount, merchant: merchant, category: category)

        case "mood":
            guard let level = actionData["level"] as? Int, (1...5).contains(level) else {
                return .unknown(text: originalText)
            }
            let note = actionData["note"] as? String
            return .mood(level: level, note: note)

        case "workout":
            let workoutType = actionData["type"] as? String ?? "workout"
            let duration = actionData["duration_minutes"] as? Int
            return .workout(type: workoutType, durationMinutes: duration)

        case "habit":
            guard let name = actionData["name"] as? String, !name.isEmpty else {
                return .unknown(text: originalText)
            }
            let completed = actionData["completed"] as? Bool ?? true
            return .habit(name: name, completed: completed)

        case "note":
            let text = actionData["text"] as? String ?? originalText
            return .note(text: text)

        default:
            return .unknown(text: originalText)
        }
    }

    /// Safely parse an amount value that may be Int, Double, or String.
    private func parseAmount(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    /// Infer meal type from current time of day.
    private func inferMealType() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "breakfast"
        case 11..<15: return "lunch"
        case 15..<17: return "snack"
        case 17..<22: return "dinner"
        default: return "snack"
        }
    }

    // MARK: - Execute Action (dispatch to stores)

    /// Execute a parsed voice action by dispatching to the appropriate data store.
    func executeAction(_ action: VoiceAction) async {
        switch action {
        case .foodLog(let mealType, let items, let location, let isHomeMade):
            let foodItems = items.map { name in
                FoodItem(name: name, quantity: 1, isHomemade: isHomeMade)
            }
            let entry = FoodStore.FoodLogEntry(
                mealType: mealType,
                items: foodItems,
                source: .manual,
                locationName: location
            )
            await FoodStore.shared.addEntry(entry)

        case .cashTransaction(let amount, let merchant, let category):
            let merchantName = merchant ?? "Unknown"
            await MainActor.run {
                TransactionStore.shared.addManualTransaction(
                    amount: amount,
                    merchant: merchantName,
                    category: category
                )
            }

        case .mood(let level, let note):
            let moodLevel: MoodStore.MoodLevel
            switch level {
            case 1: moodLevel = .terrible
            case 2: moodLevel = .bad
            case 3: moodLevel = .okay
            case 4: moodLevel = .good
            case 5: moodLevel = .great
            default: moodLevel = .okay
            }
            await MoodStore.shared.logMood(moodLevel, note: note)

        case .workout(let type, let duration):
            // Log as a workout life event
            let durMinutes = duration.map { Double($0) } ?? 0
            let workoutEvent = WorkoutEvent(
                activityType: type,
                durationMinutes: durMinutes,
                caloriesBurned: nil,
                distanceMeters: nil
            )
            let lifeEvent = LifeEvent(
                timestamp: Date(),
                source: .manual,
                payload: .workout(workoutEvent)
            )
            _ = await EventStore.shared.append(lifeEvent)

        case .habit(_, _):
            // HabitStore will be created separately — no-op for now
            break

        case .note(_):
            // No note payload type in EventPayload yet — no-op for now
            break

        case .unknown:
            break // Nothing to execute
        }
    }
}
