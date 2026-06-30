import Foundation

public struct Surah: Codable, Identifiable, Sendable, Equatable {
    public let number: Int
    public let nameAr: String
    public let translit: String
    public let nameEn: String
    public let ayahCount: Int
    public let makki: Bool
    public let juz: Int
    public var id: Int { number }
}
