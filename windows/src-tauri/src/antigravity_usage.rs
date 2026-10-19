//! Antigravity (`agy` CLI and IDE) token usage -> pet XP.
//!
//! Hook payloads carry no token counts, so usage is read from disk:
//!
//! * CLI: the payload's `transcriptPath` (`transcript_full.jsonl`) has one JSON
//!   object per step; model steps carry `input_tokens`, `cache_read_tokens` and
//!   `output_tokens`. Read the appended bytes, like the Codex rollout reader.
//! * IDE: its transcripts carry NO token fields, but the conversation DB next to
//!   it (`<gemini>/antigravity-ide/conversations/<id>.db`, table `steps`, column
//!   `metadata`, protobuf field 9) does: 9.2 = input tokens, 9.3 = output tokens
//!   (absent when 0). Verified equal to the CLI transcript on 134 model steps.
//!   `new_usage_tokens` picks the DB for IDE transcripts (path under `antigravity-ide`).
//!
//! Counted as input + output. agy's `input_tokens` excludes cached tokens
//! (`cache_read_tokens` / DB field 9.5 are reported separately), so nothing is
//! subtracted.
//!
//! The first time a conversation is seen only the current request is counted
//! (CLI: from the last `USER_INPUT` step; IDE: model steps after the last user
//! step cannot be told apart, so only steps added after the first sighting
//! count), so resuming a long conversation never feeds its whole history.
//!
//! simplify: a CLI transcript is read whole once, then only its appended tail.
//! The IDE DB is re-read per event (small files, read-only, shared WAL).

use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

// Byte offset already consumed per transcript path.
static OFFSETS: Mutex<Option<HashMap<String, u64>>> = Mutex::new(None);

fn contains(hay: &[u8], needle: &[u8]) -> bool {
    hay.windows(needle.len()).any(|w| w == needle)
}

/// Tokens one transcript step is worth (0 for steps without usage). agy's
/// `input_tokens` EXCLUDES the cache (real steps have cache_read > input, e.g.
/// input 4876 / cache_read 8134), so cache reads are simply not counted.
fn step_tokens(v: &Value) -> i64 {
    let get = |k: &str| v.get(k).and_then(|x| x.as_i64()).unwrap_or(0);
    get("input_tokens").max(0) + get("output_tokens").max(0)
}

/// Sum of the tokens in complete JSONL lines.
pub fn sum_tokens(chunk: &[u8]) -> i64 {
    chunk
        .split(|b| *b == b'\n')
        .filter(|l| contains(l, b"\"input_tokens\"") || contains(l, b"\"output_tokens\""))
        .filter_map(|l| serde_json::from_slice::<Value>(l).ok())
        .map(|v| step_tokens(&v))
        .sum()
}

/// Byte offset of the line holding the last `USER_INPUT` step (0 if none):
/// where the current request starts.
pub fn current_request_start(buf: &[u8]) -> usize {
    let mut best = 0;
    let mut pos = 0;
    for line in buf.split_inclusive(|b| *b == b'\n') {
        if contains(line, b"USER_INPUT") {
            if let Ok(v) = serde_json::from_slice::<Value>(line) {
                if v.get("type").and_then(|t| t.as_str()) == Some("USER_INPUT") {
                    best = pos;
                }
            }
        }
        pos += line.len();
    }
    best
}

// Conversation DB steps already counted, per DB path (IDE).
static SEEN_STEPS: Mutex<Option<HashMap<String, HashSet<i64>>>> = Mutex::new(None);

const STEP_USER_INPUT: i64 = 14; // steps.step_type of a user message

fn read_varint(b: &[u8], i: &mut usize) -> Option<u64> {
    let mut r: u64 = 0;
    let mut shift = 0;
    loop {
        let x = *b.get(*i)?;
        *i += 1;
        r |= ((x & 0x7f) as u64).checked_shl(shift)?;
        if x < 0x80 {
            return Some(r);
        }
        shift += 7;
        if shift > 63 {
            return None;
        }
    }
}

/// Skips one protobuf field value of the given wire type.
fn skip(b: &[u8], i: &mut usize, wire: u64) -> Option<()> {
    match wire {
        0 => { read_varint(b, i)?; }
        1 => *i = i.checked_add(8)?,
        2 => { let l = read_varint(b, i)? as usize; *i = i.checked_add(l)?; }
        5 => *i = i.checked_add(4)?,
        _ => return None,
    }
    if *i > b.len() { None } else { Some(()) }
}

