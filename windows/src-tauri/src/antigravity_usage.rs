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
//! Cost control (the DB grows with the conversation, and hook events come in
//! bursts):
//! * IDE: only steps after the last user message are read on first sight, then
//!   only a small window behind the newest step (`DB_WINDOW`, enough for a step
//!   whose usage is written a little after the step itself), never the whole
//!   table again.
//! * Events for one path are coalesced (`coalesce`): at most one scan runs per
//!   path and a burst of events collapses into one follow-up scan.
//! * CLI: the first read of a transcript is capped (`FIRST_READ_CAP`), because
//!   the path comes from the localhost hook payload.
//! * Per-path state is bounded (`MAX_TRACKED`, least recently used goes first),
//!   so a long-running app does not grow without limit.
//!
//! simplify: a CLI transcript is read once (capped), then only its appended
//! tail. A usage that appears more than `DB_WINDOW` steps late is missed.

use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

/// First read of a transcript looks only at its last few MB (the current
/// request is at the end; older history is never fed anyway).
const FIRST_READ_CAP: u64 = 4 * 1024 * 1024;
/// How many steps behind the newest one are re-read to catch late usage.
const DB_WINDOW: i64 = 64;
/// Paths tracked at once (offsets / DB state). Oldest-used is evicted first.
const MAX_TRACKED: usize = 64;
/// Wait before a coalesced scan so a burst of hook events becomes one read.
const DEBOUNCE: std::time::Duration = std::time::Duration::from_millis(250);

/// A small LRU-ish map: `touch` stamps entries, `trim` drops the oldest ones.
struct Tracked<V> {
    map: HashMap<String, (V, u64)>,
    tick: u64,
}
impl<V> Tracked<V> {
    fn new() -> Self { Tracked { map: HashMap::new(), tick: 0 } }
    fn get(&mut self, key: &str) -> Option<&mut V> {
        self.tick += 1;
        let t = self.tick;
        self.map.get_mut(key).map(|e| { e.1 = t; &mut e.0 })
    }
    fn insert(&mut self, key: String, v: V) {
        self.tick += 1;
        self.map.insert(key, (v, self.tick));
        while self.map.len() > MAX_TRACKED {
            let oldest = self.map.iter().min_by_key(|(_, e)| e.1).map(|(k, _)| k.clone());
            match oldest { Some(k) => { self.map.remove(&k); } None => break }
        }
    }
}

// Byte offset already consumed per transcript path.
static OFFSETS: Mutex<Option<Tracked<u64>>> = Mutex::new(None);

// Paths with a scan running; the flag says "another event arrived meanwhile".
static RUNNING: Mutex<Option<HashMap<String, bool>>> = Mutex::new(None);

/// Runs `scan` for `path` on the current thread unless one is already running
/// for it. Events that arrive while it runs only set a flag, and the running
/// call loops once more (after `DEBOUNCE`), so a burst costs two scans at most
/// and scans of the same path never overlap. `scan` returns tokens to feed.
pub fn coalesce(path: &str, scan: impl Fn() -> Option<i64>, feed: impl Fn(i64)) {
    {
        let Ok(mut g) = RUNNING.lock() else { return };
        let m = g.get_or_insert_with(HashMap::new);
        if let Some(rerun) = m.get_mut(path) {
            *rerun = true;
            return;
        }
        m.insert(path.to_string(), false);
    }
    loop {
        std::thread::sleep(DEBOUNCE);
        if let Some(t) = scan() {
            if t > 0 { feed(t); }
        }
        let Ok(mut g) = RUNNING.lock() else { return };
        let m = g.get_or_insert_with(HashMap::new);
        match m.get_mut(path) {
            Some(rerun) if *rerun => *rerun = false,
            _ => { m.remove(path); return; }
        }
    }
}

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

/// What is known about one conversation DB.
struct DbState {
    /// First idx ever read (history before it was never fed and is never read).
    floor: i64,
    /// Newest idx seen so far.
    max_idx: i64,
    /// Steps in the window whose usage was already counted.
    seen: HashSet<i64>,
}

// Conversation DB state per DB path (IDE).
static DBS: Mutex<Option<Tracked<DbState>>> = Mutex::new(None);

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

type Step = (i64, i64, Option<Vec<u8>>);

/// Idx of the last user message, or -1 when there is none (cheap aggregate).
fn last_user_idx(db: &Path) -> Option<i64> {
    let conn = open_ro(db)?;
    conn.query_row("SELECT COALESCE(MAX(idx), -1) FROM steps WHERE step_type = ?1", [STEP_USER_INPUT], |r| r.get(0)).ok()
}

fn open_ro(db: &Path) -> Option<rusqlite::Connection> {
    use rusqlite::{Connection, OpenFlags};
    let conn = Connection::open_with_flags(db, OpenFlags::SQLITE_OPEN_READ_ONLY).ok()?;
    let _ = conn.busy_timeout(std::time::Duration::from_millis(500));
    Some(conn)
}

/// (idx, step_type, metadata) of the steps with `idx >= low`, read-only.
fn read_steps_from(db: &Path, low: i64) -> Option<Vec<Step>> {
    let conn = open_ro(db)?;
    let mut stmt = conn.prepare("SELECT idx, step_type, metadata FROM steps WHERE idx >= ?1 ORDER BY idx").ok()?;
    let rows = stmt
        .query_map([low], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?, r.get::<_, Option<Vec<u8>>>(2)?)))
        .ok()?;
    Some(rows.filter_map(|r| r.ok()).collect())
}

