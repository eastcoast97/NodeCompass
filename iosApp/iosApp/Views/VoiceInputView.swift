import SwiftUI
import Speech
import AVFoundation

/// Voice input sheet for quick life-tracking via speech or text.
///
/// States: idle -> listening -> processing -> success/error
/// Uses SFSpeechRecognizer for real-time transcription and VoiceInputEngine
/// for Groq-powered natural language parsing.
struct VoiceInputView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = VoiceInputViewModel()

    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Drag indicator
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)

                Spacer()

                // Status-dependent content
                switch vm.state {
                case .idle:
                    idleView
                case .listening:
                    listeningView
                case .processing:
                    processingView
                case .success(let action):
                    successView(action)
                case .error(let message):
                    errorView(message)
                }

                Spacer()

                // Quick type text field (always visible except on success)
                if !vm.state.isSuccess {
                    quickTypeField
                }

                // Permissions denied notice
                if vm.permissionDenied {
                    permissionDeniedNotice
                }
            }
            .padding(.horizontal, NC.hPad)
            .padding(.bottom, 16)
        }
        .onAppear {
            vm.requestPermissions()
        }
    }

    // MARK: - Sub-Views

    private var idleView: some View {
        VStack(spacing: 20) {
            Text("What happened?")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text("Tap the mic and tell me")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            micButton
        }
    }

    private var listeningView: some View {
        VStack(spacing: 20) {
            Text("Listening...")
                .font(.title2.bold())
                .foregroundStyle(NC.teal)

            micButton

            // Live transcription
            if !vm.transcribedText.isEmpty {
                Text(vm.transcribedText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
                    .animation(.easeInOut, value: vm.transcribedText)
            }
        }
    }

    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(NC.teal)

            Text("Understanding...")
                .font(.headline)
                .foregroundStyle(.secondary)

            if !vm.transcribedText.isEmpty {
                Text(vm.transcribedText)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }

    private func successView(_ action: VoiceAction) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))

            Text("Got it!")
                .font(.title2.bold())

            HStack(spacing: 10) {
                Image(systemName: action.icon)
                    .font(.title3)
                    .foregroundStyle(NC.teal)

                Text(action.confirmationMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(NC.hPad)
            .card()
        }
        .transition(.scale.combined(with: .opacity))
        .onAppear {
            Haptic.success()
            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                dismiss()
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Couldn't understand")
                .font(.title3.bold())

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                Haptic.light()
                vm.reset()
            } label: {
                Text("Try Again")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(NC.teal, in: Capsule())
            }
        }
        .onAppear {
            Haptic.error()
        }
    }

    private var micButton: some View {
        Button {
            Haptic.medium()
            if vm.state == .listening {
                vm.stopListening()
            } else {
                vm.startListening()
            }
        } label: {
            ZStack {
                // Pulsing ring when listening
                if vm.state == .listening {
                    Circle()
                        .fill(NC.teal.opacity(0.15))
                        .frame(width: 120, height: 120)
                        .scaleEffect(vm.pulseScale)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                            value: vm.pulseScale
                        )
                }

                Circle()
                    .fill(vm.state == .listening ? NC.teal : Color(.tertiarySystemFill))
                    .frame(width: 80, height: 80)

                Image(systemName: vm.state == .listening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(vm.state == .listening ? .white : NC.teal)
            }
        }
        .disabled(vm.permissionDenied)
        .opacity(vm.permissionDenied ? 0.4 : 1)
    }

    private var quickTypeField: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard")
                .foregroundStyle(.tertiary)

            TextField("Or type here...", text: $vm.typedText)
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .onSubmit {
                    guard !vm.typedText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    Haptic.light()
                    vm.submitTypedText()
                }

            if !vm.typedText.isEmpty {
                Button {
                    Haptic.light()
                    vm.submitTypedText()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(NC.teal)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    private var permissionDeniedNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.slash.fill")
                .foregroundStyle(.orange)
            Text("Microphone or speech access denied. Enable in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .card()
    }
}

// MARK: - View Model

@MainActor
final class VoiceInputViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case listening
        case processing
        case success(VoiceAction)
        case error(String)

        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }
    }

    @Published var state: State = .idle
    @Published var transcribedText = ""
    @Published var typedText = ""
    @Published var permissionDenied = false
    @Published var pulseScale: CGFloat = 1.0

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    /// Timer to auto-stop after silence.
    private var silenceTimer: Timer?
    private var lastTranscriptUpdate = Date()

    // MARK: - Permissions

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                if status != .authorized {
                    self?.permissionDenied = true
                }
            }
        }

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if !granted {
                    self?.permissionDenied = true
                }
            }
        }
    }

    // MARK: - Listening

    func startListening() {
        guard speechRecognizer?.isAvailable == true else {
            state = .error("Speech recognition not available")
            return
        }

        // Reset
        stopAudioEngine()
        transcribedText = ""

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .error("Audio session setup failed")
            return
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            state = .error("Could not create recognition request")
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            DispatchQueue.main.async {
                if let result {
                    self.transcribedText = result.bestTranscription.formattedString
                    self.lastTranscriptUpdate = Date()

                    if result.isFinal {
                        self.finishListening()
                    }
                }

                if let error, self.state == .listening {
                    // Ignore cancellation errors (from stopping)
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                        if self.transcribedText.isEmpty {
                            self.state = .error("Couldn't hear anything. Try again.")
                        } else {
                            self.finishListening()
                        }
                    }
                }
            }
        }

        // Start audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            state = .error("Audio engine failed to start")
            return
        }

        state = .listening
        pulseScale = 1.3 // Trigger pulse animation

        // Start silence detection timer
        lastTranscriptUpdate = Date()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                let silence = Date().timeIntervalSince(self.lastTranscriptUpdate)
                // Auto-stop after 2 seconds of silence (only if we have text)
                if silence > 2.0 && !self.transcribedText.isEmpty && self.state == .listening {
                    self.stopListening()
                }
            }
        }
    }

    func stopListening() {
        guard state == .listening else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        stopAudioEngine()

        if transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state = .idle
        } else {
            finishListening()
        }
    }

    private func finishListening() {
        guard state == .listening || state == .idle else { return }
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            state = .idle
            return
        }

        silenceTimer?.invalidate()
        silenceTimer = nil
        stopAudioEngine()

        state = .processing
        processText(text)
    }

    private func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    // MARK: - Text Processing

    func submitTypedText() {
        let text = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        transcribedText = text
        typedText = ""
        state = .processing
        processText(text)
    }

    private func processText(_ text: String) {
        Task {
            let action = await VoiceInputEngine.shared.parseText(text)

            if case .unknown = action {
                state = .error("Could not understand: \"\(text)\". Try being more specific.")
                return
            }

            // Execute the action (dispatch to stores)
            await VoiceInputEngine.shared.executeAction(action)
            state = .success(action)
        }
    }

    // MARK: - Reset

    func reset() {
        state = .idle
        transcribedText = ""
        typedText = ""
        pulseScale = 1.0
    }
}

// MARK: - Preview

#Preview {
    VoiceInputView()
        .preferredColorScheme(.dark)
}
