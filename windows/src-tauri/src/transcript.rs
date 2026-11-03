//! Reads Claude Code transcripts (JSONL) , a port of the macOS app's
//! TranscriptReader + QuestionDetector. Used to (1) name sessions after the
//! conversation, and (2) detect when Claude ended its turn by ASKING the user
//! something, so a `Stop` that looks "done" is corrected to "waiting".

use serde_json::Value;
use std::collections::{HashMap, HashSet, VecDeque};
use std::io::{Read, Seek, SeekFrom};
use std::sync::Mutex;

// Summary-based titles are final; first-user-message titles are provisional
// (a later summary supersedes them), so only summaries are cached.
static SUMMARY_CACHE: Mutex<Option<HashMap<String, String>>> = Mutex::new(None);
// Byte offset already consumed by `new_usage_tokens` per transcript path, so
// repeated reads only sum the freshly-appended usage (a port of the macOS
// TranscriptReader.usageOffsets).
static USAGE_OFFSETS: Mutex<Option<HashMap<String, u64>>> = Mutex::new(None);
// Claude reply ids already counted, across transcripts (port of the macOS
// TranscriptReader.countedIDs, PR #84). Claude Code writes one line per content
// block of a reply (thinking, text, tool_use) and each repeats the reply's
// `usage`, and a resumed session copies earlier replies into a new file. Only
// locked inside `new_usage_detail`, while USAGE_OFFSETS is held.
static COUNTED: Mutex<Option<Counted>> = Mutex::new(None);
// Usage lines timestamped before this (ISO 8601 UTC, same shape Claude Code
// writes) are skipped. Set once at launch: offsets live in memory, so every
// transcript is read from the start again after a relaunch.
static COUNT_SINCE: std::sync::OnceLock<String> = std::sync::OnceLock::new();
// Resolved Codex rollout path per session, so we don't re-walk ~/.codex/sessions
// on every event (it fires on each tool use).
static CODEX_PATHS: Mutex<Option<HashMap<String, String>>> = Mutex::new(None);

/// Cached wrapper around `codex_rollout_path`, keyed by session id.
pub fn codex_rollout_path_cached(session_id: &str, cwd: Option<&str>) -> Option<String> {
    if let Some(hit) = CODEX_PATHS
        .lock()
        .ok()
        .and_then(|g| g.as_ref().and_then(|m| m.get(session_id).cloned()))
    {
        return Some(hit);
    }
    let path = codex_rollout_path(session_id, cwd)?;
    if let Ok(mut g) = CODEX_PATHS.lock() {
        g.get_or_insert_with(HashMap::new).insert(session_id.to_string(), path.clone());
    }
    Some(path)
}

/// Per-million-token USD rates by Claude tier (port of macOS ModelPricing):
/// input, output. Cache-create is input×1.25, cache-read is input×0.1.
fn claude_cost(model: Option<&str>, input: i64, output: i64, cache_create: i64, cache_read: i64) -> f64 {
    let m = model.unwrap_or("").to_lowercase();
    let (in_rate, out_rate) = if m.contains("haiku") {
        (1.0, 5.0)
    } else if m.contains("opus") {
        (15.0, 75.0)
    } else {
        (3.0, 15.0)
    };
    (input as f64 * in_rate
        + output as f64 * out_rate
        + cache_create as f64 * in_rate * 1.25
        + cache_read as f64 * in_rate * 0.1)
        / 1_000_000.0
}

/// Claude usage appended to a transcript since the last read. `tokens` is
/// input+output only: it is what feeds the pet (XP/level), so it must not change
/// meaning. The breakdown and cost only feed the usage dashboard.
#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct UsageDelta {
    pub tokens: i64,
    pub cost: f64,
    pub input: i64,
    pub output: i64,
    pub cache_read: i64,
    pub cache_write: i64,
}

