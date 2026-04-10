import Foundation
import Speech
import AVFoundation

/// Handles speech recognition and parses natural language into food items.
/// Supports phrases like "2 rotis, 200 grams chicken, and a glass of milk"
@MainActor
class VoiceFoodParser: ObservableObject {

    @Published var isListening = false
    @Published var transcript = ""
    @Published var parsedItems: [FoodItem] = []
    @Published var error: String?

    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))

    // MARK: - Authorization

    func requestPermission() async -> Bool {
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            error = "Speech recognition not authorized. Enable in Settings > Privacy > Speech Recognition."
            return false
        }

        let audioStatus: Bool
        if #available(iOS 17.0, *) {
            audioStatus = await AVAudioApplication.requestRecordPermission()
        } else {
            audioStatus = await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
        guard audioStatus else {
            error = "Microphone not authorized. Enable in Settings > Privacy > Microphone."
            return false
        }

        return true
    }

    // MARK: - Start Listening

    func startListening() async {
        guard await requestPermission() else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognition not available on this device"
            return
        }

        // Clean up any previous session
        cleanupAudio()

        transcript = ""
        parsedItems = []
        error = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Audio session failed: \(error.localizedDescription)"
            return
        }

        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device recognition for privacy (fall back to server if unavailable)
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.recognitionRequest = request

        // Install audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else {
            self.error = "Invalid audio format"
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.error = "Audio engine failed: \(error.localizedDescription)"
            cleanupAudio()
            return
        }

        isListening = true

        // Start recognition
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString

                    if result.isFinal {
                        self.finishRecognition()
                    }
                }

                if let error {
                    // Ignore cancellation errors (happens when we stop manually)
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                        if self.transcript.isEmpty {
                            self.error = "Could not recognize speech. Try again."
                        }
                    }
                    if self.isListening {
                        self.finishRecognition()
                    }
                }
            }
        }
    }

    // MARK: - Stop Listening

    func stopListening() {
        guard isListening else { return }
        // Signal end of audio, which triggers isFinal in the callback
        recognitionRequest?.endAudio()

        // If we have transcript text, parse it now (don't wait for isFinal)
        if !transcript.isEmpty && parsedItems.isEmpty {
            finishRecognition()
        } else {
            cleanupAudio()
            isListening = false
        }
    }

    private func finishRecognition() {
        cleanupAudio()
        isListening = false
        guard !transcript.isEmpty else { return }
        parsedItems = parseTranscript(transcript)
    }

    private func cleanupAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Natural Language Parser

    /// Parses a spoken transcript into food items.
    func parseTranscript(_ text: String) -> [FoodItem] {
        let cleaned = text.lowercased()
            .replacingOccurrences(of: ",", with: " and ")
            .replacingOccurrences(of: ".", with: "")

        let segments = cleaned
            .components(separatedBy: " and ")
            .flatMap { $0.components(separatedBy: " with ") }
            .flatMap { $0.components(separatedBy: " plus ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return segments.compactMap { parseSegment($0) }
    }

    private func parseSegment(_ segment: String) -> FoodItem? {
        var text = segment

        let wordNumbers: [(String, Double)] = [
            ("a half", 0.5), ("half a", 0.5), ("half", 0.5),
            ("a quarter", 0.25), ("quarter", 0.25),
            ("a dozen", 12), ("dozen", 12),
            ("one", 1), ("two", 2), ("three", 3), ("four", 4), ("five", 5),
            ("six", 6), ("seven", 7), ("eight", 8), ("nine", 9), ("ten", 10),
            ("a couple of", 2), ("couple of", 2), ("a couple", 2),
            ("a few", 3), ("some", 2),
        ]

        var amount: Double?
        var unit: FoodUnit?

        let unitPatterns: [(String, FoodUnit)] = [
            ("grams", .grams), ("gram", .grams), ("gms", .grams), ("gm", .grams), ("g ", .grams),
            ("ml", .ml), ("milliliters", .ml), ("millilitres", .ml),
            ("liters", .ml), ("litres", .ml), ("liter", .ml), ("litre", .ml),
            ("glass of", .ml), ("glasses of", .ml), ("cup of", .ml), ("cups of", .ml),
            ("bowl of", .grams), ("bowls of", .grams), ("plate of", .grams), ("plates of", .grams),
            ("piece of", .qty), ("pieces of", .qty), ("slice of", .qty), ("slices of", .qty),
        ]

        // Try "number + unit" pattern
        let numberPattern = #"(\d+\.?\d*)\s*"#
        for (unitStr, foodUnit) in unitPatterns {
            let regex = try? NSRegularExpression(pattern: numberPattern + NSRegularExpression.escapedPattern(for: unitStr), options: .caseInsensitive)
            if let match = regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let numRange = Range(match.range(at: 1), in: text) {
                amount = Double(text[numRange])
                unit = foodUnit
                if unitStr.contains("glass") || unitStr.contains("cup") {
                    if let a = amount { amount = a * 200 } else { amount = 200 }
                } else if unitStr.contains("bowl") {
                    if let a = amount { amount = a * 200 } else { amount = 200 }
                } else if unitStr.contains("plate") {
                    if let a = amount { amount = a * 250 } else { amount = 250 }
                } else if unitStr.contains("liter") || unitStr.contains("litre") {
                    if let a = amount { amount = a * 1000 }
                }
                if let matchRange = Range(match.range, in: text) {
                    text = text.replacingCharacters(in: matchRange, with: "").trimmingCharacters(in: .whitespaces)
                }
                break
            }
        }

        // Try container words without number: "a glass of milk"
        if amount == nil {
            for (unitStr, foodUnit) in unitPatterns where unitStr.contains("of") {
                if text.contains(unitStr) {
                    unit = foodUnit
                    if unitStr.contains("glass") || unitStr.contains("cup") { amount = 200 }
                    else if unitStr.contains("bowl") { amount = 200 }
                    else if unitStr.contains("plate") { amount = 250 }
                    else { amount = 1 }
                    text = text.replacingOccurrences(of: unitStr, with: "").trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }

        // Try leading number: "2 rotis"
        if amount == nil {
            let leadingNum = try? NSRegularExpression(pattern: #"^(\d+\.?\d*)\s+"#)
            if let match = leadingNum?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let numRange = Range(match.range(at: 1), in: text) {
                amount = Double(text[numRange])
                text = String(text[text.index(text.startIndex, offsetBy: match.range.length)...])
            }
        }

        // Try word numbers: "one banana", "a sandwich"
        if amount == nil {
            for (word, num) in wordNumbers {
                if text.hasPrefix(word + " ") {
                    amount = num
                    text = String(text.dropFirst(word.count + 1))
                    break
                } else if text == word {
                    amount = num
                    text = ""
                    break
                }
            }
        }

        // Remove articles
        text = text.replacingOccurrences(of: "^(a |an |the )", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        guard !text.isEmpty else { return nil }

        let detectedUnit = unit ?? NutritionDatabase.detectUnit(for: text)
        let finalAmount = amount ?? detectedUnit.defaultAmount
        let nutrition = NutritionDatabase.estimate(name: text, amount: finalAmount, unit: detectedUnit)

        return FoodItem(
            name: text.capitalized,
            amount: finalAmount,
            unit: detectedUnit,
            caloriesEstimate: nutrition?.calories,
            macros: nutrition?.macros,
            isHomemade: false
        )
    }
}
