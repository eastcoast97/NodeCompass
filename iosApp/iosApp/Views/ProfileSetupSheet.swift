import SwiftUI

/// Sheet for collecting personal info (name, birth year, height, weight).
/// Shown when user taps the notification bell on the dashboard.
struct ProfileSetupSheet: View {
    @ObservedObject var store = PersonalInfoStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var birthYear: String = ""
    @State private var heightValue: String = ""       // cm when in cm mode
    @State private var heightFeet: String = ""        // ft when in ft/in mode
    @State private var heightInches: String = ""      // in when in ft/in mode
    @State private var weightValue: String = ""
    @State private var heightUnit: PersonalInfo.HeightUnit = .cm
    @State private var weightUnit: PersonalInfo.WeightUnit = .kg
    @State private var didSyncHealth = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(NC.teal.opacity(0.1))
                                .frame(width: 72, height: 72)
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(NC.teal)
                        }
                        Text("Complete Your Profile")
                            .font(.title3.bold())
                        Text("Helps us personalize your Life Score and insights")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Form
                    VStack(spacing: 0) {
                        // Name
                        fieldRow(icon: "person.fill", color: NC.teal, label: "Name") {
                            TextField("Your name", text: $name)
                                .textContentType(.givenName)
                        }

                        Divider().padding(.leading, NC.dividerIndent)

                        // Birth Year
                        fieldRow(icon: "calendar", color: .blue, label: "Birth Year") {
                            TextField("e.g. 1997", text: $birthYear)
                                .keyboardType(.numberPad)
                        }

                        Divider().padding(.leading, NC.dividerIndent)

                        // Height — split into separate feet/inches fields when imperial
                        // to avoid the unparseable "5'10\"" placeholder that the old
                        // single TextField couldn't actually parse.
                        fieldRow(icon: "ruler.fill", color: .orange, label: "Height") {
                            HStack(spacing: 8) {
                                if heightUnit == .cm {
                                    TextField("170", text: $heightValue)
                                        .keyboardType(.numberPad)
                                        .frame(maxWidth: 70)
                                    Text("cm")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    TextField("5", text: $heightFeet)
                                        .keyboardType(.numberPad)
                                        .frame(maxWidth: 36)
                                    Text("ft")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("10", text: $heightInches)
                                        .keyboardType(.numberPad)
                                        .frame(maxWidth: 36)
                                    Text("in")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $heightUnit) {
                                    ForEach(PersonalInfo.HeightUnit.allCases, id: \.self) { u in
                                        Text(u.rawValue).tag(u)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 100)
                                .onChange(of: heightUnit) { _, _ in convertHeightFields() }
                            }
                        }

                        Divider().padding(.leading, NC.dividerIndent)

                        // Weight
                        fieldRow(icon: "scalemass.fill", color: .pink, label: "Weight") {
                            HStack(spacing: 8) {
                                TextField(weightUnit == .kg ? "70" : "154", text: $weightValue)
                                    .keyboardType(.decimalPad)
                                    .frame(maxWidth: 80)
                                Picker("", selection: $weightUnit) {
                                    ForEach(PersonalInfo.WeightUnit.allCases, id: \.self) { u in
                                        Text(u.rawValue).tag(u)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 100)
                            }
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))

                    // HealthKit sync hint
                    if !didSyncHealth {
                        Button {
                            store.syncFromHealthKit()
                            didSyncHealth = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.pink)
                                Text("Auto-fill from Apple Health")
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(.pink.opacity(0.5))
                            }
                            .padding(.horizontal, NC.hPad)
                            .padding(.vertical, NC.vPad)
                            .background(.pink.opacity(0.06), in: RoundedRectangle(cornerRadius: NC.cardRadius))
                        }
                    }

                    // Save button
                    Button { saveAndDismiss() } label: {
                        Text("Save")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(NC.teal, in: RoundedRectangle(cornerRadius: NC.cardRadius))
                    }

                    // Skip
                    Button { dismiss() } label: {
                        Text("I'll do this later")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, NC.hPad)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Your Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { saveAndDismiss() }
                }
            }
            .onAppear { loadExisting() }
            .onChange(of: store.info.heightCm) { _, newValue in
                // Auto-fill height from HealthKit sync if user hasn't typed anything yet
                if let cm = newValue, heightValue.isEmpty && heightFeet.isEmpty && heightInches.isEmpty {
                    if heightUnit == .cm {
                        heightValue = "\(Int(cm))"
                    } else {
                        let totalInches = cm / Config.Units.cmPerInch
                        heightFeet = "\(Int(totalInches) / 12)"
                        heightInches = "\(Int(totalInches.rounded()) % 12)"
                    }
                }
            }
            .onChange(of: store.info.weightKg) { _, newValue in
                // Auto-fill weight from HealthKit sync if user hasn't typed anything yet
                if let kg = newValue, weightValue.isEmpty {
                    if weightUnit == .kg {
                        weightValue = "\(Int(kg))"
                    } else {
                        weightValue = "\(Int((kg * Config.Units.lbsPerKg).rounded()))"
                    }
                }
            }
            .alert("Invalid input", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Helpers

    private func fieldRow<Content: View>(icon: String, color: Color, label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: NC.iconSize, height: NC.iconSize)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                content()
                    .font(.subheadline)
            }

            Spacer()
        }
        .padding(.horizontal, NC.hPad)
        .padding(.vertical, NC.vPad)
    }

    private func loadExisting() {
        let info = store.info
        name = info.name ?? ""
        if let y = info.birthYear { birthYear = "\(y)" }
        heightUnit = info.heightUnit
        weightUnit = info.weightUnit
        if let h = info.heightCm {
            if heightUnit == .cm {
                heightValue = "\(Int(h))"
            } else {
                let totalInches = h / Config.Units.cmPerInch
                heightFeet = "\(Int(totalInches) / 12)"
                heightInches = "\(Int(totalInches.rounded()) % 12)"
            }
        }
        if let w = info.weightKg {
            if weightUnit == .kg {
                weightValue = "\(Int(w))"
            } else {
                weightValue = "\(Int((w * Config.Units.lbsPerKg).rounded()))"
            }
        }
    }

    /// Convert between cm and ft/in fields when the user toggles the unit picker,
    /// so the displayed value stays in sync.
    private func convertHeightFields() {
        if heightUnit == .cm {
            // Came from ft/in → compute cm from ft/in fields
            let ft = Double(heightFeet) ?? 0
            let inches = Double(heightInches) ?? 0
            let totalInches = ft * 12 + inches
            if totalInches > 0 {
                heightValue = "\(Int((totalInches * Config.Units.cmPerInch).rounded()))"
            }
        } else {
            // Came from cm → compute ft/in
            if let cm = Double(heightValue), cm > 0 {
                let totalInches = cm / Config.Units.cmPerInch
                heightFeet = "\(Int(totalInches) / 12)"
                heightInches = "\(Int(totalInches.rounded()) % 12)"
            }
        }
    }

    private func saveAndDismiss() {
        store.info.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
        if let year = Int(birthYear), year >= 1900, year <= Calendar.current.component(.year, from: Date()) {
            store.info.birthYear = year
        } else if !birthYear.isEmpty {
            errorMessage = "Birth year must be a valid 4-digit year"
            return
        }

        store.info.heightUnit = heightUnit
        store.info.weightUnit = weightUnit

        // Convert height to cm using structured fields
        if heightUnit == .cm {
            if let val = Double(heightValue), val > 0, val < 300 {
                store.info.heightCm = val
            }
        } else {
            let ft = Double(heightFeet) ?? 0
            let inches = Double(heightInches) ?? 0
            let totalInches = ft * 12 + inches
            if totalInches > 0 && totalInches < 120 {
                store.info.heightCm = totalInches * Config.Units.cmPerInch
            }
        }

        // Convert weight to kg
        if let val = Double(weightValue), val > 0, val < 1000 {
            store.info.weightKg = weightUnit == .kg ? val : val / Config.Units.lbsPerKg
        }

        store.save()
        dismiss()
    }
}
