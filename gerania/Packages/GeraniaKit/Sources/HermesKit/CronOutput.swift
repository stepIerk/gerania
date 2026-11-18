import Foundation

/// One result file Hermes wrote under `~/.hermes/cron/output/<job-id>/`.
public struct CronOutput: Sendable, Equatable, Identifiable {
    public let jobID: String
    public let url: URL
    public let modifiedAt: Date

    public var id: String {
        url.path
    }

    public var fileName: String {
        url.lastPathComponent
    }

    public init(jobID: String, url: URL, modifiedAt: Date) {
        self.jobID = jobID
        self.url = url
        self.modifiedAt = modifiedAt
    }
}

/// Read-only view of the files the scheduler delivers.
public enum CronOutputStore {
    /// Newest `.md` results across every job, newest first.
    public static func recent(in cronDirectory: URL, limit: Int = 20) -> [CronOutput] {
        let outputDirectory = cronDirectory.appendingPathComponent("output", isDirectory: true)
        let manager = FileManager.default
        guard let jobDirectories = try? manager.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var results: [CronOutput] = []
        for jobDirectory in jobDirectories {
            let isDirectory = (try? jobDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }
            let files = (try? manager.contentsOfDirectory(
                at: jobDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for file in files where file.pathExtension.lowercased() == "md" {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                results.append(CronOutput(
                    jobID: jobDirectory.lastPathComponent,
                    url: file,
                    modifiedAt: modified
                ))
            }
        }
        let sorted = results.sorted { $0.modifiedAt > $1.modifiedAt }
        return Array(sorted.prefix(limit))
    }

    public static func read(_ output: CronOutput) throws -> String {
        do {
            return try String(contentsOf: output.url, encoding: .utf8)
        } catch {
            throw CronError.unreadable(output.fileName)
        }
    }
}
