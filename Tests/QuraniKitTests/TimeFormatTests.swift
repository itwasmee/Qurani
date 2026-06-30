import Testing
@testable import QuraniKit

@Test func timeLabel() {
    // Below an hour → m:ss (no zero-padded minutes).
    #expect(TimeFormat.label(5) == "0:05")
    #expect(TimeFormat.label(92) == "1:32")
    #expect(TimeFormat.label(760) == "12:40")
    #expect(TimeFormat.label(3599) == "59:59")
    // At/past an hour → h:mm:ss (zero-padded minutes + seconds).
    #expect(TimeFormat.label(3600) == "1:00:00")
    #expect(TimeFormat.label(3725) == "1:02:05")
    #expect(TimeFormat.label(5525) == "1:32:05")
    // Invalid / edge input clamps to "0:00".
    #expect(TimeFormat.label(0) == "0:00")
    #expect(TimeFormat.label(-1) == "0:00")
    #expect(TimeFormat.label(.infinity) == "0:00")
}
