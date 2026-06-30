import Foundation

/// A user-supplied local recitation file the library has identified. `bookmark` is a
/// security-scoped bookmark to the file on disk; resolving it back to a playable URL is the
/// app target's job (a later task), so the engine is handed the already-resolved URL alongside.
/// `confidence` is the library's certainty (0…1) in the reciter/surah identification.
public struct LocalTrack: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let bookmark: Data
    public let reciterName: String
    public let surahNumber: Int
    public let confidence: Double
    public let durationMs: Int?

    public init(id: UUID = UUID(), bookmark: Data, reciterName: String, surahNumber: Int,
                confidence: Double, durationMs: Int? = nil) {
        self.id = id
        self.bookmark = bookmark
        self.reciterName = reciterName
        self.surahNumber = surahNumber
        self.confidence = confidence
        self.durationMs = durationMs
    }
}
