import Darwin
import Foundation

/// Откуда запустилось приложение.
///
/// Нужно, чтобы отличить запуск человеком (показать окно) от автозапуска при
/// входе в систему (тихо поднять голос, окно не показывать).
enum LaunchOrigin {
    /// Приложение поднял launchd при входе в систему.
    ///
    /// Login-item запускает launchd, поэтому родительский процесс — первый.
    static var isLoginItem: Bool {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(
            getpid(),
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(MemoryLayout<proc_bsdinfo>.size)
        )
        guard size > 0 else { return false }
        return info.pbi_ppid == 1
    }
}
