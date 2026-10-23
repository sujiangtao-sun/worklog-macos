import Testing
@testable import WorkLogCore

@Suite("WorkLogCore")
struct CoreSmokeTests {
    @Test("Core module loads")
    func coreLoads() {
        #expect(WorkLogCore.version == "1.0.0")
    }
}
