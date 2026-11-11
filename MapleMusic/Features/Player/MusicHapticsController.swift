import Combine
import CoreHaptics
import MediaAccessibility
import AVFoundation

@MainActor
final class MusicHapticsController: ObservableObject {
    @Published var enabled = UserDefaults.standard.bool(forKey: "music-haptics-enabled") {
        didSet { UserDefaults.standard.set(enabled, forKey: "music-haptics-enabled"); changed?() }
    }
    @Published var systemMode = UserDefaults.standard.bool(forKey: "music-haptics-system") {
        didSet { UserDefaults.standard.set(systemMode, forKey: "music-haptics-system"); changed?() }
    }
    @Published var strength = (UserDefaults.standard.object(forKey: "music-haptics-strength") as? Double) ?? 0.7 {
        didSet { UserDefaults.standard.set(strength, forKey: "music-haptics-strength"); stopPattern(); changed?() }
    }
    @Published private(set) var status = "Выключено"
    let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    var changed: (() -> Void)?
    var isInBackground = false
    private var engine: CHHapticEngine?
    private var patternPlayer: CHHapticAdvancedPatternPlayer?
    private var analysis: MusicHapticAnalysis?
    private var task: Task<Void, Never>?
    private var file: URL?
    private var token = UUID()
    private var segmentStart: Double?
    private var startedAt: TimeInterval = 0
    private var segmentEnd: Double = 0
    private var observer: NSObjectProtocol?

    init() {
        if #available(iOS 18.0, *) {
            observer = NotificationCenter.default.addObserver(forName: MAMusicHapticsManager.activeStatusDidChangeNotification,
                object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.changed?() }
                }
        }
    }

    deinit { task?.cancel(); if let observer { NotificationCenter.default.removeObserver(observer) } }

    var publishesISRC: Bool {
        guard enabled else { return false }
        if systemMode { return true }
        if #available(iOS 18.0, *) { return isInBackground && MAMusicHapticsManager.shared.isActive }
        return false
    }

    func prepare(file url: URL) {
        guard enabled, !systemMode, supported else { return }
        guard url.isFileURL else { status = "Для локального расчёта нужен загруженный аудиофайл"; return }
        guard file != url else { return }
        reset()
        file = url
        let ticket = token
        status = "Рассчитываем хаптики…"
        task = Task { [weak self] in
            do {
                let result = try await MusicHapticAnalyzer.shared.analyze(url)
                guard let self, !Task.isCancelled, self.token == ticket else { return }
                self.analysis = result
                self.status = "Локальные хаптики готовы"
            } catch is CancellationError { }
            catch { if let self, self.token == ticket { self.status = "Не удалось рассчитать: \(error.localizedDescription)"; self.file = nil } }
        }
    }

    func reset() {
        task?.cancel(); task = nil; token = UUID(); file = nil; analysis = nil
        stopPattern()
        status = enabled ? "Ожидание аудио" : "Выключено"
    }

    func stopPattern() {
        try? patternPlayer?.stop(atTime: CHHapticTimeImmediate)
        patternPlayer = nil; segmentStart = nil
    }

    func tick(time: Double, playing: Bool, isrc: String?) {
        guard enabled else { stopPattern(); status = "Выключено"; return }
        if publishesISRC {
            stopPattern()
            if #available(iOS 18.0, *) {
                status = !MAMusicHapticsManager.shared.isActive ? "Включите Music Haptics в универсальном доступе iOS"
                    : (isrc == nil ? "Источник не передал ISRC этого трека" : "Системный режим: доступность дорожки определяет iOS")
            } else { status = "Для системного режима нужна iOS 18" }
            return
        }
        if isInBackground { stopPattern(); return }
        guard supported else { status = "Устройство не поддерживает Core Haptics"; return }
        guard playing, time.isFinite, let analysis, !analysis.frames.isEmpty else { stopPattern(); return }
        if let start = segmentStart, time >= start, time < segmentEnd - 0.12,
           let engine, abs((engine.currentTime - startedAt) - (time - start)) < 0.15 { return }
        stopPattern()
        do {
            if engine == nil {
                let value = try CHHapticEngine(audioSession: AVAudioSession.sharedInstance())
                value.playsHapticsOnly = true
                value.resetHandler = { [weak self] in Task { @MainActor in self?.engine = nil; self?.stopPattern() } }
                value.stoppedHandler = { [weak self] _ in Task { @MainActor in self?.engine = nil; self?.stopPattern() } }
                engine = value
            }
            guard let engine else { return }
            try engine.start()
            let first = max(0, Int(time / analysis.interval))
            let last = min(analysis.frames.count, first + 400)
            guard first < last else { return }
            let duration = Double(last - first) * analysis.interval
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0)
            ], relativeTime: 0, duration: duration)
            var curves: [CHHapticParameterCurve] = []
            // Small overlapping curves retain 10 ms features without oversized control-point arrays.
            for offset in stride(from: first, to: last, by: 15) {
                let end = min(offset + 16, last)
                for sharp in [false, true] {
                    var points = (offset..<end).map { index in
                        CHHapticParameterCurve.ControlPoint(relativeTime: Double(index - offset) * analysis.interval,
                            value: sharp ? analysis.frames[index].sharpness : analysis.frames[index].intensity * Float(min(max(strength, 0), 1)))
                    }
                    if points.count == 1, let point = points.first {
                        points.append(CHHapticParameterCurve.ControlPoint(relativeTime: analysis.interval, value: point.value))
                    }
                    curves.append(CHHapticParameterCurve(parameterID: sharp ? .hapticSharpnessControl : .hapticIntensityControl,
                        controlPoints: points, relativeTime: Double(offset - first) * analysis.interval))
                }
            }
            let pattern = try CHHapticPattern(events: [event], parameterCurves: curves)
            let value = try engine.makeAdvancedPlayer(with: pattern)
            patternPlayer = value
            segmentStart = time; segmentEnd = time + duration; startedAt = engine.currentTime
            try value.start(atTime: CHHapticTimeImmediate)
            status = "Локальные хаптики"
        } catch { status = "Хаптики недоступны: \(error.localizedDescription)"; stopPattern() }
    }
}
