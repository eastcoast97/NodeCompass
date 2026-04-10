import SwiftUI

/// Sheet for collecting personal info (name, birth year, height, weight).
/// Shown when user taps the notification bell on the dashboard.
struct ProfileSetupSheet: View {
    @ObservedObject var store = PersonalInfoStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var birthYear: String = ""
    @State private var heightValue: String = ""
    @State private var weightValue: String = ""
    @State private var heightUnit: PersonalInfo.HeightUnit = .cm
    @State private var weightUnit: PersonalInfo.WeightUnit = .kg
    @State private var didSyncHealth = false

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

                        // Height
                        fieldRow(icon: "ruler.fill", color: .orange, label: "Height") {
                            HStack(spacing: 8) {
                                TextField(heightUnit == .cm ? "170" : "5'10\"", text: $heightValue)
                                    .keyboardType(.decimalPad)
                                    .frame(maxWidth: 80)
                                Picker("", selection: $heightUnit) {
                                    ForEach(PersonalInfo.HeightUnit.allCases, id: \.self) { u in
                                        Text(u.rawValue).tag(u)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 100)
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
                            // Refresh fields after a short delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                if let h = store.info.heightCm, heightValue.isEmpty {
                                    heightValue = "\(Int(h))"
                                }
                                if let w = store.info.weightKg, weightValue.isEmpty {
                                    weightValue = "\(Int(w))"
                                }
                            }
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
        if let h = info.heightCm {
            heightUnit = info.heightUnit
            if heightUnit == .cm {
                heightValue = "\(Int(h))"
            } else {
                let totalInches = h / 2.54
                heightValue = "\(Int(totalInches))"
            }
        }
        if let w = info.weightKg {
            weightUnit = info.weightUnit
            if weightUnit == .kg {
                weightValue = "\(Int(w))"
            } else {
                weightValue = "\(Int(w * 2.205))"
            }
        }
        heightUnit = info.heightUnit
        weightUnit = info.weightUnit
    }

    private func saveAndDismiss() {
        store.info.name = name.isEmpty ? nil : name
        store.info.birthYear = Int(birthYear)
        store.info.heightUnit = heightUnit
        store.info.weightUnit = weightUnit

        // Convert height to cm
        if let val = Double(heightValue) {
            store.info.heightCm = heightUnit == .cm ? val : val * 2.54
        }

        // Convert weight to kg
        if let val = Double(weightValue) {
            store.info.weightKg = weightUnit == .kg ? val : val / 2.205
        }

        store.save()
        dismiss()
    }
}
