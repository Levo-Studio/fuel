import Testing

// MARK: - Suite

/// The suite exists so the test target has a target to compile and
/// `xcodebuild test` has something to run. The real tests live beside the
/// nutrition core, which is where the behaviour that can go wrong is.
@Suite("Fuel")
struct FuelTests {

    @Test("the test target builds and runs")
    func targetRuns() {
        #expect(Bool(true))
    }
}
