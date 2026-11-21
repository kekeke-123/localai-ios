import Foundation
import Speech
import AVFoundation
import Combine

/// 用系统「语音识别」在本地把说话转成文字（requiresOnDeviceRecognition = true，不联网）。
@MainActor
final class VoiceInput: ObservableObject {

    @Published private(set) var isRecording = false
    @Published var transcript: String = ""
    @Published var lastError: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    var isAvailable: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func start() {
        guard !isRecording else { return }
        lastError = nil
        transcript = ""

        guard let recognizer, recognizer.isAvailable else {
            lastError = "这台设备暂时用不了中文语音识别。"
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            lastError = "这个系统版本不支持纯离线中文识别。"
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .authorized:
                    self.beginRecording()
                case .denied, .restricted:
                    self.lastError = "没有语音识别权限，去 设置 → 本地智能 打开。"
                default:
                    self.lastError = "语音识别授权失败。"
                }
            }
        }
    }

    private func beginRecording() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.lastError = "没有麦克风权限，去 设置 → 本地智能 打开。"
                    return
                }
                self.startEngine()
            }
        }
    }

    private func startEngine() {
        guard let recognizer else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            try engine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil {
                        self.stop()
                    }
                }
            }
        } catch {
            lastError = "录音启动失败：\(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        guard isRecording else {
            transcript = ""
            return
        }
        isRecording = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
