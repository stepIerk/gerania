import Foundation
import GeraniaCore

/// Where the voice front-end lives.
///
/// The app bundle keeps a flattened copy of the resources, so the script is searched in
/// several places: the override from the settings, next to the python of the venv and in
/// the resources of the application.
public enum VoicePaths {
    /// Name of the script.
    public static let scriptName = "gera_ears.py"

    /// Path of the python interpreter, `nil` when nothing suitable was found.
    public static func python(
        configured: String,
        scriptDirectory: String?,
        homeDirectory: String = NSHomeDirectory()
    ) -> String? {
        let candidates = pythonCandidates(
            configured: configured,
            scriptDirectory: scriptDirectory,
            homeDirectory: homeDirectory
        )
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Path of the script `gera_ears.py`.
    public static func script(override: String, scriptDirectory: String?) -> String? {
        var candidates: [String] = []
        if !override.isEmpty {
            candidates.append(override)
        }
        if let scriptDirectory {
            candidates.append(scriptDirectory + "/" + scriptName)
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(scriptName).path)
            candidates.append(resources.appendingPathComponent("Voice").appendingPathComponent(scriptName).path)
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Directory of the script, used to find the venv next to it.
    public static func scriptDirectory(scriptPath: String?) -> String? {
        guard let scriptPath else { return nil }
        return URL(fileURLWithPath: scriptPath).deletingLastPathComponent().path
    }

    /// Environment of the script: the PATH of the legacy front-end plus the unbuffered flag.
    public static func environment(homeDirectory: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let paths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            homeDirectory + "/.local/bin",
            environment["PATH"] ?? "",
        ]
        environment["PATH"] = paths.joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        // Скрипт лежит в ресурсах приложения — байт-код туда писать не нужно.
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        return environment
    }

    private static func pythonCandidates(
        configured: String,
        scriptDirectory: String?,
        homeDirectory: String
    ) -> [String] {
        var candidates: [String] = []
        if !configured.isEmpty {
            candidates.append(configured)
        }
        if let scriptDirectory {
            candidates.append(scriptDirectory + "/.venv/bin/python")
            candidates.append(scriptDirectory + "/.venv/bin/python3")
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(".venv/bin/python").path)
        }
        // Окружение голоса ставится вне бандла — иначе сборка ломается.
        let venv = homeDirectory + "/Library/Application Support/Gerania/voice-venv"
        candidates.append(venv + "/bin/python")
        candidates.append(venv + "/bin/python3")
        // Окружение legacy-фронтенда: в нём уже есть numpy, mlx_whisper и sounddevice.
        candidates.append(NSHomeDirectory() + "/.wake_agent_env/bin/python")
        if let found = BinaryLocator.live(homeDirectory: NSHomeDirectory())
            .locatePython(configuredPath: configured)
        {
            candidates.append(found.path)
        }
        return candidates
    }
}
