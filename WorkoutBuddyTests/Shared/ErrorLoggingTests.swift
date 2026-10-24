import Foundation
import Testing
@testable import WorkoutBuddy

struct ErrorLoggingTests {
    @Test func errorCodeExposesDomainAndCodeOnly() {
        let (domain, code) = ErrorLogging.errorCode(of: NSError(domain: "NSCocoaErrorDomain", code: 134030))
        #expect(domain == "NSCocoaErrorDomain" && code == 134030)
    }
}
