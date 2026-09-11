import Foundation

/// Text rules shared by the live and final transcription passes.
enum Transcript {
    /// Collapses runs of whitespace and removes control characters.
    ///
    /// Dictated text is delivered as keystrokes, so a literal newline would
    /// submit the form or run the shell command the user is still dictating.
    static func sanitized(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if result.last != " " { result.append(" ") }
            } else if !CharacterSet.controlCharacters.contains(scalar) {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// The longest run of whole words that two consecutive hypotheses agree on.
    ///
    /// The model revises its guess as more audio arrives — "wor" becomes
    /// "world", "blue" becomes "green" — so only text that survived a second
    /// pass is settled enough to type. Stopping at a word boundary keeps a
    /// half-finished word from being typed and then needing correction.
    static func stablePrefix(previous: String, current: String) -> String {
        let old = sanitized(previous)
        let new = sanitized(current)

        // Two identical passes mean the model heard more audio and still did
        // not change its mind, so the trailing word is settled too. Without
        // this the last word is always held back, and a short phrase finishes
        // before anything has been released — which looks like no live
        // transcription at all.
        if !old.isEmpty, old == new { return new }

        let shared = zip(old, new).prefix { $0 == $1 }.map(\.0)
        guard let lastSpace = shared.lastIndex(where: \.isWhitespace) else { return "" }
        return String(shared[...lastSpace])
    }

    /// How many leading characters two strings have in common.
    static func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs, rhs).prefix { $0 == $1 }.count
    }

    /// The keystrokes needed to turn text already typed into the text wanted.
    struct Edit: Equatable {
        var deletions = 0
        var insertion = ""

        static let none = Edit()
        var isEmpty: Bool { deletions == 0 && insertion.isEmpty }
    }

    /// Works out how to move the target app from `typed` to `target`.
    ///
    /// - Parameters:
    ///   - mayTrim: whether a pass with nothing to add may still shorten the
    ///     line. Only the final pass is authoritative enough for that; a live
    ///     pass saying nothing new must not wipe the line and put it back.
    ///     This is narrower than "may the text get shorter": a live pass is
    ///     still free to delete as part of a revision, because there it types
    ///     a replacement over what it removed.
    ///   - mayDelete: false once the user has typed or clicked, after which our
    ///     own characters can no longer be told from theirs.
    static func edit(
        from typed: String,
        to target: String,
        mayTrim: Bool,
        mayDelete: Bool
    ) -> Edit {
        let shared = commonPrefixLength(typed, target)
        let needsDeletion = typed.count > shared
        let hasAddition = target.count > shared
        guard hasAddition || (mayTrim && needsDeletion) else { return .none }

        // Can't safely rewrite, so keep what is on screen and add only whole
        // words beginning past it. A stale word beats dropping everything that
        // followed it, but the offset can't be used directly: the two strings
        // have diverged, so cutting at `typed.count` lands mid-word and grafts
        // a fragment onto the end of the stale one.
        if needsDeletion, !mayDelete {
            let characters = Array(target)
            guard typed.count < characters.count,
                  let boundary = characters[typed.count...].firstIndex(where: \.isWhitespace)
            else { return .none }
            // A stable prefix always ends on a word boundary, so `typed`
            // usually ends in a space already; typing the separator again would
            // leave a double space in the middle of the sentence.
            let separated = characters[boundary...]
            let insertion = typed.last?.isWhitespace == true
                ? String(separated.drop(while: \.isWhitespace))
                : String(separated)
            // The boundary can be the final character, leaving an insertion of
            // pure whitespace: that types a stray space and still drops the
            // word it was meant to separate. Better to add nothing.
            guard insertion.contains(where: { !$0.isWhitespace }) else { return .none }
            return Edit(deletions: 0, insertion: insertion)
        }

        return Edit(
            deletions: needsDeletion ? typed.count - shared : 0,
            insertion: String(target.dropFirst(shared))
        )
    }
}
