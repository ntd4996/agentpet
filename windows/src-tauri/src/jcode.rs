//! jcode integration (github.com/1jehuang/jcode, docs/HOOKS.md). Port of the
//! macOS `JcodeHookConfig` (Sources/AgentPetCore/JcodeHook.swift).
//!
//! jcode runs observer hooks from the `[hooks]` table of `~/.jcode/config.toml`
//! and describes each event in `JCODE_HOOK_*` env vars (stdin is /dev/null).
//! The installer edits only AgentPet's keys line by line, so comments and every
//! other key stay byte-for-byte intact. `pre_tool` (a blocking gate) is never used.
//!
//! Windows twist: jcode usually runs inside WSL, so the config lives on the WSL
//! side (`\\wsl.localhost\<distro>\home\<user>\.jcode\config.toml`) and the hook
//! command runs `agentpet.exe` through WSL interop. Linux env vars only reach a
//! Windows process when listed in `WSLENV`, hence the `/usr/bin/env WSLENV=...`
//! prefix (jcode executes hook commands directly, without a shell).
//!
//! This file depends on `std` only so its logic can be unit-tested anywhere.

/// Observer events AgentPet listens to (same set as the macOS app).
pub const EVENTS: &[&str] = &["session_start", "turn_start", "post_tool", "turn_end", "session_end"];

/// `JCODE_HOOK_*` variables forwarded from WSL to agentpet.exe. No `/p` flag:
/// paths stay Linux paths (only their last component is shown as the project).
/// JCODE_HOOK_PAYLOAD (up to 16 KB) is not needed and not forwarded.
pub const FORWARDED_VARS: &[&str] = &[
    "JCODE_HOOK_EVENT", "JCODE_HOOK_SESSION_ID", "JCODE_HOOK_CWD", "JCODE_HOOK_TOOL_NAME",
    "JCODE_HOOK_STATUS", "JCODE_HOOK_MODEL", "JCODE_HOOK_LAST_ASSISTANT_TEXT",
];

/// The hook command written into config.toml. `exe` is the path jcode can
/// execute: a Linux path to agentpet.exe for WSL (e.g. /mnt/c/.../agentpet.exe),
/// or the native path when jcode runs on Windows itself.
pub fn hook_command(exe: &str, via_wsl: bool) -> String {
    if via_wsl {
        format!("/usr/bin/env WSLENV={} \"{}\" hook --agent jcode", FORWARDED_VARS.join(":"), exe)
    } else {
        format!("\"{}\" hook --agent jcode", exe)
    }
}

/// Same rule as hooks.rs: a command is ours when it mentions agentpet + hook.
pub fn is_ours(line: &str) -> bool {
    let l = line.to_lowercase();
    l.contains("agentpet") && l.contains("hook")
}

/// True for any spelling of the `[hooks]` header TOML allows: a trailing
/// comment, CRLF line endings, or spaces inside the brackets. Missing one would
/// append a second `[hooks]` table, which is invalid TOML, and jcode then
/// silently falls back to its default config (same fix as the macOS JcodeHookConfig, PR #60).
pub fn is_hooks_header(line: &str) -> bool {
    let code = line.split('#').next().unwrap_or("");
    code.chars().filter(|c| !c.is_whitespace()).collect::<String>() == "[hooks]"
}

/// Line range of the `[hooks]` table body: (header index, end exclusive).
fn hooks_body(lines: &[String]) -> Option<(usize, usize)> {
    let header = lines.iter().position(|l| is_hooks_header(l))?;
    let mut end = header + 1;
    while end < lines.len() && !lines[end].trim_start().starts_with('[') {
        end += 1;
    }
    Some((header, end))
}

/// Index of the uncommented `key = ...` line in the hooks body, if any.
fn key_line(key: &str, lines: &[String], body: (usize, usize)) -> Option<usize> {
    (body.0 + 1..body.1).find(|&i| {
        let line = lines[i].trim();
        line.strip_prefix(key).map(|rest| rest.trim_start().starts_with('=')).unwrap_or(false)
    })
}

/// TOML string for `command`: a literal string when possible (no escaping of
/// the embedded double quotes), otherwise an escaped basic string.
pub fn toml_string(command: &str) -> String {
    if !command.contains('\'') && !command.contains('\n') {
        return format!("'{}'", command);
    }
    let escaped = command.replace('\\', "\\\\").replace('"', "\\\"").replace('\n', "\\n");
    format!("\"{}\"", escaped)
}

fn split(toml: &str) -> Vec<String> {
    toml.split('\n').map(String::from).collect()
}

pub fn is_installed(toml: &str, events: &[&str]) -> bool {
    let lines = split(toml);
    let Some(body) = hooks_body(&lines) else { return false };
    events.iter().any(|e| key_line(e, &lines, body).map(|i| is_ours(&lines[i])).unwrap_or(false))
}

