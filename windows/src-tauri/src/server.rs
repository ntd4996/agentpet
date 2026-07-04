//! A tiny localhost HTTP listener. The `agentpet hook` CLI (run by each agent's
//! hook) POSTs an event here; we map it to a pet state and emit a Tauri event
//! to the UI (broadcast: pet overlay + Settings both listen). Mirrors the macOS
//! app's unix-socket daemon, but cross-platform.
//!
//! Like the macOS AppDaemon it also:
//! - drains events queued on disk while the app was closed (replayed with
//!   their original timestamps so stale sessions prune instead of resurrecting)
//! - on a Claude `Stop`, reads the transcript to see whether Claude actually
//!   ended by ASKING something, and corrects `done` → `waiting` (the final
//!   state is emitted once , no done-then-waiting double notification)
//! - resolves a human conversation title from the transcript

use serde_json::Value;
use tauri::{AppHandle, Emitter};

pub const HOOK_PORT: u16 = 47628;

pub fn start(app: AppHandle) {
    // Replay events queued while the app was closed (name order = time order).
    if let Some(dir) = crate::cli::queue_dir() {
        if let Ok(entries) = std::fs::read_dir(&dir) {
            let mut names: Vec<_> = entries.flatten().map(|e| e.path()).collect();
            names.sort();
            for path in names {
                if let Ok(body) = std::fs::read_to_string(&path) {
                    for line in body.lines().filter(|l| !l.trim().is_empty()) {
                        handle_event(&app, line);
                    }
                }
                let _ = std::fs::remove_file(&path);
            }
        }
    }

    std::thread::spawn(move || {
        let server = match tiny_http::Server::http(("127.0.0.1", HOOK_PORT)) {
            Ok(s) => s,
            Err(_) => return, // another instance owns the port
        };
        for mut req in server.incoming_requests() {
            let mut body = String::new();
            let _ = req.as_reader().read_to_string(&mut body);
            handle_event(&app, &body);
            let _ = req.respond(tiny_http::Response::from_string("ok"));
        }
    });
}

fn str_of<'a>(v: &'a Value, key: &str) -> &'a str {
    v.get(key).and_then(|x| x.as_str()).unwrap_or("")
}

fn handle_event(app: &AppHandle, body: &str) {
    let Ok(v) = serde_json::from_str::<Value>(body) else { return };
    let agent = str_of(&v, "agent").to_string();
    let event = str_of(&v, "event").to_string();
    let session = str_of(&v, "session").to_string();
    let project = str_of(&v, "project").to_string();
    let message = str_of(&v, "message").to_string();
    let tool = str_of(&v, "tool").to_string();
    let file = str_of(&v, "file").to_string();
    let desc = str_of(&v, "desc").to_string();
    let transcript = str_of(&v, "transcript").to_string();
    let ts = v.get("ts").and_then(|x| x.as_u64()).unwrap_or(0);

    if crate::statemap::is_session_end(&agent, &event) {
        let _ = app.emit("agent-end", session);
        return;
    }
    let Some(state) = crate::statemap::state(&agent, &event) else { return };

    // Claude's Stop fires identically whether the agent is truly done or just
    // asked the user a question. Resolve the transcript first (fast, local
    // file) and emit exactly one final-state event , like the macOS app.
    let claude_path = if agent == "claude" {
        if !transcript.is_empty() {
            Some(transcript.clone())
        } else if !project.is_empty() && !session.is_empty() {
            crate::transcript::inferred_path(&session, &project)
        } else {
            None
        }
    } else {
        None
    };
    let is_stop_done = event == "Stop" && state == "done";
    // Kept for the token event, since `emit_payload` moves session/project.
    let tok_session = session.clone();
    let tok_project = project.clone();

    let emit_payload = move |app: &AppHandle, state: &str, title: Option<String>| {
        let payload = serde_json::json!({
            "agent": agent, "state": state, "session": session, "project": project,
            "message": message, "tool": tool, "file": file, "desc": desc,
            "event": event, "title": title, "ts": ts,
        });
        let _ = app.emit("agent-event", payload);
    };

    if let Some(path) = claude_path {
        let app = app.clone();
        let state = state.to_string();
        std::thread::spawn(move || {
            let title = crate::transcript::title(&path);
            let final_state = if is_stop_done
                && crate::transcript::latest_assistant_text(&path)
                    .map(|t| crate::transcript::looks_like_question(&t))
                    .unwrap_or(false)
            {
                "waiting".to_string()
            } else {
                state
            };
            emit_payload(&app, &final_state, title);
            // Feed the pet: the tokens Claude burned since the last read (delta).
            if let Some(tokens) = crate::transcript::new_usage_tokens(&path) {
                if tokens > 0 {
                    let _ = app.emit("agent-tokens", serde_json::json!({
                        "agent": "claude", "session": tok_session,
                        "project": tok_project, "tokens": tokens,
                    }));
                }
            }
        });
        return;
    }

    emit_payload(app, state, None);
}
