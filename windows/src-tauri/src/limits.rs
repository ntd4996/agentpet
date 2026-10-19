//! Subscription limits read straight from the provider, a port of the macOS
//! `NativeUsageProbe` (Claude half) + `JcodeClaudeAuth`.
//!
//! Token sources, best first: Claude Code's `~/.claude/.credentials.json`, then
//! jcode's active Claude account in `~/.jcode/auth.json` (reached over
//! `\\wsl.localhost` when jcode runs in WSL). Read-only: only the short-lived
//! access token is used, never the refresh token, nothing is written back, and
//! the token stays in Rust (the webview only sees percentages and reset times).
//! simplify: Claude only; the Codex `wham/usage` probe is the upgrade path.

use serde::Serialize;
use serde_json::Value;
use std::path::PathBuf;
use std::time::Duration;

const USAGE_URL: &str = "https://api.anthropic.com/api/oauth/usage";

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct LimitWindow {
    /// "Session" / "Weekly" (translated in the webview).
    pub label: String,
    /// 0..1 of the budget still left.
    pub fraction_left: f64,
    /// The provider's reset timestamp, passed through for `Date.parse`.
    pub resets_at: Option<String>,
    /// Window length in seconds (5h / 7d), for the "5h" / "7d" short label.
    pub period: f64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct LimitProvider {
    pub id: String,
    pub display_name: String,
    pub windows: Vec<LimitWindow>,
}

/// True only when `expiry` is a number (epoch seconds or milliseconds) in the
/// past. A missing/unknown expiry is not treated as expired: the API call is
/// the real check (mirrors `OAuthExpiry.isExpired`).
pub fn is_expired(expiry: Option<&Value>, now_secs: f64) -> bool {
    let Some(raw) = expiry.and_then(Value::as_f64) else { return false };
    // Heuristic: epoch-ms values are > 1e11 (1973+ in ms, year 5138 in s).
    let secs = if raw > 1e11 { raw / 1000.0 } else { raw };
    secs <= now_secs
}

/// jcode `auth.json`: `{"anthropic_accounts": [{"label", "access", "expires"
/// (epoch ms), ...}], "active_anthropic_account": "<label>"}`. The active
/// account's token, else the first account's; None if missing/expired.
pub fn jcode_access_token(data: &[u8], now_secs: f64) -> Option<String> {
    let json: Value = serde_json::from_slice(data).ok()?;
    let accounts = json.get("anthropic_accounts")?.as_array()?;
    let first = accounts.first()?;
    let active = json.get("active_anthropic_account").and_then(Value::as_str);
    let account = accounts
        .iter()
        .find(|a| active.is_some() && a.get("label").and_then(Value::as_str) == active)
        .unwrap_or(first);
    let token = account.get("access")?.as_str()?;
    if token.is_empty() || is_expired(account.get("expires"), now_secs) {
        return None;
    }
    Some(token.to_string())
}

/// Claude Code `.credentials.json`: `{"claudeAiOauth": {"accessToken",
/// "expiresAt"}}`.
pub fn claude_code_access_token(data: &[u8], now_secs: f64) -> Option<String> {
    let json: Value = serde_json::from_slice(data).ok()?;
    let oauth = json.get("claudeAiOauth")?;
    let token = oauth.get("accessToken")?.as_str()?;
    if token.is_empty() || is_expired(oauth.get("expiresAt"), now_secs) {
        return None;
    }
    Some(token.to_string())
}

/// Parses an `/api/oauth/usage` body. Windows are `{"utilization": <percent
/// used>, "resets_at": ...}`.
pub fn claude_provider(json: &Value) -> Option<LimitProvider> {
    let mut windows = Vec::new();
    for (key, label, period) in [("five_hour", "Session", 18_000.0), ("seven_day", "Weekly", 604_800.0)] {
        let Some(w) = json.get(key) else { continue };
        let Some(used) = w.get("utilization").and_then(Value::as_f64) else { continue };
        let resets_at = match w.get("resets_at") {
            Some(Value::String(s)) => Some(s.clone()),
            Some(Value::Number(n)) => Some(n.to_string()),
            _ => None,
        };
        windows.push(LimitWindow {
            label: label.into(),
            fraction_left: ((100.0 - used) / 100.0).clamp(0.0, 1.0),
            resets_at,
            period,
        });
    }
    if windows.is_empty() {
        return None;
    }
    Some(LimitProvider { id: "claude".into(), display_name: "Claude".into(), windows })
}

/// Unexpired candidate tokens from the given files, deduped, in order. Each
/// file is tried with both shapes, so the caller just lists paths.
pub fn candidate_tokens(paths: &[PathBuf], now_secs: f64) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for p in paths {
        let Ok(data) = std::fs::read(p) else { continue };
        let token = claude_code_access_token(&data, now_secs).or_else(|| jcode_access_token(&data, now_secs));
        if let Some(t) = token {
            if !out.contains(&t) {
                out.push(t);
            }
        }
    }
    out
}