/// (input, output) tokens from a `steps.metadata` protobuf: message field 9
/// holds 2 = input and 3 = output (3 is omitted when 0). None if the step has
/// no usage message.
pub fn parse_usage(md: &[u8]) -> Option<(i64, i64)> {
    let mut i = 0;
    while i < md.len() {
        let key = read_varint(md, &mut i)?;
        let (field, wire) = (key >> 3, key & 7);
        if field == 9 && wire == 2 {
            let len = read_varint(md, &mut i)? as usize;
            let end = i.checked_add(len)?;
            let sub = md.get(i..end)?;
            let (mut input, mut output, mut seen) = (0i64, 0i64, false);
            let mut j = 0;
            while j < sub.len() {
                let k = read_varint(sub, &mut j)?;
                let (f, w) = (k >> 3, k & 7);
                if w == 0 {
                    let v = read_varint(sub, &mut j)? as i64;
                    if f == 2 { input = v; seen = true; }
                    if f == 3 { output = v; }
                } else {
                    skip(sub, &mut j, w)?;
                }
            }
            return if seen { Some((input, output)) } else { None };
        }
        skip(md, &mut i, wire)?;
    }
    None
}

/// `<root>/antigravity-ide/conversations/<id>.db` for an IDE transcript path
/// `<root>/antigravity-ide/brain/<id>/.system_generated/logs/<file>`; None for
/// anything else (the CLI lives under `antigravity-cli`).
pub fn ide_db_for(transcript: &str) -> Option<PathBuf> {
    let conv = Path::new(transcript).parent()?.parent()?.parent()?;
    let brain = conv.parent()?;
    let root = brain.parent()?;
    let is = |p: &Path, name: &str| p.file_name().map(|n| n.to_string_lossy().eq_ignore_ascii_case(name)).unwrap_or(false);
    if !is(brain, "brain") || !is(root, "antigravity-ide") {
        return None;
    }
    let id = conv.file_name()?.to_string_lossy().into_owned();
    if id.is_empty() || id.contains("..") {
        return None;
    }
    Some(root.join("conversations").join(format!("{id}.db")))
}

/// (idx, step_type, metadata) of every step, read-only.
fn read_steps(db: &Path) -> Option<Vec<(i64, i64, Option<Vec<u8>>)>> {
    use rusqlite::{Connection, OpenFlags};
    let conn = Connection::open_with_flags(db, OpenFlags::SQLITE_OPEN_READ_ONLY).ok()?;
    let _ = conn.busy_timeout(std::time::Duration::from_millis(500));
    let mut stmt = conn.prepare("SELECT idx, step_type, metadata FROM steps ORDER BY idx").ok()?;
    let rows = stmt
        .query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?, r.get::<_, Option<Vec<u8>>>(2)?)))
        .ok()?;
    Some(rows.filter_map(|r| r.ok()).collect())
}

/// New tokens in the IDE conversation DB since the previous call. A step is
/// counted once, whenever its usage appears (a step can exist before its usage
/// is written). On first sighting everything up to the last user message is
/// history and only marked as seen, so resuming a conversation feeds nothing old.
pub fn new_db_tokens(db: &Path) -> Option<i64> {
    let steps = read_steps(db)?;
    let key = db.to_string_lossy().into_owned();
    let mut guard = SEEN_STEPS.lock().ok()?;
    let all = guard.get_or_insert_with(HashMap::new);
    let first = !all.contains_key(&key);
    let seen = all.entry(key).or_default();
    let last_user = steps.iter().filter(|s| s.1 == STEP_USER_INPUT).map(|s| s.0).max().unwrap_or(-1);
    let mut total = 0;
    for (idx, _, md) in &steps {
        let Some((input, output)) = md.as_deref().and_then(parse_usage) else { continue };
        if seen.contains(idx) {
            continue;
        }
        seen.insert(*idx);
        if first && *idx < last_user {
            continue; // history from before the current request
        }
        total += input.max(0) + output.max(0);
    }
    Some(total)
}

/// New tokens for one hook event: the IDE reads its conversation DB (its
/// transcripts have no token fields), the CLI reads its transcript.
pub fn new_usage_tokens(path: &str) -> Option<i64> {
    match ide_db_for(path) {
        Some(db) => new_db_tokens(&db),
        None => new_transcript_tokens(path),
    }
}

