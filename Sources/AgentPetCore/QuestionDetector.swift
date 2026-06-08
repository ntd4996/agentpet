import Foundation

/// Detects whether a piece of assistant text reads like Claude ended its turn
/// by asking the user something — as opposed to simply reporting completion.
///
/// Pure string logic: no I/O, no actor isolation. Used to correct a session's
/// state from `.done` to `.waiting` when Claude's `Stop` hook fires after a
/// turn that actually ended in a question (Claude Code sends no separate event
/// for "I asked the user something and am waiting for a reply").
public enum QuestionDetector {
    /// Phrases that open a direct request for the user's decision.
    private static let questionStarters = [
        "which ", "what ", "how ", "should i", "do you", "want me to",
        "shall i", "would you", "can you", "could you", "are you",
    ]

    /// Polite, optional follow-ups appended after a completed summary — not
    /// blocking questions that need an immediate answer.
    private static let optionalFollowUpPatterns = [
        "let me know if",
        "let me know when",
        "feel free to",
        "if you'd like any",
        "if you want any",
        "if you want to",
        "if you'd like to",
        "if you need any",
        "say which one",
        "say the word",
        "if anything else",
        "happy to help",
        "happy to make",
        "don't hesitate",
        "just let me know",
    ]

    /// True when the **last sentence** is a direct question or request for
    /// direction. Completion summaries with an optional "let me know if…"
    /// tail are treated as done, not waiting.
    public static func looksLikeQuestion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let last = lastSentence(of: trimmed).lowercased()
        guard !last.isEmpty else { return false }
        if isOptionalFollowUp(last) { return false }
        return isPrimaryQuestion(last)
    }

    // MARK: - Private

    private static func lastSentence(of text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)

        var segments: [String] = []
        var current = ""
        for char in normalized {
            current.append(char)
            if char == "." || char == "!" || char == "?" {
                let s = current.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { segments.append(s) }
                current = ""
            }
        }
        let remainder = current.trimmingCharacters(in: .whitespaces)
        if !remainder.isEmpty { segments.append(remainder) }

        return segments.last ?? normalized
    }

    private static func isOptionalFollowUp(_ sentenceLower: String) -> Bool {
        optionalFollowUpPatterns.contains { sentenceLower.contains($0) }
    }

    private static func isPrimaryQuestion(_ sentenceLower: String) -> Bool {
        if sentenceLower.hasSuffix("?") { return true }
        return questionStarters.contains { sentenceLower.hasPrefix($0) }
    }
}
