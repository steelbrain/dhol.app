import Testing
@testable import DholApp

private func liveEdit(from typed: String, to target: String) -> Transcript.Edit {
    Transcript.edit(from: typed, to: target, mayTrim: false, mayDelete: true)
}

private func finalEdit(from typed: String, to target: String) -> Transcript.Edit {
    Transcript.edit(from: typed, to: target, mayTrim: true, mayDelete: true)
}

/// What a live pass becomes once the user has touched the keyboard: it may
/// neither shorten the line nor delete characters it can no longer prove are
/// its own. This is the combination TextWriter.write actually uses for most of
/// a session where the user types alongside dictation.
private func interveningLiveEdit(from typed: String, to target: String) -> Transcript.Edit {
    Transcript.edit(from: typed, to: target, mayTrim: false, mayDelete: false)
}

@Test func liveEditAppendsWhatIsNew() {
    #expect(liveEdit(from: "hello", to: "hello world")
        == Transcript.Edit(deletions: 0, insertion: " world"))
}

@Test func liveEditRewritesAWordTheModelRevised() {
    // The regression that made live typing stop dead: once a committed word was
    // revised, an append-only writer could never match again, so nothing more
    // was typed for the rest of the session.
    #expect(liveEdit(from: "the blue folder", to: "the green folder")
        == Transcript.Edit(deletions: 11, insertion: "green folder"))
}

@Test func liveTypingRecoversAfterARevisionInsteadOfFreezing() {
    // Walk the exact sequence that used to wedge: commit, revise, continue.
    var typed = ""
    func step(_ target: String) {
        let edit = liveEdit(from: typed, to: target)
        typed.removeLast(edit.deletions)
        typed += edit.insertion
    }
    step("the blue folder")
    step("the green folder")
    step("the green folder is open")
    #expect(typed == "the green folder is open")
}

@Test func liveEditNeverWipesTheLineWhenAPassOffersNothingNew() {
    // A pass whose stable prefix is shorter than what is on screen is saying
    // "I'm less sure now", not "delete that". Only the final pass may shorten.
    #expect(liveEdit(from: "the blue folder", to: "the ") == .none)
    #expect(liveEdit(from: "hello world", to: "hello world") == .none)
}

@Test func finalEditTrimsTextTheLastPassDropped() {
    #expect(finalEdit(from: "hello world extra", to: "hello world ")
        == Transcript.Edit(deletions: 5, insertion: ""))
}

@Test func editNeverGraftsAFragmentOntoAStaleWord() {
    // "the blue folder" + dropFirst(15) of the new text would append "r is
    // open" — the offset is meaningless once the strings diverge. Only whole
    // words beginning past what is on screen may be added.
    let edit = Transcript.edit(
        from: "the blue folder",
        to: "the green folder is open",
        mayTrim: true,
        mayDelete: false
    )
    #expect(edit.insertion == " is open")
    #expect(!edit.insertion.hasPrefix("r"))
}

@Test func editKeepsUsersOwnInputAndStillAppendsTheRest() {
    // With the user's own keystrokes mixed in we can't tell our characters from
    // theirs, so nothing is deleted — but the rest of what they said must still
    // arrive rather than being dropped on the floor.
    let edit = Transcript.edit(
        from: "the blue folder",
        to: "the green folder is open",
        mayTrim: true,
        mayDelete: false
    )
    #expect(edit == Transcript.Edit(deletions: 0, insertion: " is open"))
}

@Test func editDeletesNothingWhenItCannotAndHasNothingToAdd() {
    #expect(
        Transcript.edit(from: "hello there", to: "hello world", mayTrim: true, mayDelete: false)
            == .none
    )
}

@Test func editNeverDeletesMoreThanWasTyped() {
    for (typed, target) in [("", "anything"), ("a", "completely different"), ("short", "s")] {
        let edit = Transcript.edit(from: typed, to: target, mayTrim: true, mayDelete: true)
        #expect(edit.deletions <= typed.count)
    }
}

@Test func editAddsNothingRatherThanABareSpace() {
    // The word boundary can be the last character, so the insertion would be
    // pure whitespace: a stray space typed into the document, and the word it
    // was supposed to separate dropped anyway.
    let edit = Transcript.edit(
        from: "the blue folde",
        to: "the green folder ",
        mayTrim: true,
        mayDelete: false
    )
    #expect(edit == .none)
}

@Test func liveEditAfterTheUserTypesAddsWholeWordsAndNothingElse() {
    // Every other mayDelete: false case here pairs with mayTrim: true, which is
    // the final pass. The live pass after an intervention is mayTrim: false as
    // well, and that combination had no coverage at all.
    #expect(interveningLiveEdit(from: "the blue folder", to: "the green folder is open")
        == Transcript.Edit(deletions: 0, insertion: " is open"))
    // With both permissions withheld a pass that has nothing to add can only
    // leave the line alone — it must not retract what is already on screen.
    #expect(interveningLiveEdit(from: "the blue folder", to: "the ") == .none)
}

@Test func editStillRecoversWholeWordsPastWhatWasTyped() {
    // What is on screen already ends on the word boundary, so the separator
    // must not be typed again — doing so put a double space mid-sentence.
    let edit = Transcript.edit(
        from: "the blue ",
        to: "the green folder ",
        mayTrim: true,
        mayDelete: false
    )
    #expect(edit == Transcript.Edit(deletions: 0, insertion: "folder "))
    #expect(!("the blue " + edit.insertion).contains("  "))
}