/// Adds AgentPet's keys. A key already set to someone else's command is refused
/// (validated up front, so a conflict never half-installs).
/// simplify: refuse instead of merging; jcode accepts an array value, so merging
/// is the upgrade path if anyone needs to share a hook with AgentPet.
pub fn install(toml: &str, command: &str, events: &[&str]) -> Result<String, String> {
    let mut lines = split(toml);
    if hooks_body(&lines).is_none() {
        if lines.last().map(|l| l.is_empty()).unwrap_or(false) {
            lines.pop();
        }
        if !lines.is_empty() {
            lines.push(String::new());
        }
        lines.push("[hooks]".into());
        lines.push(String::new());
    }
    let body = hooks_body(&lines).expect("just ensured");
    for e in events {
        if let Some(i) = key_line(e, &lines, body) {
            if !is_ours(&lines[i]) {
                return Err(format!(
                    "config.toml already sets hooks.{e}; remove it or add AgentPet's command to it manually."
                ));
            }
        }
    }
    let value = toml_string(command);
    let mut missing = Vec::new();
    for e in events {
        let entry = format!("{e} = {value}");
        match key_line(e, &lines, body) {
            Some(i) => lines[i] = entry,
            None => missing.push(entry),
        }
    }
    // Insert below the header: indices above stay valid.
    for (k, entry) in missing.into_iter().enumerate() {
        lines.insert(body.0 + 1 + k, entry);
    }
    Ok(lines.join("\n"))
}

/// Removes only AgentPet's keys; foreign hooks and the table header stay.
pub fn uninstall(toml: &str, events: &[&str]) -> String {
    let mut lines = split(toml);
    for e in events {
        let Some(body) = hooks_body(&lines) else { break };
        if let Some(i) = key_line(e, &lines, body) {
            if is_ours(&lines[i]) {
                lines.remove(i);
            }
        }
    }
    lines.join("\n")
}

// ---------------------------------------------------------------- questions --
// Port of the macOS QuestionDetector (also in transcript.rs for Claude; kept
// here too so this module stays std-only and testable on its own).

const QUESTION_STARTERS: &[&str] = &[
    "which ", "what ", "how ", "should i", "do you", "want me to",
    "shall i", "would you", "can you", "could you", "are you",
];
const OPTIONAL_FOLLOW_UPS: &[&str] = &[
    "let me know if", "let me know when", "feel free to", "if you'd like any",
    "if you want any", "if you want to", "if you'd like to", "if you need any",
    "say which one", "say the word", "if anything else", "happy to help",
    "happy to make", "don't hesitate", "just let me know",
];

pub fn last_sentence(text: &str) -> String {
    let normalized = text.replace('\n', " ");
    let mut segs: Vec<String> = Vec::new();
    let mut cur = String::new();
    for ch in normalized.trim().chars() {
        cur.push(ch);
        if ch == '.' || ch == '!' || ch == '?' {
            let s = cur.trim().to_string();
            if !s.is_empty() {
                segs.push(s);
            }
            cur.clear();
        }
    }
    let rest = cur.trim();
    if !rest.is_empty() {
        segs.push(rest.to_string());
    }
    segs.pop().unwrap_or_default()
}

pub fn looks_like_question(text: &str) -> bool {
    let last = last_sentence(text.trim()).to_lowercase();
    if last.is_empty() || OPTIONAL_FOLLOW_UPS.iter().any(|p| last.contains(p)) {
        return false;
    }
    last.ends_with('?') || QUESTION_STARTERS.iter().any(|s| last.starts_with(s))
}

/// The jcode event as (event name, message), from `JCODE_HOOK_*` values.
/// `None` when the event or session is missing (nothing useful to report).
/// A turn that ends by asking the user something becomes "waiting": jcode has
/// no "needs input" hook (same refinement as the macOS app).
pub fn event_from_env(get: impl Fn(&str) -> Option<String>) -> Option<(String, String, String, String, String)> {
    let nonempty = |k: &str| get(k).filter(|s| !s.is_empty());
    let event = nonempty("JCODE_HOOK_EVENT")?;
    let session = nonempty("JCODE_HOOK_SESSION_ID")?;
    let project = nonempty("JCODE_HOOK_CWD").unwrap_or_default();
    let tool = nonempty("JCODE_HOOK_TOOL_NAME").unwrap_or_default();
    let mut name = event.clone();
    let mut message = String::new();
    if event == "turn_end" && get("JCODE_HOOK_STATUS").as_deref() != Some("error") {
        if let Some(text) = nonempty("JCODE_HOOK_LAST_ASSISTANT_TEXT") {
            if looks_like_question(&text) {
                name = "waiting".into();
                message = last_sentence(&text).chars().take(140).collect();
            } else {
                // Finished turn: keep the agent's opening line so the "finished"
                // toast says what was done (markdown marks stripped).
                message = opening_line(&text).chars().take(140).collect();
            }
        }
    }
    Some((name, session, project, tool, message))
}