/// Message ids seen so far; the oldest half is dropped past `LIMIT`.
#[derive(Default)]
pub struct Counted {
    ids: HashSet<String>,
    order: VecDeque<String>,
}

impl Counted {
    const LIMIT: usize = 20_000;

    /// True the first time `id` is seen.
    fn insert(&mut self, id: &str) -> bool {
        if !self.ids.insert(id.to_string()) {
            return false;
        }
        self.order.push_back(id.to_string());
        if self.order.len() > Self::LIMIT {
            for old in self.order.drain(..Self::LIMIT / 2) {
                self.ids.remove(&old);
            }
        }
        true
    }
}

/// Feed the pet only what is spent from now on (call once at launch).
pub fn count_usage_from_now() {
    let _ = COUNT_SINCE.set(iso_utc(std::time::SystemTime::now()));
}

/// `2026-11-03T01:02:03.456Z`, the format of Claude Code's `timestamp` field,
/// so the two compare as strings.
fn iso_utc(t: std::time::SystemTime) -> String {
    let d = t.duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
    let secs = d.as_secs() as i64;
    let (days, rem) = (secs.div_euclid(86_400), secs.rem_euclid(86_400));
    // Civil date from days since 1970-01-01 (Howard Hinnant's algorithm).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + if month <= 2 { 1 } else { 0 };
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}.{:03}Z",
        rem / 3600,
        rem % 3600 / 60,
        rem % 60,
        d.subsec_millis()
    )
}

/// Parses transcript JSONL lines into a `UsageDelta` (pure, unit-tested). Each
/// reply counts once (by `message.id`, across calls sharing `counted`), and
/// lines timestamped before `since` are skipped. Lines without an id or a
/// timestamp still count.
pub fn sum_usage_lines(text: &str, since: Option<&str>, counted: &mut Counted) -> UsageDelta {
    let mut d = UsageDelta::default();
    for line in text.lines() {
        if !line.contains("\"usage\"") {
            continue; // fast reject: most lines carry no usage object
        }
        let Ok(json) = serde_json::from_str::<Value>(line.trim()) else { continue };
        if let Some(msg) = json.get("message") {
            if let Some(usage) = msg.get("usage") {
                if let (Some(since), Some(stamp)) = (since, json.get("timestamp").and_then(|v| v.as_str())) {
                    if stamp.ends_with('Z') && stamp < since {
                        continue;
                    }
                }
                if let Some(id) = msg.get("id").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
                    if !counted.insert(id) {
                        continue;
                    }
                }
                let g = |k: &str| usage.get(k).and_then(|v| v.as_i64()).unwrap_or(0);
                let (input, output) = (g("input_tokens"), g("output_tokens"));
                let (cache_write, cache_read) = (g("cache_creation_input_tokens"), g("cache_read_input_tokens"));
                d.tokens += input + output;
                d.input += input;
                d.output += output;
                d.cache_write += cache_write;
                d.cache_read += cache_read;
                let model = msg.get("model").and_then(|v| v.as_str());
                d.cost += claude_cost(model, input, output, cache_write, cache_read);
            }
        }
    }
    d
}

/// Usage (tokens, breakdown, estimated USD cost) for lines appended to the
/// transcript since the previous call for the same path. First call consumes the
/// whole file. `None` if unreadable, a zero delta if no new usage lines appeared.
pub fn new_usage_detail(path: &str) -> Option<UsageDelta> {
    // Hold the offsets lock across the whole read + advance, so two events for
    // the same session firing at once can't both consume the same bytes (which
    // would double-feed the pet). Reads are small deltas, so serialising is fine.
    let mut guard = USAGE_OFFSETS.lock().ok()?;
    let offsets = guard.get_or_insert_with(HashMap::new);

    let mut f = std::fs::File::open(path).ok()?;
    let size = f.seek(SeekFrom::End(0)).ok()?;
    let mut start = offsets.get(path).copied().unwrap_or(0);
    if start > size {
        start = 0; // file truncated/replaced: start over
    }
    if size <= start {
        return Some(UsageDelta::default());
    }
    f.seek(SeekFrom::Start(start)).ok()?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf).ok()?;
    // Consume up to the last full line; a partial trailing line stays for later.
    let nl = buf.iter().rposition(|&b| b == b'\n')?;
    let consumable = &buf[..=nl];
    offsets.insert(path.to_string(), start + consumable.len() as u64);
    let mut counted = COUNTED.lock().unwrap_or_else(|e| e.into_inner());
    let counted = counted.get_or_insert_with(Counted::default);
    let since = COUNT_SINCE.get().map(String::as_str);
    Some(sum_usage_lines(&String::from_utf8_lossy(consumable), since, counted))
}

