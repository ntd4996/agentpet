//! jcode token usage (port of the macOS JcodeUsage on hoangdq08's dev branch, not upstream yet).
//!
//! jcode's hooks carry no token counts, so the session files are the only
//! source: a snapshot `~/.jcode/sessions/<id>.json` plus a journal
//! `<id>.journal.jsonl` of messages appended since the last snapshot. Every
//! assistant message has a flat `"token_usage":{...}` object, so a session's
//! total is the sum over both files. On turn_start the total sets a baseline;
//! on turn_end (or its waiting variant) the growth is fed to the pet.
//!
//! On Windows the files live inside WSL, reached through the same
//! `\\wsl.localhost\<distro>\<home>` root the hook installer uses.
//!
//! simplify: both files are rescanned whole once per turn (27 MB took ~225 ms
//! over the WSL UNC share here, so it runs off the listener thread). If jcode
//! adds token fields to its turn_end hook, read those instead and drop this.

use serde_json::Value;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

/// `<home>/.jcode/sessions/<id>.json`, or None for an id that could escape
/// the sessions directory.
pub fn session_path(session_id: &str, home: &Path) -> Option<PathBuf> {
    if session_id.is_empty() || session_id.contains('/') || session_id.contains('\\') || session_id.contains("..") {
        return None;
    }
    Some(home.join(".jcode").join("sessions").join(format!("{session_id}.json")))
}

/// Session title from a snapshot's head. The snapshot starts with
/// `{"id":..,"parent_id":..,"title":"..",...,"messages":[` so only the first
/// few KB are read (the file can be tens of MB). jcode's hooks carry no title,
/// so this is the only source. None when absent, null, or empty.
pub fn title_at(snapshot: &Path) -> Option<String> {
    use std::io::Read;
    let mut head = Vec::with_capacity(4096);
    std::fs::File::open(snapshot).ok()?.take(4096).read_to_end(&mut head).ok()?;
    title_from_head(&head)
}

/// Pure half of `title_at`, for tests: pulls `"title":"..."` out of the head.
pub fn title_from_head(head: &[u8]) -> Option<String> {
    let key = b"\"title\":";
    let at = find(head, key, 0)?;
    // Titles are never past the messages array; guard against a quoted key inside one.
    if let Some(m) = find(head, b"\"messages\":", 0) {
        if m < at { return None; }
    }
    let mut i = at + key.len();
    while i < head.len() && head[i] == b' ' { i += 1; }
    if i >= head.len() || head[i] != b'"' { return None; } // null or missing
    // Find the closing unescaped quote, then let serde decode escapes/unicode.
    let start = i;
    i += 1;
    while i < head.len() {
        match head[i] {
            b'\\' => i += 2,
            b'"' => {
                let s: String = serde_json::from_slice(&head[start..=i]).ok()?;
                let s = clean_title(&s);
                return if s.is_empty() { None } else { Some(s) };
            }
            _ => i += 1,
        }
    }
    None // truncated inside the title: skip rather than show half of it
}

