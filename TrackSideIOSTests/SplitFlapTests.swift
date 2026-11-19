import Testing
@testable import TrackSideIOS

@Suite("Split-flap drum")
struct SplitFlapTests {
    @Test("Rolls through the digits in between")
    func digits() {
        #expect(SplitFlap.steps(from: "2", to: "6") == ["3", "4", "5", "6"])
    }

    @Test("Goes round past 9 to 0, as a drum does")
    func wraps() {
        #expect(SplitFlap.steps(from: "8", to: "1") == ["9", "0", "1"])
    }

    @Test("Rolls through letters")
    func letters() {
        #expect(SplitFlap.steps(from: "W", to: "Z") == ["X", "Y", "Z"])
    }

    @Test("Never more than ten flaps")
    func capped() {
        let steps = SplitFlap.steps(from: "A", to: "Z")
        #expect(steps.count == 10)
        #expect(steps.last == "Z")
    }

    @Test("Changes straight to a character on another drum")
    func otherDrum() {
        #expect(SplitFlap.steps(from: "7", to: "W") == ["W"])
    }

    @Test("Settling ends on the tile's own character")
    func settling() {
        #expect(SplitFlap.settling(to: "4", index: 0).last == "4")
        #expect(SplitFlap.settling(to: "4", index: 0).count >= 3)
    }
}