#[cfg(test)]
mod usage_detail_tests {
    use super::*;

    #[test]
    fn tokens_stay_input_plus_output_and_breakdown_sums() {
        let l1 = r#"{"message":{"model":"claude-opus-4","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000}}}"#;
        let l2 = r#"{"message":{"model":"claude-haiku","usage":{"input_tokens":1,"output_tokens":2}}}"#;
        let d = sum_usage_lines(&format!("{l1}\nnot json \"usage\"\n{l2}\n"), None, &mut Counted::default());
        assert_eq!(d.tokens, 18); // pet XP basis: input+output only, cache excluded
        assert_eq!((d.input, d.output, d.cache_write, d.cache_read), (11, 7, 100, 1000));
        assert!(d.cost > 0.0);
    }

    fn line(id: &str, stamp: &str, input: i64, output: i64) -> String {
        format!(r#"{{"timestamp":"{stamp}","message":{{"id":"{id}","model":"claude-opus-4","usage":{{"input_tokens":{input},"output_tokens":{output}}}}}}}"#)
    }

    #[test]
    fn one_reply_split_into_blocks_counts_once() {
        // Thinking, text and tool_use lines of one reply all repeat its usage.
        let t = "2026-11-03T01:00:00.000Z";
        let text = [line("msg_a", t, 10, 5), line("msg_a", t, 10, 5), line("msg_a", t, 10, 5), line("msg_b", t, 1, 1)].join("\n");
        let d = sum_usage_lines(&text, None, &mut Counted::default());
        assert_eq!(d.tokens, 17);
    }

    #[test]
    fn resumed_session_copy_in_another_file_is_not_recounted() {
        let mut c = Counted::default();
        let t = "2026-11-03T01:00:00.000Z";
        assert_eq!(sum_usage_lines(&line("msg_a", t, 10, 5), None, &mut c).tokens, 15);
        // Same reply copied into the resumed session's new transcript.
        assert_eq!(sum_usage_lines(&(line("msg_a", t, 10, 5) + "\n" + &line("msg_c", t, 2, 2)), None, &mut c).tokens, 4);
    }

    #[test]
    fn replies_from_before_launch_are_skipped() {
        let since = "2026-11-03T01:00:00.000Z";
        let text = [line("msg_old", "2026-11-02T23:59:59.999Z", 100, 100), line("msg_new", "2026-11-03T01:00:00.001Z", 3, 4)].join("\n");
        assert_eq!(sum_usage_lines(&text, Some(since), &mut Counted::default()).tokens, 7);
        // No id and no timestamp: still counted, like before.
        let bare = r#"{"message":{"usage":{"input_tokens":2,"output_tokens":3}}}"#;
        assert_eq!(sum_usage_lines(&format!("{bare}\n{bare}"), Some(since), &mut Counted::default()).tokens, 10);
    }

    #[test]
    fn id_cache_is_bounded() {
        let mut c = Counted::default();
        for i in 0..=Counted::LIMIT {
            assert!(c.insert(&format!("m{i}")));
        }
        assert_eq!(c.ids.len(), c.order.len());
        assert!(c.ids.len() <= Counted::LIMIT);
        assert!(c.insert("m0")); // oldest dropped, so it would count again
    }

    #[test]
    fn iso_utc_matches_claude_timestamp_format() {
        let t = std::time::UNIX_EPOCH + std::time::Duration::from_millis(1_793_235_723_456);
        assert_eq!(iso_utc(t), "2026-10-29T01:02:03.456Z");
        assert_eq!(iso_utc(std::time::UNIX_EPOCH), "1970-01-01T00:00:00.000Z");
    }
}

/// Expected transcript path for a Claude Code session when the hook payload
/// didn't carry `transcript_path`: `~/.claude/projects/<sanitized-cwd>/<id>.jsonl`
/// where the sanitized cwd replaces every separator with `-`.
pub fn inferred_path(session_id: &str, cwd: &str) -> Option<String> {
    let home = dirs::home_dir()?;
    let sanitized: String = cwd
        .chars()
        .map(|c| if c == '/' || c == '\\' || c == ':' { '-' } else { c })
        .collect();
    Some(format!(
        "{}/.claude/projects/{}/{}.jsonl",
        home.to_string_lossy(),
        sanitized,
        session_id
    ))
}

/// Sums new Codex token usage (fresh input minus cached, plus output) appended
/// to a rollout JSONL since the previous call, so Codex earns token XP like
/// Claude. Offset-based + serialised, like `new_usage_tokens`.
pub fn new_codex_usage_tokens(path: &str) -> Option<i64> {
    let mut guard = USAGE_OFFSETS.lock().ok()?;
    let offsets = guard.get_or_insert_with(HashMap::new);

    let mut f = std::fs::File::open(path).ok()?;
    let size = f.seek(SeekFrom::End(0)).ok()?;
    let mut start = offsets.get(path).copied().unwrap_or(0);
    if start > size {
        start = 0;
    }
    if size <= start {
        return Some(0);
    }
    f.seek(SeekFrom::Start(start)).ok()?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf).ok()?;
    let nl = buf.iter().rposition(|&b| b == b'\n')?;
    let consumable = &buf[..=nl];
    offsets.insert(path.to_string(), start + consumable.len() as u64);
    let text = String::from_utf8_lossy(consumable);
    let mut total: i64 = 0;
    for line in text.lines() {
        if !line.contains("\"last_token_usage\"") {
            continue;
        }
        let Ok(json) = serde_json::from_str::<Value>(line.trim()) else { continue };
        if let Some(last) = json
            .get("payload")
            .and_then(|p| p.get("info"))
            .and_then(|i| i.get("last_token_usage"))
        {
            let input = last.get("input_tokens").and_then(|v| v.as_i64()).unwrap_or(0);
            let cached = last.get("cached_input_tokens").and_then(|v| v.as_i64()).unwrap_or(0);
            let output = last.get("output_tokens").and_then(|v| v.as_i64()).unwrap_or(0);
            total += (input - cached).max(0) + output;
        }
    }
    Some(total)
}

