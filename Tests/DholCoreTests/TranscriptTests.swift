import Testing
@testable import DholApp

@Test func sanitizingRemovesCharactersThatWouldActOnTheTarget() {
    // Typed into a shell, a newline would run the half-dictated command and an
    // escape would be read as the start of a control sequence.
    #expect(Transcript.sanitized("echo\t hello\nworld\r\u{1B}") == "echo hello world ")
}

@Test func stablePrefixCommitsOnlyWordsTwoPassesAgreeOn() {
    #expect(Transcript.stablePrefix(previous: "hello wor", current: "hello world") == "hello ")
}

@Test func stablePrefixWaitsWhileTheFirstWordIsStillChanging() {
    #expect(Transcript.stablePrefix(previous: "hel", current: "hello").isEmpty)
}

@Test func stablePrefixStopsAtTheFirstRevisedWord() {
    #expect(
        Transcript.stablePrefix(
            previous: "open the blue folder",
            current: "open the green folder"
        ) == "open the "
    )
}

@Test func commonPrefixLengthDrivesHowMuchGetsRewritten() {
    #expect(Transcript.commonPrefixLength("hello world", "hello there") == 6)
    #expect(Transcript.commonPrefixLength("hello", "hello world") == 5)
    #expect(Transcript.commonPrefixLength("", "anything") == 0)
    #expect(Transcript.commonPrefixLength("same", "same") == 4)
}

@Test func stablePrefixCommitsTheLastWordOnceAPassRepeatsItself() {
    // Two identical passes mean more audio arrived and the model kept its
    // answer, so holding the final word back would serve no purpose — and
    // holding it back is what made short phrases look like they only
    // transcribed on release.
    #expect(Transcript.stablePrefix(previous: "hello world", current: "hello world")
        == "hello world")
}

@Test func stablePrefixStillWaitsOnTheFirstPass() {
    #expect(Transcript.stablePrefix(previous: "", current: "hello").isEmpty)
    #expect(Transcript.stablePrefix(previous: "", current: "").isEmpty)
}