/// jcode titles start with the user's first message, which often begins with
/// pasted-image placeholders (`[image 1]`). Drop them and collapse whitespace so
/// an image-only title becomes empty (the caller then shows nothing for it).
pub fn clean_title(s: &str) -> String {
    const TAG: &str = "[image ";
    let mut out = String::new();
    let mut rest = s;
    while let Some(i) = rest.find(TAG) {
        out.push_str(&rest[..i]);
        let after = &rest[i + TAG.len()..];
        let digits = after.chars().take_while(|c| c.is_ascii_digit()).count();
        if digits > 0 && after[digits..].starts_with(']') {
            rest = &after[digits + 1..];
        } else {
            out.push_str(TAG);
            rest = after;
        }
    }
    out.push_str(rest);
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// The journal next to a snapshot (`<id>.json` -> `<id>.journal.jsonl`).
pub fn journal_path(snapshot: &Path) -> PathBuf {
    snapshot.with_extension("journal.jsonl")
}

/// Session total from snapshot + journal. A missing file counts as 0.
/// Snapshot first: a checkpoint landing between the two reads makes this read
/// low, and the tracker feeds the rest at the next turn.
pub fn total_tokens_at(snapshot: &Path) -> u64 {
    [snapshot.to_path_buf(), journal_path(snapshot)]
        .iter()
        .map(|p| std::fs::read(p).map(|d| total_tokens(&d)).unwrap_or(0))
        .sum()
}

fn num(v: &Value, k: &str) -> Option<u64> {
    v.get(k).and_then(|x| x.as_u64())
}

/// Tokens the model processed for one response, cached prompt excluded.
/// jcode reports prompt_tokens = uncached + cache read + cache write for every
/// provider, so subtracting both cache fields works for Anthropic (input is
/// already uncached) and OpenAI (input includes the cached part).
pub fn billable_tokens(u: &Value) -> u64 {
    let output = num(u, "output_tokens").unwrap_or(0);
    match num(u, "prompt_tokens") {
        None => num(u, "input_tokens").unwrap_or(0) + output,
        Some(prompt) => {
            let cached = num(u, "cache_read_input_tokens").unwrap_or(0) + num(u, "cache_creation_input_tokens").unwrap_or(0);
            prompt.saturating_sub(cached) + output
        }
    }
}

const KEY: &[u8] = b"\"token_usage\":";

fn find(hay: &[u8], needle: &[u8], from: usize) -> Option<usize> {
    if from >= hay.len() { return None; }
    hay[from..].windows(needle.len()).position(|w| w == needle).map(|i| i + from)
}

/// Sum of billable tokens over every `"token_usage":{...}` in a session file.
/// Scans bytes instead of parsing the whole document (a 40 MB session took
/// 114 MB of RAM to parse on macOS). Safe because the key cannot occur
/// unescaped inside a JSON string, and the usage object is flat.
pub fn total_tokens(data: &[u8]) -> u64 {
    let mut total = 0;
    let mut cursor = 0;
    while let Some(hit) = find(data, KEY, cursor) {
        let mut open = hit + KEY.len();
        while open < data.len() && data[open] == b' ' { open += 1; }
        let close = if open < data.len() && data[open] == b'{' {
            data[open..].iter().position(|&b| b == b'}').map(|i| open + i)
        } else {
            None
        };
        let Some(close) = close else { cursor = hit + KEY.len(); continue };
        if let Ok(v) = serde_json::from_slice::<Value>(&data[open..=close]) {
            total += billable_tokens(&v);
        }
        cursor = close + 1;
    }
    total
}

/// Turns session totals into per-turn deltas. A session seen for the first
/// time only sets the baseline (old history is never fed in one go); a total
/// that shrinks (compaction) just moves it.
#[derive(Default)]
pub struct Tracker {
    seen: HashMap<String, u64>,
}

impl Tracker {
    pub fn baseline(&mut self, session: &str, total: u64) {
        self.seen.entry(session.to_string()).or_insert(total);
    }
    pub fn delta(&mut self, session: &str, total: u64) -> u64 {
        let last = self.seen.insert(session.to_string(), total);
        match last {
            Some(l) if total > l => total - l,
            _ => 0,
        }
    }
    pub fn forget(&mut self, session: &str) {
        self.seen.remove(session);
    }
    pub fn is_tracking(&self, session: &str) -> bool {
        self.seen.contains_key(session)
    }
}

/// Process-wide tracker for the running app.
pub static TRACKER: Mutex<Option<Tracker>> = Mutex::new(None);

/// What to do with a jcode event: None for events that don't touch usage.
/// Some(true) = end of turn (feed the delta), Some(false) = set the baseline.
pub fn usage_action(event: &str) -> Option<bool> {
    match event {
        "session_start" | "turn_start" => Some(false),
        "turn_end" | "waiting" => Some(true),
        _ => None, // post_tool: the turn's tokens are fed once, at its end
    }
}

/// Applies one event to the shared tracker; returns tokens to feed (0 = none).
pub fn apply(session: &str, is_end: bool, total: u64) -> u64 {
    let mut g = TRACKER.lock().unwrap_or_else(|e| e.into_inner());
    let t = g.get_or_insert_with(Tracker::default);
    if is_end { t.delta(session, total) } else { t.baseline(session, total); 0 }
}

pub fn forget(session: &str) {
    if let Some(t) = TRACKER.lock().unwrap_or_else(|e| e.into_inner()).as_mut() {
        t.forget(session);
    }
}

/// One unit of work for the usage worker: read the session total and either
/// set the baseline or report the turn's delta through `feed`.
pub struct Job {
    pub session: String,
    pub project: String,
    pub is_end: bool,
}

/// A single background thread processes jobs in arrival order, so a turn's
/// baseline is always taken before its end is measured (two parallel reads
/// could land the other way round) and the listener never blocks on the
/// ~100-200 ms UNC read of a large session (nor on resolving the WSL home,
/// which is why `snapshot_for` runs here and not on the caller's thread).
pub fn spawn_worker(
    snapshot_for: impl Fn(&str) -> Option<PathBuf> + Send + 'static,
    feed: impl Fn(&str, &str, u64) + Send + 'static,
) -> std::sync::mpsc::Sender<Job> {
    let (tx, rx) = std::sync::mpsc::channel::<Job>();
    std::thread::spawn(move || {
        for job in rx {
            let Some(snapshot) = snapshot_for(&job.session) else { continue };
            let total = total_tokens_at(&snapshot);
            let tokens = apply(&job.session, job.is_end, total);
            if tokens > 0 {
                feed(&job.session, &job.project, tokens);
            }
        }
    });
    tx
}

#[cfg(test)]
mod tests {
    use super::*;

    // Shapes copied from the macOS JcodeUsageTests on that dev branch (real sessions, 2026-10-04).
    fn session(usages: &[&str]) -> Vec<u8> {
        let msgs: Vec<String> = usages.iter().map(|u| format!(
            r#"{{"role":"user","content":[{{"type":"text","text":"say \"token_usage\": hi"}}]}},{{"role":"assistant","content":[],"token_usage":{u}}}"#
        )).collect();
        format!(r#"{{"id":"session_x_1","messages":[{}],"compaction":null}}"#, msgs.join(",")).into_bytes()
    }

    #[test]
    fn claude_usage_counts_uncached_input_plus_output() {
        let d = session(&[r#"{"prompt_tokens":88127,"input_tokens":482,"output_tokens":705,"cache_read_input_tokens":86688,"cache_creation_input_tokens":957}"#]);
        assert_eq!(total_tokens(&d), 482 + 705);
    }

    #[test]
    fn openai_usage_subtracts_cached_prompt() {
        let d = session(&[r#"{"prompt_tokens":109406,"input_tokens":109406,"output_tokens":275,"cache_read_input_tokens":108032,"cache_creation_input_tokens":0}"#]);
        assert_eq!(total_tokens(&d), 109406 - 108032 + 275);
    }

    #[test]
    fn sums_all_messages_and_skips_quoted_key() {
        let d = session(&[
            r#"{"prompt_tokens":100,"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":90,"cache_creation_input_tokens":0}"#,
            r#"{"prompt_tokens":50,"input_tokens":50,"output_tokens":1,"cache_read_input_tokens":null,"cache_creation_input_tokens":null}"#,
            r#"{"input_tokens":7,"output_tokens":3}"#,
        ]);
        assert_eq!(total_tokens(&d), (10 + 5) + (50 + 1) + (7 + 3));
    }

    #[test]
    fn pretty_printed_key_is_found() {
        assert_eq!(total_tokens(br#"{"messages":[{"token_usage": {"input_tokens": 4, "output_tokens": 2}}]}"#), 6);
    }

    #[test]
    fn not_a_session_gives_zero() {
        assert_eq!(total_tokens(b"not json"), 0);
        assert_eq!(total_tokens(br#"{"token_usage":{"input_tokens":3"#), 0);
    }

    #[test]
    fn title_is_read_from_snapshot_head() {
        let d = br#"{"id":"s","parent_id":null,"title":"x\u00f3a session \"c\u0169\"","created_at":"t","messages":[]}"#;
        assert_eq!(title_from_head(d).as_deref(), Some("xóa session \"cũ\""));
    }

    #[test]
    fn missing_null_or_empty_title_is_none() {
        assert_eq!(title_from_head(br#"{"id":"s","messages":[]}"#), None);
        assert_eq!(title_from_head(br#"{"id":"s","title":null,"messages":[]}"#), None);
        assert_eq!(title_from_head(br#"{"id":"s","title":"  ","messages":[]}"#), None);
    }

    #[test]
    fn title_inside_messages_is_ignored() {
        let d = br#"{"id":"s","messages":[{"text":"say \"title\":\"fake\""}]}"#;
        assert_eq!(title_from_head(d), None);
    }

    #[test]
    fn image_placeholders_are_dropped_from_titles() {
        assert_eq!(clean_title("[image 4][image 5]"), "");
        assert_eq!(clean_title("[image 1] kiểm tra mấy file này"), "kiểm tra mấy file này");
        assert_eq!(clean_title("[image 1] [image 2]  bạn  kiểm tra"), "bạn kiểm tra");
        assert_eq!(clean_title("see [image x] here"), "see [image x] here"); // not a placeholder
        assert_eq!(clean_title("tail [image 12"), "tail [image 12"); // unterminated
    }

    #[test]
    fn image_only_title_reads_as_none() {
        assert_eq!(title_from_head(br#"{"id":"s","title":"[image 4][image 5]","messages":[]}"#), None);
        assert_eq!(
            title_from_head(br#"{"id":"s","title":"[image 1] d\u1ecdn \u0111i","messages":[]}"#).as_deref(),
            Some("dọn đi")
        );
    }

    #[test]
    fn truncated_title_is_none() {
        assert_eq!(title_from_head(br#"{"id":"s","title":"abc"#), None);
    }

    #[test]
    fn session_path_rejects_traversal() {
        let h = Path::new("/h");
        assert_eq!(session_path("session_x_1", h).unwrap(), Path::new("/h/.jcode/sessions/session_x_1.json"));
        assert!(session_path("../auth", h).is_none());
        assert!(session_path("a/b", h).is_none());
        assert!(session_path("a\\b", h).is_none());
        assert!(session_path("", h).is_none());
        assert_eq!(journal_path(Path::new("/h/.jcode/sessions/session_x_1.json")),
                   Path::new("/h/.jcode/sessions/session_x_1.journal.jsonl"));
    }

    #[test]
    fn total_adds_journal_to_snapshot() {
        let dir = std::env::temp_dir().join(format!("jcode-usage-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let snap = dir.join("session_x_1.json");
        std::fs::write(&snap, session(&[r#"{"input_tokens":10,"output_tokens":5}"#])).unwrap();
        assert_eq!(total_tokens_at(&snap), 15);
        let lines = [
            r#"{"meta":{"title":"t"},"append_messages":[{"role":"assistant","content":[],"token_usage":{"input_tokens":3,"output_tokens":2}}]}"#,
            r#"{"meta":{"title":"t"},"append_messages":[{"role":"user","content":[]}]}"#,
        ];
        std::fs::write(journal_path(&snap), lines.join("\n") + "\n").unwrap();
        assert_eq!(total_tokens_at(&snap), 15 + 5);
        assert_eq!(total_tokens_at(&dir.join("missing.json")), 0);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn turn_feeds_only_its_own_tokens() {
        let mut t = Tracker::default();
        t.baseline("s", 4_500_000);
        assert_eq!(t.delta("s", 4_512_000), 12_000);
        t.baseline("s", 4_512_000);
        assert_eq!(t.delta("s", 4_520_000), 8_000);
    }

    #[test]
    fn first_sighting_feeds_nothing() {
        let mut t = Tracker::default();
        assert_eq!(t.delta("s", 4_500_000), 0);
        assert_eq!(t.delta("s", 4_501_000), 1_000);
    }

    #[test]
    fn shrinking_total_moves_baseline() {
        let mut t = Tracker::default();
        t.baseline("s", 900);
        assert_eq!(t.delta("s", 300), 0);
        assert_eq!(t.delta("s", 350), 50);
    }

    #[test]
    fn baseline_does_not_overwrite_and_forget_resets() {
        let mut t = Tracker::default();
        t.baseline("s", 100);
        t.baseline("s", 999);
        assert_eq!(t.delta("s", 150), 50);
        t.forget("s");
        assert!(!t.is_tracking("s"));
        assert_eq!(t.delta("s", 5_000), 0);
    }

    #[test]
    fn usage_action_matches_mac_daemon() {
        assert_eq!(usage_action("session_start"), Some(false));
        assert_eq!(usage_action("turn_start"), Some(false));
        assert_eq!(usage_action("turn_end"), Some(true));
        assert_eq!(usage_action("waiting"), Some(true));
        assert_eq!(usage_action("post_tool"), None);
    }
}
