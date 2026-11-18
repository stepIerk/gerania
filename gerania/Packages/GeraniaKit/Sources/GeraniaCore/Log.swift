import Foundation
import os

/// Central `os.Logger` factory. Never use `print` in library code.
public enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.yourname.Gerania"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let hermes = Logger(subsystem: subsystem, category: "hermes")
    public static let voice = Logger(subsystem: subsystem, category: "voice")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
    public static let speech = Logger(subsystem: subsystem, category: "speech")
}
