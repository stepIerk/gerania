import Foundation
import HermesKit
import Testing

@Suite("Статус управления компьютером")
struct ComputerUseStatusTests {
    private let readyReport = """
    {
      "checks": [
        { "name": "binary_version", "status": "pass", "message": "cua-driver 0.21.0" },
        {
          "name": "bundle_identity",
          "status": "pass",
          "message": "Bundle is com.trycua.driver.",
          "data": { "bundle_identifier": "com.trycua.driver" }
        },
        { "name": "tcc_accessibility", "status": "pass", "message": "Accessibility is granted." },
        { "name": "tcc_screen_recording", "status": "pass", "message": "Screen Recording is granted." },
        {
          "name": "screen_capture_capability",
          "status": "skip",
          "message": "Not probed by health_report."
        }
      ],
      "driver_version": "0.21.0",
      "overall": "ok",
      "platform": "darwin"
    }
    """

    @Test("Готовый драйвер читается целиком")
    func readyDriver() throws {
        let status = try ComputerUseStatus.parse(Data(readyReport.utf8))

        #expect(status.isReady)
        #expect(status.isInstalled)
        #expect(status.platform == "darwin")
        #expect(status.driverVersion == "0.21.0")
        #expect(status.driverLabel == "cua-driver 0.21.0")
        #expect(status.accessibility == true)
        #expect(status.screenRecording == true)
        #expect(status.bundleIdentifier == "com.trycua.driver")
        #expect(status.missingPermissions.isEmpty)
        #expect(status.summary.contains("Готово"))
    }

    @Test("Нет записи экрана — это видно и объяснено")
    func missingScreenRecording() throws {
        let report = readyReport
            .replacingOccurrences(of: "\"overall\": \"ok\"", with: "\"overall\": \"degraded\"")
            .replacingOccurrences(
                of: "\"name\": \"tcc_screen_recording\", \"status\": \"pass\"",
                with: "\"name\": \"tcc_screen_recording\", \"status\": \"fail\""
            )

        let status = try ComputerUseStatus.parse(Data(report.utf8))

        #expect(!status.isReady)
        #expect(status.isInstalled)
        #expect(status.accessibility == true)
        #expect(status.screenRecording == false)
        #expect(status.missingPermissions == ["Запись экрана"])
        #expect(status.summary.contains("Запись экрана"))
    }

    @Test("Пропущенная проверка не выдаёт себя за разрешение")
    func skippedPermissionIsUnknown() throws {
        let report = readyReport.replacingOccurrences(
            of: "\"name\": \"tcc_accessibility\", \"status\": \"pass\"",
            with: "\"name\": \"tcc_accessibility\", \"status\": \"skip\""
        )

        let status = try ComputerUseStatus.parse(Data(report.utf8))

        #expect(status.accessibility == nil)
        #expect(status.missingPermissions.isEmpty)
    }

    @Test("Проблемный отчёт остаётся читаемым")
    func degradedReport() throws {
        let report = """
        {
          "checks": [],
          "overall": "failed",
          "platform": "darwin",
          "error": "cua-driver is not reachable"
        }
        """

        let status = try ComputerUseStatus.parse(Data(report.utf8))

        #expect(!status.isReady)
        #expect(!status.isInstalled)
        #expect(status.driverLabel == "не установлен")
        #expect(status.summary == "cua-driver не установлен")
    }

    @Test("Битый JSON не проходит как готовый драйвер")
    func brokenReport() {
        #expect(throws: (any Error).self) {
            try ComputerUseStatus.parse(Data("{ not json".utf8))
        }
    }

    @Test("Ошибка запуска объясняется человеку")
    func failedStatus() {
        let status = ComputerUseStatus.failed("Не найден hermes")

        #expect(!status.isReady)
        #expect(status.summary == "Не найден hermes")
    }
}
