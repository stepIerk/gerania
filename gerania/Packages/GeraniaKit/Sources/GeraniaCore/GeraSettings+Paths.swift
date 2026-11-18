import Foundation

/// Path helpers of the settings.
///
/// They live in a separate file so the settings class stays within the project's file
/// length limit.
public extension GeraSettings {
    var expandedWorkdir: String {
        Self.expandedPath(workdir)
    }

    nonisolated static func expandedPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// Mirrors `PROMPT_PREFIX` from the legacy `wake_agent.py`.
    nonisolated static func defaultVoicePromptPrefix(workdir: String) -> String {
        "[Голосовой режим] Отвечай по-русски, коротко (1–3 предложения), без markdown и "
            + "списков: ответ будет озвучен. Ничего не удаляй и не перезаписывай; новые файлы "
            + "и папки создавай только в \(workdir). Запрос: "
    }
}
