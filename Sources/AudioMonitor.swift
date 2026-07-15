import AVFoundation
import Observation
import OSLog

@MainActor
@Observable
final class AudioMonitor {
    var isMonitoring = false
    var volume: Float = 1.0 {
        didSet { bridge?.setVolume(volume) }
    }

    @ObservationIgnored
    private var bridge: HALAudioBridge?
    @ObservationIgnored
    private var debugTask: Task<Void, Never>?

    init() {
        guard CommandLine.arguments.contains("--monitor") else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.start()
        }
    }

    func toggle() {
        isMonitoring ? stop() : start()
    }

    func start() {
        guard !isMonitoring else { return }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginMonitoring()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.beginMonitoring()
                    }
                }
            }
        default:
            break
        }
    }

    func stop() {
        debugTask?.cancel()
        debugTask = nil
        bridge?.stop()
        bridge = nil
        isMonitoring = false
    }

    private func beginMonitoring() {
        let bridge = HALAudioBridge()

        do {
            try bridge.start(volume: volume)
            self.bridge = bridge
            isMonitoring = true
            if let diagnostics = bridge.diagnostics {
                Logger(subsystem: "com.return.monitor", category: "latency").info(
                    "[DEBUG-HAL-7C31] started input=\(diagnostics.inputDeviceName, privacy: .public) output=\(diagnostics.outputDeviceName, privacy: .public) inputFrames=\(diagnostics.inputBufferFrames) outputFrames=\(diagnostics.outputBufferFrames) targetFrames=\(diagnostics.bridgeTargetFrames) sampleRate=\(diagnostics.sampleRate)"
                )
            }
            debugTask = Task { @MainActor [weak self, weak bridge] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, let bridge, self.bridge === bridge else { return }
                    let stats = bridge.runtimeStats()
                    let diagnostics = bridge.diagnostics
                    let text = "[DEBUG-HAL-7C31] input=\(diagnostics?.inputDeviceName ?? "?") output=\(diagnostics?.outputDeviceName ?? "?") inputFrames=\(diagnostics?.inputBufferFrames ?? 0) outputFrames=\(diagnostics?.outputBufferFrames ?? 0) target=\(diagnostics?.bridgeTargetFrames ?? 0) fill=\(stats.fill) underflows=\(stats.underflows) overflows=\(stats.overflows) shortened=\(stats.shortened) stretched=\(stats.stretched) writeCalls=\(stats.writeCalls) writtenFrames=\(stats.writtenFrames) renderCalls=\(stats.renderCalls) renderedFrames=\(stats.renderedFrames) maximumWrite=\(stats.maximumWrite) maximumRender=\(stats.maximumRender)\n"
                    try? text.write(toFile: "/private/tmp/Return-HAL-7C31.txt", atomically: true, encoding: .utf8)
                }
            }
        } catch {
            Logger(subsystem: "com.return.monitor", category: "latency").error(
                "[DEBUG-HAL-7C31] start failed: \(error.localizedDescription, privacy: .public)"
            )
            bridge.stop()
            isMonitoring = false
        }
    }
}
