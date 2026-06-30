public enum Theme: String, CaseIterable, Sendable { case system, sahar, noor, layl }
public enum ResolvedTheme: String, Sendable { case sahar, noor, layl }

public extension Theme {
    func resolved(systemIsDark: Bool) -> ResolvedTheme {
        switch self {
        case .system: return systemIsDark ? .noor : .sahar
        case .sahar:  return .sahar
        case .noor:   return .noor
        case .layl:   return .layl
        }
    }
}
