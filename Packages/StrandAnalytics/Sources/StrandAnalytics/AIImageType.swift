import Foundation

/// The media type of a picture sent to a provider, read from the first bytes of its base64, so what is declared is what is sent. Pure.
public enum AIImageType {
    /// "image/jpeg" for a JPEG, "image/png" for anything else (the charts the app draws).
    public static func mime(base64: String) -> String { base64.hasPrefix("/9j/") ? "image/jpeg" : "image/png" }
}