/// New tokens in the IDE conversation DB since the previous call. A step is
/// counted once, whenever its usage appears (a step can exist before its usage
/// is written). On first sight everything before the last user message is
/// history: it is neither read nor fed, so resuming a conversation feeds nothing
/// old. Afterwards only the last `DB_WINDOW` steps (never below that first
/// point) are read, not the whole table. Callers serialise per path (`coalesce`).
pub fn new_db_tokens(db: &Path) -> Option<i64> {
    let key = db.to_string_lossy().into_owned();
    let known = {
        let mut g = DBS.lock().ok()?;
        g.get_or_insert_with(Tracked::new).get(&key).map(|st| (st.floor, st.max_idx))
    };
    let (floor, low, first) = match known {
        Some((floor, max_idx)) => (floor, floor.max(max_idx - DB_WINDOW + 1), false),
        None => {
            let f = last_user_idx(db)?.max(0);
            (f, f, true)
        }
    };
    let steps = read_steps_from(db, low)?;
    let mut g = DBS.lock().ok()?;
    let all = g.get_or_insert_with(Tracked::new);
    if first {
        all.insert(key.clone(), DbState { floor, max_idx: -1, seen: HashSet::new() });
    }
    let st = all.get(&key)?;
    let mut total = 0;
    for (idx, _, md) in &steps {
        st.max_idx = st.max_idx.max(*idx);
        let Some((input, output)) = md.as_deref().and_then(parse_usage) else { continue };
        if st.seen.insert(*idx) {
            total += input.max(0) + output.max(0);
        }
    }
    // Forget counted steps that left the window so the set stays small.
    let keep_from = st.floor.max(st.max_idx - DB_WINDOW + 1);
    st.seen.retain(|i| *i >= keep_from);
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
    let offsets = guard.get_or_insert_with(Tracked::new);

    let mut f = std::fs::File::open(path).ok()?;
    let size = f.seek(SeekFrom::End(0)).ok()?;
    let known = offsets.get(path).map(|o| *o);
    let mut start = known.unwrap_or(0);
    if start > size {
        start = 0; // file replaced: start over
    }
    // A big first read (or a huge jump): only the tail (see FIRST_READ_CAP). The cut can
    // land mid-line, so skip to the first newline after it.
    let mut cut = false;
    if size - start > FIRST_READ_CAP {
        start = size - FIRST_READ_CAP;
        cut = true;
    }
    if known.is_some() && size <= start {
        return Some(0);
    }
    f.seek(SeekFrom::Start(start)).ok()?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf).ok()?;
    if cut {
        let nl = buf.iter().position(|&b| b == b'\n').map(|i| i + 1).unwrap_or(buf.len());
        start += nl as u64;
        buf.drain(..nl);
    }

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
    fn db_reads_only_a_window_after_the_first_scan() {
        let p = tmp("db-window");
        // 300 model steps: after the first scan only DB_WINDOW of them may be re-read.
        let mut steps: Vec<(i64, i64, Option<Vec<u8>>)> = vec![(0, 14, None)];
        for i in 1..=300 { steps.push((i, 15, Some(usage_md(10, None)))); }
        make_db(&p, &steps);
        assert_eq!(new_db_tokens(&p), Some(3000));
        // Tamper with an old step far outside the window: it must not be re-read.
        let c = rusqlite::Connection::open(&p).unwrap();
        c.execute("UPDATE steps SET metadata=?1 WHERE idx=5", rusqlite::params![usage_md(999_999, None)]).unwrap();
        drop(c);
        add_step(&p, 301, 15, Some(usage_md(7, None)));
        assert_eq!(new_db_tokens(&p), Some(7));
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn tracked_map_is_bounded_and_evicts_the_oldest() {
        let mut t: Tracked<u8> = Tracked::new();
        for i in 0..(MAX_TRACKED + 10) {
            t.insert(format!("k{i}"), 0);
            if i == 0 { continue; }
            t.get("k0"); // keep k0 fresh
        }
        assert_eq!(t.map.len(), MAX_TRACKED);
        assert!(t.get("k0").is_some(), "recently used entry survives");
        assert!(t.get("k1").is_none(), "oldest unused entry was evicted");
    }

    #[test]
    fn first_read_of_a_huge_transcript_is_capped() {
        let p = tmp("huge");
        let filler = format!("{{\"type\":\"GENERIC\",\"content\":\"{}\"}}\n", "x".repeat(1000));
        let mut s = String::new();
        // About 2 x FIRST_READ_CAP of filler, then one real model step at the end.
        for _ in 0..(2 * FIRST_READ_CAP as usize / filler.len()) { s.push_str(&filler); }
        s.push_str(&format!("{PLAN1}\n"));
        std::fs::write(&p, &s).unwrap();
        assert_eq!(new_transcript_tokens(p.to_str().unwrap()), Some(11641 + 58));
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn a_burst_of_events_becomes_at_most_two_scans() {
        use std::sync::atomic::{AtomicUsize, Ordering};
        use std::sync::Arc;
        let scans = Arc::new(AtomicUsize::new(0));
        let fed = Arc::new(AtomicUsize::new(0));
        let path = "burst-test-path";
        let mut hs = vec![];
        for _ in 0..8 {
            let (s, f) = (scans.clone(), fed.clone());
            hs.push(std::thread::spawn(move || {
                coalesce(path, || { s.fetch_add(1, Ordering::SeqCst); std::thread::sleep(DEBOUNCE); Some(5) },
                         |t| { f.fetch_add(t as usize, Ordering::SeqCst); });
            }));
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        for h in hs { h.join().unwrap(); }
        let n = scans.load(Ordering::SeqCst);
        assert!(n >= 1 && n <= 2, "scans={n}");
        assert_eq!(fed.load(Ordering::SeqCst), 5 * n);
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
