import Foundation

enum CLIOutput {
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func printUsage() {
        let usage = """
        gerania-cli [--transport auto|gateway|acp|oneshot] [--session ID | --new] "текст"
        gerania-cli sessions [--transport ...] [--limit N]
        gerania-cli replay FILE.jsonl
        """
        write(usage + "\n")
    }

    static func grey(_ text: String) -> String {
        "\u{001B}[90m\(text)\u{001B}[0m"
    }

    static func write(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        try? FileHandle.standardOutput.write(contentsOf: data)
    }

    static func writeError(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        try? FileHandle.standardError.write(contentsOf: data)
    }
}