/// New tokens appended to the CLI transcript since the previous call. `None` if
/// the file is unreadable, `Some(0)` if nothing new. Serialised across threads so
/// two events for one conversation cannot both consume the same bytes.
pub fn new_transcript_tokens(path: &str) -> Option<i64> {
    let mut guard = OFFSETS.lock().ok()?;
    let offsets = guard.get_or_insert_with(HashMap::new);

    let mut f = std::fs::File::open(path).ok()?;
    let size = f.seek(SeekFrom::End(0)).ok()?;
    let known = offsets.get(path).copied();
    let mut start = known.unwrap_or(0);
    if start > size {
        start = 0; // file replaced: start over
    }
    if known.is_some() && size <= start {
        return Some(0);
    }
    f.seek(SeekFrom::Start(start)).ok()?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf).ok()?;

    let skip = if known.is_none() { current_request_start(&buf) } else { 0 };
    let body = &buf[skip..];
    let Some(nl) = body.iter().rposition(|&b| b == b'\n') else {
        // No complete line yet: remember where the request starts, read later.
        offsets.insert(path.to_string(), start + skip as u64);
        return Some(0);
    };
    let consumable = &body[..=nl];
    offsets.insert(path.to_string(), start + (skip + consumable.len()) as u64);
    Some(sum_tokens(consumable))
}

#[cfg(test)]
mod tests {
    use super::*;

    // Shapes copied from a real transcript_full.jsonl (agy 2026-10-09).
    const USER: &str = r#"{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"2026-10-09T03:59:10Z","content":"hi"}"#;
    const PLAN1: &str = r#"{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-10-09T03:59:12Z","input_tokens":11641,"cache_read_tokens":0,"output_tokens":58,"tool_calls":[{"name":"run_command"}]}"#;
    const TOOL: &str = r#"{"step_index":2,"source":"MODEL","type":"GENERIC","status":"DONE","content":"output mentions input_tokens and USER_INPUT"}"#;
    const PLAN2: &str = r#"{"step_index":3,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","input_tokens":11786,"cache_read_tokens":0,"output_tokens":1,"content":"done"}"#;

