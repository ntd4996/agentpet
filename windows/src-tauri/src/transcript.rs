//! Reads Claude Code transcripts (JSONL) , a port of the macOS app's
//! TranscriptReader + QuestionDetector. Used to (1) name sessions after the
//! conversation, and (2) detect when Claude ended its turn by ASKING the user
//! something, so a `Stop` that looks "done" is corrected to "waiting".

use serde_json::Value;
use std::collections::HashMap;
use std::io::{Read, Seek, SeekFrom};
use std::sync::Mutex;

// Summary-based titles are final; first-user-message titles are provisional
// (a later summary supersedes them), so only summaries are cached.
static SUMMARY_CACHE: Mutex<Option<HashMap<String, String>>> = Mutex::new(None);
// Byte offset already consumed by `new_usage_tokens` per transcript path, so
// repeated reads only sum the freshly-appended usage (a port of the macOS
// TranscriptReader.usageOffsets).
static USAGE_OFFSETS: Mutex<Option<HashMap<String, u64>>> = Mutex::new(None);
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

/// Sums Claude model usage tokens (input + output) appended to the transcript
/// since the previous call for the same path. First call consumes the whole
/// file. `None` if unreadable, `0` if no new usage lines appeared. Feeds the pet.
pub fn new_usage_tokens(path: &str) -> Option<i64> {
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
        return Some(0);
    }
    f.seek(SeekFrom::Start(start)).ok()?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf).ok()?;
    // Consume up to the last full line; a partial trailing line stays for later.
    let nl = buf.iter().rposition(|&b| b == b'\n')?;
    let consumable = &buf[..=nl];
    offsets.insert(path.to_string(), start + consumable.len() as u64);
    let text = String::from_utf8_lossy(consumable);
    let mut total: i64 = 0;
    for line in text.lines() {
        if !line.contains("\"usage\"") {
            continue; // fast reject: most lines carry no usage object
        }
        let Ok(json) = serde_json::from_str::<Value>(line.trim()) else { continue };
        if let Some(usage) = json.get("message").and_then(|m| m.get("usage")) {
            total += usage.get("input_tokens").and_then(|v| v.as_i64()).unwrap_or(0);
            total += usage.get("output_tokens").and_then(|v| v.as_i64()).unwrap_or(0);
        }
    }
    Some(total)
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