/// Claude Code (native home, then WSL home) and jcode (`hooks::jcode_home`).
pub fn default_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Some(home) = dirs::home_dir() {
        paths.push(home.join(".claude").join(".credentials.json"));
    }
    if let Some((home, _)) = crate::hooks::jcode_home() {
        paths.push(home.join(".claude").join(".credentials.json"));
        paths.push(home.join(".jcode").join("auth.json"));
    }
    paths
}

fn now_secs() -> f64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

/// Tries every unexpired token in order (each source is refreshed only by its
/// own CLI, so one can be stale while another is live). None when no token
/// works or the network is down; the UI then just shows nothing.
pub async fn probe_claude(paths: &[PathBuf]) -> Option<LimitProvider> {
    let tokens = candidate_tokens(paths, now_secs());
    if tokens.is_empty() {
        return None;
    }
    // The updater installs the same provider lazily; whoever runs first wins.
    if rustls::crypto::CryptoProvider::get_default().is_none() {
        let _ = rustls::crypto::ring::default_provider().install_default();
    }
    let client = reqwest::Client::builder().timeout(Duration::from_secs(8)).build().ok()?;
    for token in tokens {
        if let Some(p) = probe_with(&client, &token).await {
            return Some(p);
        }
    }
    None
}

async fn probe_with(client: &reqwest::Client, token: &str) -> Option<LimitProvider> {
    for attempt in 0..2 {
        let res = client
            .get(USAGE_URL)
            .bearer_auth(token)
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .header("anthropic-beta", "oauth-2025-04-20")
            .header("User-Agent", "claude-code/2.1.69")
            .send()
            .await;
        let retry = match res {
            Ok(r) if r.status().is_success() => {
                let body = r.bytes().await.ok()?;
                let json: Value = serde_json::from_slice(&body).ok()?;
                return claude_provider(&json);
            }
            Ok(r) => r.status().is_server_error(),
            Err(_) => true,
        };
        if !retry || attempt == 1 {
            return None;
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const NOW: f64 = 1_800_000_000.0;
    fn future_ms() -> f64 { (NOW + 3600.0) * 1000.0 }
    fn past_ms() -> f64 { (NOW - 60.0) * 1000.0 }

    fn auth(accounts: Value, active: Option<&str>) -> Vec<u8> {
        let mut j = json!({ "anthropic_accounts": accounts });
        if let Some(a) = active {
            j["active_anthropic_account"] = json!(a);
        }
        serde_json::to_vec(&j).unwrap()
    }

    #[test]
    fn active_account_wins() {
        let d = auth(json!([
            {"label": "a", "access": "tok-a", "expires": future_ms()},
            {"label": "b", "access": "tok-b", "expires": future_ms()}
        ]), Some("b"));
        assert_eq!(jcode_access_token(&d, NOW).as_deref(), Some("tok-b"));
    }

    #[test]
    fn falls_back_to_first_account_when_active_unknown() {
        let one = json!([{"label": "a", "access": "tok-a", "expires": future_ms()}]);
        assert_eq!(jcode_access_token(&auth(one.clone(), Some("gone")), NOW).as_deref(), Some("tok-a"));
        assert_eq!(jcode_access_token(&auth(one, None), NOW).as_deref(), Some("tok-a"));
    }

    #[test]
    fn expired_token_is_skipped() {
        let d = auth(json!([{"label": "a", "access": "tok-a", "expires": past_ms()}]), Some("a"));
        assert_eq!(jcode_access_token(&d, NOW), None);
    }

    #[test]
    fn malformed_or_empty_is_none() {
        assert_eq!(jcode_access_token(b"not json", NOW), None);
        assert_eq!(jcode_access_token(b"{}", NOW), None);
        assert_eq!(jcode_access_token(&auth(json!([]), None), NOW), None);
        let blank = auth(json!([{"label": "a", "access": "", "expires": future_ms()}]), Some("a"));
        assert_eq!(jcode_access_token(&blank, NOW), None);
    }

    #[test]
    fn expiry_units() {
        assert!(is_expired(Some(&json!((NOW - 1.0) * 1000.0)), NOW), "ms, past");
        assert!(!is_expired(Some(&json!((NOW + 60.0) * 1000.0)), NOW), "ms, future");
        assert!(is_expired(Some(&json!(NOW - 1.0)), NOW), "seconds, past");
        assert!(!is_expired(Some(&json!(NOW + 60.0)), NOW), "seconds, future");
        assert!(!is_expired(None, NOW), "unknown expiry: let the API decide");
        assert!(!is_expired(Some(&json!("soon")), NOW));
    }

    #[test]
    fn claude_code_credentials_shape() {
        let ok = serde_json::to_vec(&json!({"claudeAiOauth": {"accessToken": "cc", "expiresAt": future_ms()}})).unwrap();
        assert_eq!(claude_code_access_token(&ok, NOW).as_deref(), Some("cc"));
        let old = serde_json::to_vec(&json!({"claudeAiOauth": {"accessToken": "cc", "expiresAt": past_ms()}})).unwrap();
        assert_eq!(claude_code_access_token(&old, NOW), None);
        // A jcode file is not mistaken for Claude Code credentials.
        let j = auth(json!([{"label": "a", "access": "tok-a"}]), Some("a"));
        assert_eq!(claude_code_access_token(&j, NOW), None);
    }

    #[test]
    fn claude_keeps_both_windows_with_resets() {
        let body = json!({
            "five_hour": {"utilization": 37.0, "resets_at": "2026-10-02T23:59:59.536032+00:00"},
            "seven_day": {"utilization": 79.0, "resets_at": "2026-10-05T03:59:59.536051+00:00"}
        });
        let p = claude_provider(&body).unwrap();
        assert_eq!(p.windows.iter().map(|w| w.label.as_str()).collect::<Vec<_>>(), ["Session", "Weekly"]);
        assert!((p.windows[0].fraction_left - 0.63).abs() < 1e-9);
        assert!((p.windows[1].fraction_left - 0.21).abs() < 1e-9);
        assert_eq!(p.windows[0].period, 18_000.0);
        assert_eq!(p.windows[1].period, 604_800.0);
        assert!(p.windows.iter().all(|w| w.resets_at.is_some()));
    }

    #[test]
    fn claude_clamps_and_skips_missing_windows() {
        let p = claude_provider(&json!({"five_hour": {"utilization": 130}, "seven_day": null})).unwrap();
        assert_eq!(p.windows.len(), 1);
        assert_eq!(p.windows[0].fraction_left, 0.0);
        assert_eq!(p.windows[0].resets_at, None);
        assert_eq!(claude_provider(&json!({"error": "x"})), None);
    }

    #[test]
    fn candidates_dedupe_and_skip_unreadable() {
        let dir = std::env::temp_dir().join(format!("ap-limits-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let cc = dir.join("cc.json");
        let jc = dir.join("auth.json");
        std::fs::write(&cc, serde_json::to_vec(&json!({"claudeAiOauth": {"accessToken": "same"}})).unwrap()).unwrap();
        std::fs::write(&jc, auth(json!([{"label": "a", "access": "same"}, {"label": "b", "access": "other"}]), Some("a"))).unwrap();
        let got = candidate_tokens(&[dir.join("missing.json"), cc, jc], NOW);
        assert_eq!(got, vec!["same".to_string()]);
        std::fs::remove_dir_all(&dir).ok();
    }
}
