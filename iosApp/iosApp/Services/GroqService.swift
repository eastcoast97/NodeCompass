import Foundation

/// Tracks daily Groq API token usage for display in the UI.
class GroqTokenTracker: ObservableObject {
    static let shared = GroqTokenTracker()

    private let usageKey = "groq_token_usage"
    private let dateKey = "groq_usage_date"

    /// Groq free tier: ~6,000 tokens/min, ~500,000 tokens/day (approximate for llama-3.3-70b)
    let dailyLimit: Int = 500_000

    @Published var todayTokens: Int = 0
    @Published var sessionTokens: Int = 0
    @Published var lastRequestTokens: Int = 0

    private init() {
        resetIfNewDay()
        todayTokens = UserDefaults.standard.integer(forKey: usageKey)
    }

    var todayPercentage: Double {
        min(Double(todayTokens) / Double(dailyLimit), 1.0)
    }

    var remainingTokens: Int {
        max(dailyLimit - todayTokens, 0)
    }

    var formattedUsage: String {
        let used = formatTokenCount(todayTokens)
        let limit = formatTokenCount(dailyLimit)
        return "\(used) / \(limit)"
    }

    func recordUsage(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        resetIfNewDay()
        let total = totalTokens > 0 ? totalTokens : (promptTokens + completionTokens)
        todayTokens += total
        sessionTokens += total
        lastRequestTokens = total
        UserDefaults.standard.set(todayTokens, forKey: usageKey)
    }

    func resetIfNewDay() {
        let today = Calendar.current.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: today)
        let savedDate = UserDefaults.standard.string(forKey: dateKey) ?? ""

        if savedDate != todayStr {
            UserDefaults.standard.set(0, forKey: usageKey)
            UserDefaults.standard.set(todayStr, forKey: dateKey)
            todayTokens = 0
            sessionTokens = 0
        }
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

/// Groq API client for NodeCompass.
/// Uses Llama 3.3 70B on Groq's free tier (30 RPM, 14,400 RPD).
/// Handles: receipt parsing, email classification, and merchant categorization.
class GroqService {
    static let shared = GroqService()

    private let baseURL = "https://api.groq.com/openai/v1/chat/completions"
    private let model = "llama-3.3-70b-versatile"
    private let keychain = KeychainService.shared
    private let apiKeyKey = "groq_api_key"

    private init() {}

    // MARK: - API Key Management

    var hasApiKey: Bool {
        keychain.get(key: apiKeyKey) != nil
    }

    func setApiKey(_ key: String) {
        keychain.save(key: apiKeyKey, value: key)
    }

    func removeApiKey() {
        keychain.delete(key: apiKeyKey)
    }

    func getApiKey() -> String? {
        keychain.get(key: apiKeyKey)
    }

    /// Test if an API key is valid by making a minimal request.
    /// Returns (success, errorMessage).
    func testApiKey(_ key: String) async -> (Bool, String?) {
        guard let url = URL(string: baseURL) else { return (false, "Invalid URL") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "Hi"]],
            "max_tokens": 5
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return (false, "Request build failed")
        }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            if statusCode == 200 {
                return (true, nil)
            }

            // Parse error for better messaging
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return (false, message)
            }
            return (false, "API returned status \(statusCode)")
        } catch {
            return (false, "Network error: \(error.localizedDescription)")
        }
    }

    // MARK: - Core API Call

    /// Send a prompt and return the text response.
    func generate(prompt: String, maxTokens: Int = 1024) async -> String? {
        guard let apiKey = getApiKey() else { return nil }
        guard let url = URL(string: baseURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": maxTokens,
            "temperature": 0.1,
            "response_format": ["type": "json_object"]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                if let httpResponse = response as? HTTPURLResponse {
                }
                return nil
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let choices = json?["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            let content = message?["content"] as? String

            // Track token usage
            if let usage = json?["usage"] as? [String: Any] {
                let prompt = usage["prompt_tokens"] as? Int ?? 0
                let completion = usage["completion_tokens"] as? Int ?? 0
                let total = usage["total_tokens"] as? Int ?? 0
                await MainActor.run {
                    GroqTokenTracker.shared.recordUsage(promptTokens: prompt, completionTokens: completion, totalTokens: total)
                }
            }

            return content
        } catch {
            return nil
        }
    }

    /// Send a prompt that expects plain text (not JSON), e.g., "transaction" or "promotional".
    func generateText(prompt: String, maxTokens: Int = 10) async -> String? {
        guard let apiKey = getApiKey() else { return nil }
        guard let url = URL(string: baseURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": maxTokens,
            "temperature": 0.1
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let choices = json?["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]

            // Track token usage
            if let usage = json?["usage"] as? [String: Any] {
                let prompt = usage["prompt_tokens"] as? Int ?? 0
                let completion = usage["completion_tokens"] as? Int ?? 0
                let total = usage["total_tokens"] as? Int ?? 0
                await MainActor.run {
                    GroqTokenTracker.shared.recordUsage(promptTokens: prompt, completionTokens: completion, totalTokens: total)
                }
            }

            return message?["content"] as? String
        } catch {
            return nil
        }
    }

    /// Send a prompt and parse the response as JSON.
    func generateJSON(prompt: String, maxTokens: Int = 1024) async -> Any? {
        guard let text = await generate(prompt: prompt, maxTokens: maxTokens) else { return nil }

        // Strip markdown code fences if present
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
