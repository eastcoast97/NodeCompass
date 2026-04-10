import Foundation

/// Persists the learned UserProfile.
/// Rebuilt periodically by PatternEngine, not updated in real-time.
actor UserProfileStore {
    static let shared = UserProfileStore()

    private(set) var profile: UserProfile
    private let fileName = "user_profile.json"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        profile = .empty

        if let loaded = Self.loadFromDisk(decoder: decoder) {
            profile = loaded
        }
    }

    // MARK: - Public API

    func currentProfile() -> UserProfile {
        profile
    }

    func update(_ newProfile: UserProfile) {
        profile = newProfile
        saveToDisk()
    }

    /// Reset to empty profile (called when user clears data).
    func clearAll() {
        profile = .empty
        saveToDisk()
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    private func saveToDisk() {
        do {
            let data = try encoder.encode(profile)
            try data.write(to: fileURL, options: .atomicWrite)
        } catch {
            print("[UserProfileStore] Save failed: \(error)")
        }
    }

    private static func loadFromDisk(decoder: JSONDecoder) -> UserProfile? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("user_profile.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(UserProfile.self, from: data)
        } catch {
            print("[UserProfileStore] Load failed: \(error)")
            return nil
        }
    }
}
