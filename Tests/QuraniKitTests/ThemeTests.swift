import Testing
@testable import QuraniKit

@Test func systemFollowsAppearance() {
    #expect(Theme.system.resolved(systemIsDark: true) == .noor)
    #expect(Theme.system.resolved(systemIsDark: false) == .sahar)
}
@Test func explicitThemesIgnoreAppearance() {
    #expect(Theme.sahar.resolved(systemIsDark: true) == .sahar)
    #expect(Theme.noor.resolved(systemIsDark: false) == .noor)
    #expect(Theme.layl.resolved(systemIsDark: false) == .layl)
}
