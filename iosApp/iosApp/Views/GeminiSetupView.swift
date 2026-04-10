import SwiftUI

/// Guided onboarding to get the user's free Groq API key.
/// Shows as a sheet when AI features aren't configured.
struct GeminiSetupView: View {
    @StateObject private var categorizer = SmartCategorizer.shared
    @Binding var isPresented: Bool
    @State private var currentStep = 0
    @State private var apiKeyInput = ""
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showSuccess {
                    successView
                } else {
                    // Step indicator
                    stepIndicator
                        .padding(.top, 16)
                        .padding(.bottom, 24)

                    // Step content
                    TabView(selection: $currentStep) {
                        step1WhyView.tag(0)
                        step2GetKeyView.tag(1)
                        step3PasteKeyView.tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut, value: currentStep)

                    Spacer()

                    // Bottom buttons
                    bottomButtons
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        isPresented = false
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { step in
                Capsule()
                    .fill(step <= currentStep ? NC.teal : Color(.systemGray4))
                    .frame(width: step == currentStep ? 24 : 8, height: 8)
                    .animation(.spring(), value: currentStep)
            }
        }
    }

    // MARK: - Step 1: Why

    private var step1WhyView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 52))
                    .foregroundStyle(NC.teal)
                    .padding(.top, 20)

                Text("Unlock Smart Features")
                    .font(.title2.bold())

                Text("NodeCompass uses AI to automatically understand your receipts, categorize spending, and surface insights — completely free.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 14) {
                    featureRow(icon: "doc.text.magnifyingglass", color: .blue,
                               title: "Receipt Parsing",
                               detail: "Reads email receipts and extracts items, amounts, merchants")
                    featureRow(icon: "tag.fill", color: .purple,
                               title: "Smart Categorization",
                               detail: "Auto-categorizes every transaction accurately")
                    featureRow(icon: "envelope.badge.shield.half.filled.fill", color: .orange,
                               title: "Spam Filtering",
                               detail: "Distinguishes real receipts from promotional emails")
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
                .padding(.horizontal, 20)

                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(NC.teal)
                    Text("Only merchant names are sent — never your balances or personal info")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Step 2: Get Key

    private var step2GetKeyView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "key.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .padding(.top, 20)

                Text("Get Your Free Groq Key")
                    .font(.title2.bold())

                Text("It takes 30 seconds. No credit card needed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 16) {
                    instructionRow(number: "1", text: "Tap the button below to open Groq Console")
                    instructionRow(number: "2", text: "Sign up free with Google or email")
                    instructionRow(number: "3", text: "Go to API Keys → Create API Key")
                    instructionRow(number: "4", text: "Copy the key and come back here")
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
                .padding(.horizontal, 20)

                Button {
                    if let url = URL(string: "https://console.groq.com/keys") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "safari.fill")
                        Text("Open Groq Console")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [Color.blue, Color.blue.opacity(0.8)],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
                .padding(.horizontal, 20)

                Text("Free tier: 14,400 requests/day — more than enough")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Step 3: Paste Key

    private var step3PasteKeyView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(NC.teal)
                    .padding(.top, 20)

                Text("Paste Your Key")
                    .font(.title2.bold())

                Text("Paste the API key you copied from Groq Console.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    HStack {
                        TextField("gsk_...", text: $apiKeyInput)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Button {
                            if let clipboard = UIPasteboard.general.string {
                                apiKeyInput = clipboard
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.title3)
                                .foregroundStyle(NC.teal)
                        }
                    }
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(validationError != nil ? Color.red.opacity(0.5) : Color(.systemGray4), lineWidth: 1)
                    )

                    if let error = validationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)

                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                    Text("Stored securely in iOS Keychain — never leaves your device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(NC.income)

            Text("You're All Set!")
                .font(.title.bold())

            Text("NodeCompass will now automatically parse receipts, categorize transactions, and surface smart insights.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                isPresented = false
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(NC.teal, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        HStack {
            if currentStep > 0 {
                Button {
                    withAnimation { currentStep -= 1 }
                } label: {
                    Text("Back")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            }

            Spacer()

            if currentStep < 2 {
                Button {
                    withAnimation { currentStep += 1 }
                } label: {
                    Text("Next")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(NC.teal, in: Capsule())
                }
            } else {
                Button {
                    validateAndSave()
                } label: {
                    HStack(spacing: 6) {
                        if isValidating {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isValidating ? "Validating..." : "Activate")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(
                        apiKeyInput.isEmpty ? Color.gray : NC.teal,
                        in: Capsule()
                    )
                }
                .disabled(apiKeyInput.isEmpty || isValidating)
            }
        }
    }

    // MARK: - Helpers

    private func featureRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(NC.teal, in: Circle())
            Text(text)
                .font(.subheadline)
        }
    }

    private func validateAndSave() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        // Basic format check
        guard key.hasPrefix("gsk_") else {
            validationError = "Groq keys start with \"gsk_\". Make sure you copied the right key."
            return
        }

        isValidating = true
        validationError = nil

        // Test the key with a simple API call
        Task {
            let (success, errorMsg) = await GroqService.shared.testApiKey(key)
            await MainActor.run {
                isValidating = false
                if success {
                    categorizer.setApiKey(key)
                    withAnimation { showSuccess = true }
                } else if let msg = errorMsg, msg.lowercased().contains("quota") {
                    // Quota error means key is valid — just rate limited from test attempts
                    categorizer.setApiKey(key)
                    withAnimation { showSuccess = true }
                } else {
                    validationError = errorMsg ?? "Key validation failed. Try again."
                }
            }
        }
    }
}