/// The agent's first sentence for a finished turn, markdown marks stripped.
/// The opening line usually states the result ("Installed X"), while the last
/// one is often an invitation ("let me know..."). A '.' only ends a sentence
/// before whitespace/end, so `server.rs` or `0.1.27` stay whole; a line break
/// also ends it, so a heading or bullet isn't glued to the next paragraph.
pub fn opening_line(text: &str) -> String {
    let clean = text.replace("**", "").replace('`', "");
    let first = clean
        .lines()
        .map(|l| l.trim().trim_start_matches(|c: char| matches!(c, '#' | '-' | '*' | '>' | '•')).trim())
        .find(|l| !l.is_empty())
        .unwrap_or("");
    let chars: Vec<char> = first.chars().collect();
    for (i, &c) in chars.iter().enumerate() {
        let end_mark = c == '.' || c == '!' || c == '?';
        if end_mark && (i + 1 == chars.len() || chars[i + 1].is_whitespace()) {
            return chars[..=i].iter().collect();
        }
    }
    first.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    const CMD: &str = "/usr/bin/env WSLENV=A:B \"/mnt/c/x/agentpet.exe\" hook --agent jcode";

    fn env<'a>(pairs: &'a [(&'a str, &'a str)]) -> impl Fn(&str) -> Option<String> + 'a {
        move |k| pairs.iter().find(|(a, _)| *a == k).map(|(_, v)| v.to_string())
    }

    // --- payload (mirrors Tests/AgentPetCoreTests/JcodeHookTests.swift) ---

    #[test]
    fn env_payload_builds_event() {
        let e = event_from_env(env(&[("JCODE_HOOK_EVENT", "post_tool"), ("JCODE_HOOK_SESSION_ID", "session_x_1"),
            ("JCODE_HOOK_CWD", "/proj"), ("JCODE_HOOK_TOOL_NAME", "bash")])).unwrap();
        assert_eq!(e.0, "post_tool");
        assert_eq!(e.1, "session_x_1");
        assert_eq!(e.2, "/proj");
        assert_eq!(e.3, "bash");
    }

    #[test]
    fn missing_session_or_event_is_ignored() {
        assert!(event_from_env(env(&[("JCODE_HOOK_EVENT", "turn_end")])).is_none());
        assert!(event_from_env(env(&[("JCODE_HOOK_SESSION_ID", "s")])).is_none());
        assert!(event_from_env(env(&[])).is_none());
    }

    #[test]
    fn turn_ending_on_question_is_waiting() {
        let e = event_from_env(env(&[("JCODE_HOOK_EVENT", "turn_end"), ("JCODE_HOOK_SESSION_ID", "s"),
            ("JCODE_HOOK_STATUS", "ok"),
            ("JCODE_HOOK_LAST_ASSISTANT_TEXT", "I found two options. Which one should I use?")])).unwrap();
        assert_eq!(e.0, "waiting");
        assert_eq!(e.4, "Which one should I use?");
    }

    #[test]
    fn turn_ending_with_summary_is_done() {
        let e = event_from_env(env(&[("JCODE_HOOK_EVENT", "turn_end"), ("JCODE_HOOK_SESSION_ID", "s"),
            ("JCODE_HOOK_STATUS", "ok"), ("JCODE_HOOK_LAST_ASSISTANT_TEXT", "Fixed the bug and tests pass.")])).unwrap();
        assert_eq!(e.0, "turn_end");
        assert_eq!(e.4, "Fixed the bug and tests pass.");
    }

    #[test]
    fn done_message_drops_markdown_marks() {
        let e = event_from_env(env(&[("JCODE_HOOK_EVENT", "turn_end"), ("JCODE_HOOK_SESSION_ID", "s"),
            ("JCODE_HOOK_STATUS", "ok"), ("JCODE_HOOK_LAST_ASSISTANT_TEXT", "**Done:** patched `server.rs`. Let me know if you want more.")])).unwrap();
        assert_eq!(e.0, "turn_end");
        assert_eq!(e.4, "Done: patched server.rs.");
    }

    #[test]
    fn opening_line_keeps_dots_inside_tokens() {
        assert_eq!(opening_line("Updated 0.1.27 and server.rs. Then more."), "Updated 0.1.27 and server.rs.");
        assert_eq!(opening_line("One. Two! Three."), "One.");
        assert_eq!(opening_line("Single line without end"), "Single line without end");
        assert_eq!(opening_line("Đã cài xong bản mới\n\n- chi tiết một\n- chi tiết hai"), "Đã cài xong bản mới");
        assert_eq!(opening_line("\n\n## Kết quả\nOK."), "Kết quả");
        assert_eq!(opening_line("  \n "), "");
        assert_eq!(opening_line(""), "");
    }

    #[test]
    fn failed_turn_is_never_waiting() {
        let e = event_from_env(env(&[("JCODE_HOOK_EVENT", "turn_end"), ("JCODE_HOOK_SESSION_ID", "s"),
            ("JCODE_HOOK_STATUS", "error"), ("JCODE_HOOK_LAST_ASSISTANT_TEXT", "Should I retry?")])).unwrap();
        assert_eq!(e.0, "turn_end");
    }

    #[test]
    fn polite_follow_up_is_not_a_question() {
        assert!(!looks_like_question("Done. Let me know if you want changes?"));
        assert!(looks_like_question("Two paths. Want me to apply the fix"));
    }

    // --- config edits ---

    #[test]
    fn install_into_empty_file_creates_table() {
        let out = install("", CMD, EVENTS).unwrap();
        assert!(out.starts_with("[hooks]\n"));
        for e in EVENTS {
            assert!(out.contains(&format!("{e} = '{CMD}'")), "{e} missing in {out}");
        }
        assert!(is_installed(&out, EVENTS));
    }

    #[test]
    fn install_keeps_other_keys_and_comments() {
        let src = "[display]\ntheme = \"\"\n\n[hooks]\n# mine\npre_tool_timeout_ms = 5000\n\n[ambient]\nenabled = false\n";
        let out = install(src, CMD, EVENTS).unwrap();
        assert!(out.contains("# mine\npre_tool_timeout_ms = 5000"));
        assert!(out.contains("[ambient]\nenabled = false"));
        assert_eq!(out.matches("[hooks]").count(), 1);
        let back = uninstall(&out, EVENTS);
        assert_eq!(back, src, "uninstall must restore the original bytes");
    }

    #[test]
    fn install_is_idempotent_and_replaces_older_agentpet_commands() {
        let src = "[hooks]\nturn_end = \"/home/u/.jcode/hooks/agentpet-jcode-hook\"\n";
        let once = install(src, CMD, EVENTS).unwrap();
        let twice = install(&once, CMD, EVENTS).unwrap();
        assert_eq!(once, twice);
        assert!(!once.contains("agentpet-jcode-hook"));
        assert_eq!(once.matches("turn_end =").count(), 1);
    }

    #[test]
    fn foreign_hook_is_refused_without_partial_edit() {
        let src = "[hooks]\nturn_end = \"~/bin/notify\"\n";
        assert!(install(src, CMD, EVENTS).is_err());
        assert!(!is_installed(src, EVENTS));
    }

    #[test]
    fn every_header_spelling_is_matched() {
        for h in ["[hooks]", "[hooks] # lifecycle", "[ hooks ]", "[hooks]\r", "  [hooks]"] {
            assert!(is_hooks_header(h), "{h:?}");
            let src = format!("{h}\npre_tool_timeout_ms = 5000\n");
            let out = install(&src, CMD, EVENTS).unwrap();
            assert_eq!(out.lines().filter(|l| is_hooks_header(l)).count(), 1, "duplicate table for {h:?}");
        }
        assert!(!is_hooks_header("[hooks.extra]"));
        assert!(!is_hooks_header("# [hooks]"));
    }

    #[test]
    fn commented_key_is_not_treated_as_set() {
        let src = "[hooks]\n# turn_end = \"~/bin/notify\"\n";
        let out = install(src, CMD, EVENTS).unwrap();
        assert!(out.contains("# turn_end = \"~/bin/notify\""));
        assert!(out.contains(&format!("turn_end = '{CMD}'")));
    }

    #[test]
    fn toml_string_escapes_when_needed() {
        assert_eq!(toml_string("a \"b\""), "'a \"b\"'");
        assert_eq!(toml_string("it's \"x\""), "\"it's \\\"x\\\"\"");
    }

    #[test]
    fn hook_command_forwards_vars_through_wslenv() {
        let c = hook_command("/mnt/c/A P/agentpet.exe", true);
        assert!(c.starts_with("/usr/bin/env WSLENV=JCODE_HOOK_EVENT:JCODE_HOOK_SESSION_ID:"));
        assert!(c.ends_with("\"/mnt/c/A P/agentpet.exe\" hook --agent jcode"));
        let wslenv = c.split_whitespace().nth(1).unwrap();
        assert!(!wslenv.contains('/'), "a /u or /p flag would change direction or translate paths: {wslenv}");
        assert!(is_ours(&c));
    }
}
