import Foundation
import GeraniaCore
import VoiceKit

/// The Picovoice key, the wake files and the recording of the owner voice.
public extension AppModel {
    /// Saves the AccessKey in the Keychain and restarts the ears with it.
    func saveWakeKey(_ key: String) async -> String {
        do {
            try WakeEngine.saveAccessKey(key)
        } catch {
            return error.localizedDescription
        }
        await restartEars()
        return key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Ключ удалён: «Гера» снова ловит Whisper."
            : "Ключ сохранён в Связке ключей."
    }

    /// Copies a `.ppn` or `.pv` file the person picked and restarts the ears.
    func installWakeFile(from source: URL, as destination: URL) async -> String {
        do {
            try WakeEngine.install(source, as: destination)
        } catch {
            return "Не удалось скопировать файл: \(error.localizedDescription)"
        }
        await restartEars()
        return "Файл «\(source.lastPathComponent)» установлен."
    }

    /// Records about 15 seconds of the owner's speech into an Eagle profile.
    ///
    /// The running ears are suspended meanwhile: «Гера» in the sample speech
    /// must not wake anything. The new profile replaces the old one only when
    /// the recording finished.
    func recordOwnerVoice() async {
        guard voiceInput.enrollment == nil else { return }
        guard WakeEngine.accessKey() != nil else {
            voiceInput.enrollMessage = "Сначала сохраните ключ Picovoice."
            return
        }
        let profile = WakeEngine.ownerProfileURL()
        let draft = profile.deletingLastPathComponent().appendingPathComponent("owner.recording")
        try? FileManager.default.createDirectory(
            at: profile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let enrollment = VoiceEnrollment(configuration: VoiceBridge.Configuration(
            pythonPath: settings.pythonPath,
            scriptOverridePath: settings.earsScriptOverridePath,
            environment: earsEnvironment()
        ))
        voiceInput.enrollment = enrollment
        voiceInput.enrollPercent = 0
        voiceInput.enrollMessage = "Говорите обычным голосом, как с Герой: расскажите, что делали сегодня."
        let earsWereRunning = voiceBridge != nil && isVoiceRunning && !voiceIsSuspended
        if earsWereRunning {
            await voiceBridge?.send(.suspend)
        }
        var finished = false
        for await event in enrollment.run(outputPath: draft.path) {
            switch event {
            case let .enrollProgress(percent):
                voiceInput.enrollPercent = percent
            case .enrollDone:
                finished = true
            case let .error(message):
                voiceInput.enrollMessage = message
            default:
                break
            }
        }
        voiceInput.enrollment = nil
        voiceInput.enrollPercent = nil
        if finished {
            finished = (try? replaceOwnerProfile(at: profile, with: draft)) != nil
        }
        if earsWereRunning {
            await voiceBridge?.send(.resume)
        }
        guard finished else {
            if voiceInput.enrollMessage?.hasPrefix("Говорите") == true {
                voiceInput.enrollMessage = "Запись прервана."
            }
            return
        }
        voiceInput.settings.ownerGateEnabled = true
        voiceInput.enrollMessage = "Голос записан. Гера будет слушать только вас."
        Log.voice.notice("owner voice recorded")
        await restartEars()
    }

    func cancelOwnerVoiceRecording() {
        voiceInput.enrollment?.cancel()
    }

    func forgetOwnerVoice() async {
        try? FileManager.default.removeItem(at: WakeEngine.ownerProfileURL())
        voiceInput.enrollMessage = "Запись голоса удалена."
        await restartEars()
    }

    private func replaceOwnerProfile(at profile: URL, with draft: URL) throws {
        let files = FileManager.default
        if files.fileExists(atPath: profile.path) {
            try files.removeItem(at: profile)
        }
        try files.moveItem(at: draft, to: profile)
    }
}