/// Locates a Codex session's rollout file under ~/.codex/sessions. Primary: a
/// filename containing the session id. Fallback: the newest rollout whose first
/// line's `payload.cwd` matches `cwd`.
pub fn codex_rollout_path(session_id: &str, cwd: Option<&str>) -> Option<String> {
    fn norm(p: &str) -> String {
        p.trim_end_matches(['/', '\\']).to_lowercase()
    }
    fn walk(
        dir: &std::path::Path,
        session_id: &str,
        out: &mut Vec<(std::path::PathBuf, std::time::SystemTime)>,
    ) -> Option<std::path::PathBuf> {
        for entry in std::fs::read_dir(dir).ok()?.flatten() {
            let p = entry.path();
            if p.is_dir() {
                if let Some(hit) = walk(&p, session_id, out) {
                    return Some(hit);
                }
            } else if let Some(name) = p.file_name().and_then(|n| n.to_str()) {
                if name.ends_with(".jsonl") && name.contains("rollout-") {
                    if name.contains(session_id) {
                        return Some(p);
                    }
                    let m = entry
                        .metadata()
                        .ok()
                        .and_then(|md| md.modified().ok())
                        .unwrap_or(std::time::UNIX_EPOCH);
                    out.push((p, m));
                }
            }
        }
        None
    }
    let root = dirs::home_dir()?.join(".codex").join("sessions");
    let mut candidates: Vec<(std::path::PathBuf, std::time::SystemTime)> = Vec::new();
    if let Some(hit) = walk(&root, session_id, &mut candidates) {
        return Some(hit.to_string_lossy().into_owned());
    }
    let cwd = cwd?;
    if cwd.trim().is_empty() {
        return None;
    }
    let target = norm(cwd);
    candidates.sort_by(|a, b| b.1.cmp(&a.1));
    for (p, _) in candidates.iter().take(40) {
        let Some(line) = first_line(p) else { continue };
        let Ok(json) = serde_json::from_str::<Value>(line.trim()) else { continue };
        if let Some(c) = json.get("payload").and_then(|pl| pl.get("cwd")).and_then(|v| v.as_str()) {
            if norm(c) == target {
                return Some(p.to_string_lossy().into_owned());
            }
        }
    }
    None
}