    fn tmp(name: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("agy-usage-{}-{}", std::process::id(), name));
        let _ = std::fs::remove_file(&d);
        d
    }

    #[test]
    fn sums_input_plus_output_over_planner_steps() {
        let t = format!("{USER}\n{PLAN1}\n{TOOL}\n{PLAN2}\n");
        assert_eq!(sum_tokens(t.as_bytes()), 11641 + 58 + 11786 + 1);
    }

    #[test]
    fn cache_reads_are_not_added_and_not_subtracted() {
        // real shape: input excludes cache (cache_read > input)
        let l = r#"{"type":"PLANNER_RESPONSE","input_tokens":4876,"cache_read_tokens":8134,"output_tokens":10151}"#;
        assert_eq!(sum_tokens(format!("{l}\n").as_bytes()), 4876 + 10151);
    }

    #[test]
    fn text_mentioning_the_keys_is_ignored() {
        assert_eq!(sum_tokens(format!("{TOOL}\n").as_bytes()), 0);
        assert_eq!(sum_tokens(b"not json input_tokens\n{\"input_tokens\":3"), 0);
    }

    #[test]
    fn request_starts_at_last_user_input() {
        let old = format!("{USER}\n{PLAN1}\n");
        let t = format!("{old}{USER}\n{PLAN2}\n");
        assert_eq!(current_request_start(t.as_bytes()), old.len());
        assert_eq!(current_request_start(format!("{PLAN1}\n").as_bytes()), 0);
        // a tool output that merely mentions USER_INPUT is not a request start
        assert_eq!(current_request_start(format!("{USER}\n{TOOL}\n").as_bytes()), 0);
    }

    #[test]
    fn feeds_only_new_tokens_and_never_twice() {
        let p = tmp("incr");
        std::fs::write(&p, format!("{USER}\n")).unwrap();
        let ps = p.to_str().unwrap();
        assert_eq!(new_transcript_tokens(ps), Some(0));
        let mut s = format!("{USER}\n{PLAN1}\n{TOOL}\n");
        std::fs::write(&p, &s).unwrap();
        assert_eq!(new_transcript_tokens(ps), Some(11641 + 58));
        assert_eq!(new_transcript_tokens(ps), Some(0)); // same bytes again: nothing
        s.push_str(PLAN2);
        s.push('\n');
        std::fs::write(&p, &s).unwrap();
        assert_eq!(new_transcript_tokens(ps), Some(11786 + 1));
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn resumed_conversation_does_not_feed_history() {
        let p = tmp("resume");
        // an old request (with usage) then the new request's user step
        std::fs::write(&p, format!("{USER}\n{PLAN1}\n{TOOL}\n{USER}\n")).unwrap();
        let ps = p.to_str().unwrap();
        assert_eq!(new_transcript_tokens(ps), Some(0));
        std::fs::write(&p, format!("{USER}\n{PLAN1}\n{TOOL}\n{USER}\n{PLAN2}\n")).unwrap();
        assert_eq!(new_transcript_tokens(ps), Some(11786 + 1));
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn first_sighting_mid_request_counts_that_request_so_far() {
        let p = tmp("mid");
        std::fs::write(&p, format!("{USER}\n{PLAN1}\n{TOOL}\n")).unwrap();
        assert_eq!(new_transcript_tokens(p.to_str().unwrap()), Some(11641 + 58));
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn partial_last_line_waits_for_its_newline() {
        let p = tmp("partial");
        let ps = p.to_str().unwrap();
        std::fs::write(&p, format!("{USER}\n")).unwrap();
        assert_eq!(new_transcript_tokens(ps), Some(0));
        std::fs::write(&p, format!("{USER}\n{}", &PLAN1[..60])).unwrap();
        assert_eq!(new_transcript_tokens(ps), Some(0));
        std::fs::write(&p, format!("{USER}\n{PLAN1}\n")).unwrap();
        assert_eq!(new_transcript_tokens(ps), Some(11641 + 58));
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn replaced_file_starts_over_and_missing_file_is_none() {
        let p = tmp("replace");
        let ps = p.to_str().unwrap();
        std::fs::write(&p, format!("{USER}\n{PLAN1}\n{PLAN1}\n")).unwrap();
        assert_eq!(new_transcript_tokens(ps), Some(2 * (11641 + 58)));
        std::fs::write(&p, format!("{USER}\n{PLAN2}\n")).unwrap(); // shorter: replaced
        assert_eq!(new_transcript_tokens(ps), Some(11786 + 1));
        let _ = std::fs::remove_file(&p);
        assert_eq!(new_transcript_tokens("Z:/no/such/transcript.jsonl"), None);
    }

    // ---- IDE (conversation DB) ----
    // metadata of a real model step: field 9 = {1:1318, 2:15283, 3:2080, 6:24, 9:927, 10:1153}
    fn usage_md(input: u64, output: Option<u64>) -> Vec<u8> {
        fn v(out: &mut Vec<u8>, mut n: u64) { loop { let b = (n & 0x7f) as u8; n >>= 7; if n == 0 { out.push(b); break } out.push(b | 0x80) } }
        let mut sub = vec![];
        v(&mut sub, 1 << 3); v(&mut sub, 1318);
        v(&mut sub, 2 << 3); v(&mut sub, input);
        if let Some(o) = output { v(&mut sub, 3 << 3); v(&mut sub, o); }
        v(&mut sub, 6 << 3); v(&mut sub, 24);
        let mut md = vec![];
        v(&mut md, (3 << 3) | 2); v(&mut md, 3); md.extend_from_slice(&[0x0a, 0x01, 0x7a]); // unrelated field 3
        v(&mut md, (9 << 3) | 2); v(&mut md, sub.len() as u64); md.extend(sub);
        md
    }

    #[test]
    fn parses_input_and_output_from_field_9() {
        assert_eq!(parse_usage(&usage_md(15283, Some(2080))), Some((15283, 2080)));
        assert_eq!(parse_usage(&usage_md(13051, None)), Some((13051, 0))); // output 0 is omitted
        assert_eq!(parse_usage(&[0x08, 0x01]), None); // no usage message
        assert_eq!(parse_usage(&[0x4a, 0x7f, 0x10]), None); // truncated: never panics
        assert_eq!(parse_usage(&[]), None);
    }

    #[test]
    fn ide_transcript_maps_to_its_conversation_db() {
        let t = "C:/Users/H/.gemini/antigravity-ide/brain/63fc7f9e-1/.system_generated/logs/transcript_full.jsonl";
        let db = ide_db_for(t).unwrap();
        assert_eq!(db, Path::new("C:/Users/H/.gemini/antigravity-ide/conversations/63fc7f9e-1.db"));
        // CLI transcripts and arbitrary paths are not IDE
        assert!(ide_db_for("C:/Users/H/.gemini/antigravity-cli/brain/x/.system_generated/logs/t.jsonl").is_none());
        assert!(ide_db_for("/tmp/transcript_full.jsonl").is_none());
        assert!(ide_db_for("").is_none());
    }

    fn make_db(path: &Path, steps: &[(i64, i64, Option<Vec<u8>>)]) {
        let _ = std::fs::remove_file(path);
        let c = rusqlite::Connection::open(path).unwrap();
        c.execute("CREATE TABLE steps (idx integer, step_type integer, metadata blob)", []).unwrap();
        for (i, t, m) in steps {
            c.execute("INSERT INTO steps VALUES (?1,?2,?3)", rusqlite::params![i, t, m]).unwrap();
        }
    }
    fn add_step(path: &Path, idx: i64, t: i64, m: Option<Vec<u8>>) {
        let c = rusqlite::Connection::open(path).unwrap();
        c.execute("INSERT INTO steps VALUES (?1,?2,?3)", rusqlite::params![idx, t, m]).unwrap();
    }

    #[test]
    fn db_counts_only_new_model_steps_once() {
        let p = tmp("db1");
        make_db(&p, &[(0, 14, None), (1, 15, Some(usage_md(1000, Some(10))))]);
        // first sighting: step 1 is before the last user message? no user after it -> counted
        assert_eq!(new_db_tokens(&p), Some(1010));
        assert_eq!(new_db_tokens(&p), Some(0)); // same rows: nothing
        add_step(&p, 2, 14, None);
        add_step(&p, 3, 15, Some(usage_md(2000, None)));
        assert_eq!(new_db_tokens(&p), Some(2000));
        assert_eq!(new_db_tokens(&p), Some(0));
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn db_resume_skips_history_before_last_user_step() {
        let p = tmp("db2");
        // old request (usage) then a new user message: history is not fed
        make_db(&p, &[(0, 14, None), (1, 15, Some(usage_md(5000, Some(50)))), (2, 14, None)]);
        assert_eq!(new_db_tokens(&p), Some(0));
        add_step(&p, 3, 15, Some(usage_md(700, Some(7))));
        assert_eq!(new_db_tokens(&p), Some(707));
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn db_step_whose_usage_arrives_later_is_counted_then() {
        let p = tmp("db3");
        make_db(&p, &[(0, 14, None), (1, 15, None)]); // model step exists, usage not written yet
        assert_eq!(new_db_tokens(&p), Some(0));
        let c = rusqlite::Connection::open(&p).unwrap();
        c.execute("UPDATE steps SET metadata=?1 WHERE idx=1", rusqlite::params![usage_md(300, Some(3))]).unwrap();
        drop(c);
        assert_eq!(new_db_tokens(&p), Some(303));
        assert_eq!(new_db_tokens(&p), Some(0));
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn db_missing_or_not_a_db_is_none() {
        assert_eq!(new_db_tokens(Path::new("Z:/no/such.db")), None);
        let p = tmp("notdb");
        std::fs::write(&p, b"this is not sqlite").unwrap();
        assert_eq!(new_db_tokens(&p), None);
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn dispatcher_uses_db_for_ide_and_transcript_for_cli() {
        let root = std::env::temp_dir().join(format!("agy-ide-{}", std::process::id()));
        let conv = root.join("antigravity-ide").join("conversations");
        let logs = root.join("antigravity-ide").join("brain").join("c1").join(".system_generated").join("logs");
        std::fs::create_dir_all(&conv).unwrap();
        std::fs::create_dir_all(&logs).unwrap();
        make_db(&conv.join("c1.db"), &[(0, 14, None), (1, 15, Some(usage_md(111, Some(9))))]);
        let t = logs.join("transcript_full.jsonl");
        std::fs::write(&t, "{\"type\":\"USER_INPUT\"}\n").unwrap(); // IDE transcript: no tokens
        assert_eq!(new_usage_tokens(t.to_str().unwrap()), Some(120));
        // a CLI-style path still goes through the transcript reader
        let cli = std::env::temp_dir().join(format!("agy-cli-{}.jsonl", std::process::id()));
        std::fs::write(&cli, format!("{USER}\n{PLAN1}\n")).unwrap();
        assert_eq!(new_usage_tokens(cli.to_str().unwrap()), Some(11641 + 58));
        let _ = std::fs::remove_dir_all(&root);
        let _ = std::fs::remove_file(&cli);
    }
}
