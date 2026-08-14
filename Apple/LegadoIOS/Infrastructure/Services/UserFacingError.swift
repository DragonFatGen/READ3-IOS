import Foundation

enum UserFacingError {
    static func message(for error: Error, fallback: String) -> String {
        if error is CancellationError { return "" }
#if DEBUG
        let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? fallback : detail
#else
        return fallback
#endif
    }
}