fn first_line(path: &std::path::Path) -> Option<String> {
    let mut f = std::fs::File::open(path).ok()?;
    let mut buf = vec![0u8; 4096];
    let n = f.read(&mut buf).ok()?;
    buf.truncate(n);
    String::from_utf8_lossy(&buf).lines().next().map(|l| l.to_string())
}

/// Path to a subagent's transcript for a Claude/Droid `SubagentStop`. Claude
/// stores them at `<parent-without-.jsonl>/subagents/<agent-id>.jsonl`.
pub fn subagent_transcript_path(parent: &str, agent_id: &str) -> String {
    let dir = std::path::Path::new(parent).with_extension("");
    dir.join("subagents")
        .join(format!("{}.jsonl", agent_id))
        .to_string_lossy()
        .into_owned()
}

/// Conversation title: a Claude "summary" event (cached), else the first human
/// user message (≤60 chars, provisional).
pub fn title(path: &str) -> Option<String> {
    {
        let cache = SUMMARY_CACHE.lock().ok()?;
        if let Some(hit) = cache.as_ref().and_then(|m| m.get(path)) {
            return Some(hit.clone());
        }
    }
    let (result, is_summary) = read_title(path)?;
    if is_summary {
        if let Ok(mut cache) = SUMMARY_CACHE.lock() {
            cache.get_or_insert_with(HashMap::new).insert(path.to_string(), result.clone());
        }
    }
    Some(result)
}

fn read_title(path: &str) -> Option<(String, bool)> {
    // First 32 KB covers the summary event, which appears early.
    let mut f = std::fs::File::open(path).ok()?;
    let mut buf = vec![0u8; 32_768];
    let n = f.read(&mut buf).ok()?;
    buf.truncate(n);
    // Truncate to the last newline so we never split a multi-byte char.
    if n == 32_768 {
        if let Some(nl) = buf.iter().rposition(|&b| b == b'\n') {
            buf.truncate(nl + 1);
        }
    }
    let text = String::from_utf8_lossy(&buf);

    let mut first_user: Option<String> = None;
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let Ok(json) = serde_json::from_str::<Value>(trimmed) else { continue };
        match json.get("type").and_then(|t| t.as_str()) {
            Some("summary") => {
                if let Some(s) = json.get("summary").and_then(|s| s.as_str()) {
                    if !s.trim().is_empty() {
                        return Some((s.trim().to_string(), true));
                    }
                }
            }
            Some("user") if first_user.is_none() => {
                first_user = extract_user_text(&json);
            }
            _ => {}
        }
    }
    first_user.map(|t| (t, false))
}

