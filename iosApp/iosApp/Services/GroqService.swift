import Foundation

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
