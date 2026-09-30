import Foundation

/// Reads jcode's Claude OAuth login from `~/.jcode/auth.json` so the usage
/// meter keeps working for people who run jcode rather than Claude Code (whose
/// own token then sits expired in the Keychain).
///
/// Shape (jcode 0.89): `{"anthropic_accounts": [{"label", "access", "refresh",
/// "expires" (epoch ms), ...}], "active_anthropic_account": "<label>"}`.
/// Read-only: only the short-lived access token is used, never the refresh
/// token, and nothing is written back.
public enum JcodeClaudeAuth {
    /// The active account's access token, or the first account's when no
    /// account is marked active. `nil` if missing, malformed, or expired.
    public static func accessToken(fromAuthJSON data: Data, now: Date) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accounts = json["anthropic_accounts"] as? [[String: Any]], !accounts.isEmpty
        else { return nil }
        let active = json["active_anthropic_account"] as? String
        let account = accounts.first { ($0["label"] as? String) == active } ?? accounts[0]
        guard let token = account["access"] as? String, !token.isEmpty,
              !OAuthExpiry.isExpired(account["expires"], now: now) else { return nil }
        return token
    }
}

/// Expiry check shared by every OAuth token file we read (Claude Code's
/// Keychain entry and jcode's `auth.json` store it differently).
public enum OAuthExpiry {
    /// True only when `expiry` is a number (epoch seconds or milliseconds) in
    /// the past. A missing/unknown expiry is not treated as expired: the API
    /// call is the real check.
    public static func isExpired(_ expiry: Any?, now: Date) -> Bool {
        guard let raw = (expiry as? NSNumber)?.doubleValue else { return false }
        // Heuristic: epoch-ms values are > 1e11 (1973+ in ms, year 5138 in s).
        let seconds = raw > 1e11 ? raw / 1000 : raw
        return seconds <= now.timeIntervalSince1970
    }
}
