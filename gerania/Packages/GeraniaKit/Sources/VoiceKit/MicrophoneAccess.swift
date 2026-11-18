import AVFoundation
import Foundation

/// Access to the microphone.
///
/// The voice front-end records from a child process, but the permission is asked by the
/// application: macOS shows the request for the app and adds it to the privacy list.
public enum MicrophoneAccess {
    /// Asks the system for the microphone and returns the answer.
    @discardableResult
    public static func request() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    /// Name of the current permission state, for the log.
    public static var statusName: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "notDetermined"
        @unknown default: "unknown"
        }
    }

    /// Whether the microphone is already allowed.
    public static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Whether the user has forbidden the microphone.
    public static var isDenied: Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted: true
        default: false
        }
    }
}