fn extract_user_text(json: &Value) -> Option<String> {
    let message = json.get("message")?;
    if let Some(blocks) = message.get("content").and_then(|c| c.as_array()) {
        for block in blocks {
            if block.get("type").and_then(|t| t.as_str()) == Some("text") {
                if let Some(raw) = block.get("text").and_then(|t| t.as_str()) {
                    if let Some(clean) = human_readable(raw) {
                        return Some(clean);
                    }
                }
            }
        }
        return None;
    }
    message.get("content").and_then(|c| c.as_str()).and_then(human_readable)
}

/// Trimmed + capped at 60 chars; rejects XML-style system injections.
fn human_readable(text: &str) -> Option<String> {
    let trimmed = text.trim();
    if trimmed.is_empty() || trimmed.starts_with('<') {
        return None;
    }
    Some(trimmed.chars().take(60).collect())
}

/// Raw text of the most recent assistant message (last 128 KB, capped 400 chars).
pub fn latest_assistant_text(path: &str) -> Option<String> {
    let mut f = std::fs::File::open(path).ok()?;
    let size = f.seek(SeekFrom::End(0)).ok()?;
    let max: u64 = 131_072;
    let start = size.saturating_sub(max);
    f.seek(SeekFrom::Start(start)).ok()?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf).ok()?;
    let text = String::from_utf8_lossy(&buf);

    for line in text.lines().rev() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let Ok(json) = serde_json::from_str::<Value>(trimmed) else { continue };
        if json.get("type").and_then(|t| t.as_str()) != Some("assistant") {
            continue;
        }
        if let Some(t) = extract_assistant_text(&json) {
            return Some(t.trim().chars().take(400).collect());
        }
    }
    None
}

fn extract_assistant_text(json: &Value) -> Option<String> {
    let message = json.get("message")?;
    if let Some(blocks) = message.get("content").and_then(|c| c.as_array()) {
        let text: Vec<&str> = blocks
            .iter()
            .filter(|b| b.get("type").and_then(|t| t.as_str()) == Some("text"))
            .filter_map(|b| b.get("text").and_then(|t| t.as_str()))
            .collect();
        let joined = text.join("\n");
        if joined.trim().is_empty() {
            return None;
        }
        return Some(joined);
    }
    message.get("content").and_then(|c| c.as_str()).map(String::from)
}

// ---- QuestionDetector ------------------------------------------------------

const QUESTION_STARTERS: &[&str] = &[
    "which ", "what ", "how ", "should i", "do you", "want me to",
    "shall i", "would you", "can you", "could you", "are you",
];

const OPTIONAL_FOLLOW_UPS: &[&str] = &[
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
];

/// True when the LAST sentence is a direct question or request for direction.
/// Completion summaries with an optional "let me know if…" tail count as done.
pub fn looks_like_question(text: &str) -> bool {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return false;
    }
    let last = last_sentence(trimmed).to_lowercase();
    if last.is_empty() {
        return false;
    }
    if OPTIONAL_FOLLOW_UPS.iter().any(|p| last.contains(p)) {
        return false;
    }
    last.ends_with('?') || QUESTION_STARTERS.iter().any(|s| last.starts_with(s))
}

fn last_sentence(text: &str) -> String {
    let normalized = text.replace('\n', " ");
    let normalized = normalized.trim();
    let mut segments: Vec<String> = Vec::new();
    let mut current = String::new();
    for ch in normalized.chars() {
        current.push(ch);
        if ch == '.' || ch == '!' || ch == '?' {
            let s = current.trim().to_string();
            if !s.is_empty() {
                segments.push(s);
            }
            current.clear();
        }
    }
    let rest = current.trim();
    if !rest.is_empty() {
        segments.push(rest.to_string());
    }
    segments.pop().unwrap_or_else(|| normalized.to_string())
}
