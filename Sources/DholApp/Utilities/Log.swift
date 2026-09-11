import OSLog

/// Failures worth being able to look up after the fact, via Console.app or
/// `log stream --predicate 'subsystem == "ai.aneesiqbal.dhol"'`.
///
/// This deliberately goes nowhere else. The previous hand-rotated file under
/// ~/Library/Logs duplicated what the unified log already keeps.
enum Log {
    static let shared = Logger(subsystem: "ai.aneesiqbal.dhol", category: "dictation")
}
