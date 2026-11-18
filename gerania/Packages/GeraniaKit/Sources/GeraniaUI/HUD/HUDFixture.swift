import Foundation

/// Markdown fixtures used by the debug stream route.
///
/// The files live in the resources of the package; the loader also looks into the
/// application bundle, because the app target copies the package folder into Resources.
public enum HUDFixture {
    /// Names of the available fixtures.
    public static let names = ["markdown", "long", "code", "table"]

    /// Text of the fixture with the given name.
    public static func text(named name: String) -> String? {
        guard let data = data(named: name) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func data(named name: String) -> Data? {
        let fileName = "\(name).md"
        for bundle in [Bundle.module, Bundle.main] {
            if let url = bundle.url(forResource: name, withExtension: "md", subdirectory: "Fixtures") {
                return try? Data(contentsOf: url)
            }
            if let url = bundle.url(forResource: fileName, withExtension: nil, subdirectory: "Fixtures") {
                return try? Data(contentsOf: url)
            }
            for path in candidateSubdirectories {
                if let url = bundle.url(
                    forResource: fileName,
                    withExtension: nil,
                    subdirectory: path
                ) {
                    return try? Data(contentsOf: url)
                }
            }
        }
        return nil
    }

    /// Paths the app target may use when it copies the package folder into Resources.
    private static let candidateSubdirectories = [
        "GeraniaKit/Sources/GeraniaUI/Resources/Fixtures",
        "Sources/GeraniaUI/Resources/Fixtures",
        "GeraniaUI/Resources/Fixtures",
    ]
}
