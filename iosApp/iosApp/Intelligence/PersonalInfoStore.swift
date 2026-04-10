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
        name != nil && !name!.isEmpty && birthYear != nil && heightCm != nil && weightKg != nil
    }

    /// Number of fields that are still empty.
    var pendingCount: Int {
        var count = 0
        if name == nil || name!.isEmpty { count += 1 }
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
            let totalInches = cm / 2.54
            let feet = Int(totalInches) / 12
            let inches = Int(totalInches) % 12
            return "\(feet)'\(inches)\""
        }
    }

    var displayWeight: String {
        guard let kg = weightKg else { return "--" }
        switch weightUnit {
        case .kg: return "\(Int(kg)) kg"
        case .lbs: return "\(Int(kg * 2.205)) lbs"
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

/// Persistent store for personal info.
class PersonalInfoStore: ObservableObject {
    static let shared = PersonalInfoStore()
    private let key = "personal_info"

    @Published var info: PersonalInfo

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(PersonalInfo.self, from: data) {
            info = decoded
        } else {
            info = .empty
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(data, forKey: key)
        }
        objectWillChange.send()
    }

    /// Try to pull height and weight from HealthKit if available.
    func syncFromHealthKit() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()

        // Height
        if let heightType = HKQuantityType.quantityType(forIdentifier: .height) {
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: heightType, predicate: nil, limit: 1, sortDescriptors: [sort]) { [weak self] _, results, _ in
                if let sample = results?.first as? HKQuantitySample {
                    let cm = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
                    DispatchQueue.main.async {
                        if self?.info.heightCm == nil {
                            self?.info.heightCm = cm
                            self?.save()
                        }
                    }
                }
            }
            store.execute(query)
        }

        // Weight
        if let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: weightType, predicate: nil, limit: 1, sortDescriptors: [sort]) { [weak self] _, results, _ in
                if let sample = results?.first as? HKQuantitySample {
                    let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    DispatchQueue.main.async {
                        if self?.info.weightKg == nil {
                            self?.info.weightKg = kg
                            self?.save()
                        }
                    }
                }
            }
            store.execute(query)
        }
    }
}
