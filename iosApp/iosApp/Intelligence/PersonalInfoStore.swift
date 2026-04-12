import Foundation
import HealthKit

/// User-entered personal info (name, age, height, weight).
/// Separate from the learned UserProfile — this is explicit user input.
struct PersonalInfo: Codable {
    var name: String?
    var birthYear: Int?
    var heightCm: Double?
    var weightKg: Double?
    var heightUnit: HeightUnit
    var weightUnit: WeightUnit

    var isComplete: Bool {
        name != nil && !(name?.isEmpty ?? true) && birthYear != nil && heightCm != nil && weightKg != nil
    }

    /// Number of fields that are still empty.
    var pendingCount: Int {
        var count = 0
        if name == nil || (name?.isEmpty ?? true) { count += 1 }
        if birthYear == nil { count += 1 }
        if heightCm == nil { count += 1 }
        if weightKg == nil { count += 1 }
        return count
    }

    var age: Int? {
        guard let year = birthYear else { return nil }
        return Calendar.current.component(.year, from: Date()) - year
    }

    var displayHeight: String {
        guard let cm = heightCm else { return "--" }
        switch heightUnit {
        case .cm: return "\(Int(cm)) cm"
        case .ftIn:
            let totalInches = cm / Config.Units.cmPerInch
            let feet = Int(totalInches) / 12
            let inches = Int(totalInches.rounded()) % 12
            return "\(feet)'\(inches)\""
        }
    }

    var displayWeight: String {
        guard let kg = weightKg else { return "--" }
        switch weightUnit {
        case .kg: return "\(Int(kg)) kg"
        case .lbs: return "\(Int((kg * Config.Units.lbsPerKg).rounded())) lbs"
        }
    }

    enum HeightUnit: String, Codable, CaseIterable {
        case cm = "cm"
        case ftIn = "ft/in"
    }

    enum WeightUnit: String, Codable, CaseIterable {
        case kg = "kg"
        case lbs = "lbs"
    }

    static var empty: PersonalInfo {
        PersonalInfo(name: nil, birthYear: nil, heightCm: nil, weightKg: nil,
                     heightUnit: .cm, weightUnit: .kg)
    }
}

/// Persistent store for personal info. @MainActor because the backing store
/// is @Published for SwiftUI binding. HealthKit queries use an internal
/// serial sync flag to prevent duplicate writes.
@MainActor
class PersonalInfoStore: ObservableObject {
    static let shared = PersonalInfoStore()
    private let key = "personal_info"

    @Published var info: PersonalInfo

    /// Guard against concurrent syncFromHealthKit calls.
    private var isSyncingFromHealthKit: Bool = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(PersonalInfo.self, from: data) {
            info = decoded
        } else {
            info = .empty
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(info)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("[PersonalInfoStore] Save failed: \(error)")
        }
    }

    /// Try to pull height and weight from HealthKit if available.
    /// Reentrancy-safe: a second call while the first is in flight is a no-op.
    func syncFromHealthKit() {
        guard !isSyncingFromHealthKit else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        isSyncingFromHealthKit = true

        let store = HKHealthStore()
        let group = DispatchGroup()

        var fetchedHeightCm: Double?
        var fetchedWeightKg: Double?

        // Height
        if let heightType = HKQuantityType.quantityType(forIdentifier: .height) {
            group.enter()
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: heightType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, results, error in
                defer { group.leave() }
                if let error = error {
                    print("[PersonalInfoStore] Height query error: \(error)")
                    return
                }
                if let sample = results?.first as? HKQuantitySample {
                    fetchedHeightCm = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
                }
            }
            store.execute(query)
        }

        // Weight
        if let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            group.enter()
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: weightType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, results, error in
                defer { group.leave() }
                if let error = error {
                    print("[PersonalInfoStore] Weight query error: \(error)")
                    return
                }
                if let sample = results?.first as? HKQuantitySample {
                    fetchedWeightKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                }
            }
            store.execute(query)
        }

        // When both queries finish, write results on the main actor atomically
        // and release the sync lock.
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                if let cm = fetchedHeightCm, self.info.heightCm == nil {
                    self.info.heightCm = cm
                }
                if let kg = fetchedWeightKg, self.info.weightKg == nil {
                    self.info.weightKg = kg
                }
                if fetchedHeightCm != nil || fetchedWeightKg != nil {
                    self.save()
                }
                self.isSyncingFromHealthKit = false
            }
        }
    }
}
