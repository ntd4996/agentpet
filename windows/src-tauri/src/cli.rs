//! The `agentpet hook --agent <kind>` command, run by each agent's hook. It
//! reads the agent's payload (explicit flags for the opencode plugin, otherwise
//! JSON on stdin), extracts the essentials, and POSTs them to the running app's
//! localhost listener. ALWAYS exits 0 so it never blocks an agent (Copilot
//! PreToolUse is fail-closed). If the app isn't running, the event is queued on
//! disk and replayed on the next launch (like the macOS app's event queue).
//!
//! Also hosts `agentpet run -- <cmd...>`: wraps any CLI agent, keeping the
//! session `working` (with a heartbeat) while it runs and `done` on exit.

use serde_json::Value;
use std::io::{Read, Write};
use std::net::TcpStream;

pub fn run_hook(args: &[String]) {
    let agent = flag(args, "--agent").unwrap_or_else(|| "unknown".into());
    let (terminal_program, terminal_focus_url) = terminal_env();

    // Explicit flags win (opencode plugin + the run wrapper). `--event` carries a
    // normalised state directly there.
    if let Some(event) = flag(args, "--event") {
        post_and_exit(Payload {
            agent,
            event,
            session: flag(args, "--session").unwrap_or_default(),
            project: flag(args, "--project").unwrap_or_default(),
            message: flag(args, "--message").unwrap_or_default(),
            terminal_program,
            terminal_focus_url,
            ..Payload::default()
        });
    }

    // Otherwise decode the JSON the agent pipes on stdin. Field names vary by
    // agent (Claude/Codex/Gemini/Kiro/Copilot, Cursor, Windsurf, Antigravity),
    // so we try each convention.
    let mut buf = String::new();
    let _ = std::io::stdin().read_to_string(&mut buf);
    let v: Value = serde_json::from_str(&buf).unwrap_or(Value::Null);

    // Antigravity sends no event-name field; infer state from discriminator fields
    // (mirrors AntigravityHookPayload.makeEvent in the macOS core).
    let event = if agent == "antigravity" {
        if v.get("terminationReason").is_some() || v.get("fullyIdle").is_some() {
            Some("done".to_string())
        } else if v.get("toolCall").is_some()
            || v.get("invocationNum").is_some()
            || v.get("stepIdx").is_some()
        {
            Some("working".to_string())
        } else {
            None
        }
    } else {
        first_str(&v, &["hook_event_name", "agent_action_name", "hookEventName", "eventName"])
    };
    let session = first_str(&v, &["session_id", "conversation_id", "trajectory_id", "sessionId", "conversationId"]);
    let project = first_str(&v, &["cwd", "projectRoot"])
        .or_else(|| {
            v.get("workspace_roots")
                .and_then(|a| a.as_array())
                .and_then(|a| a.first())
                .and_then(|x| x.as_str())
                .map(String::from)
        })
        .or_else(|| {
            // Antigravity uses camelCase workspacePaths (array), not workspace_roots
            v.get("workspacePaths")
                .and_then(|a| a.as_array())
                .and_then(|a| a.iter().find(|x| x.as_str().map(|s| !s.is_empty()).unwrap_or(false)))
                .and_then(|x| x.as_str())
                .map(String::from)
        })
        .unwrap_or_default();

    if session.as_deref().unwrap_or("").is_empty() && event.as_deref().unwrap_or("").is_empty() {
        std::process::exit(0); // nothing useful; never block the agent
    }
    post_and_exit(Payload {
        agent,
        event: event.unwrap_or_default(),
        session: session.unwrap_or_default(),
        project,
        message: first_str(&v, &["message"]).unwrap_or_default(),
        tool: first_str(&v, &["tool_name", "toolName"]).unwrap_or_default(),
        file: v
            .get("tool_input")
            .and_then(|i| i.get("file_path"))
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string(),
        desc: v
            .get("tool_input")
            .and_then(|i| i.get("description"))
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string(),
        transcript: first_str(&v, &["transcript_path", "transcriptPath"]).unwrap_or_default(),
        subagent: first_str(&v, &["agent_id", "subagent_id", "agentId"]).unwrap_or_default(),
        terminal_program,
        terminal_focus_url,
    });
}

/// Which terminal the hook runs in, for click-to-focus. `TERM_PROGRAM` names it;
/// Warp also exports `WARP_FOCUS_URL` (a `warp://session/<uuid>` deep link) that
/// focuses the exact pane , the one cross-platform "focus exact tab" we get.
fn terminal_env() -> (String, String) {
    let nonempty = |k: &str| std::env::var(k).ok().filter(|s| !s.is_empty()).unwrap_or_default();
    (nonempty("TERM_PROGRAM"), nonempty("WARP_FOCUS_URL"))
}

/// `agentpet run [--session id] [--project path] [--agent kind] -- <command...>`
/// Port of the macOS RunCLI: any CLI agent gets a working session with a 60s
/// heartbeat, and `done` when the command exits (exit code passed through).
pub fn run_wrapper(args: &[String]) -> ! {
    let dashdash = args.iter().position(|a| a == "--");
    let (flags, command) = match dashdash {
        Some(i) => (&args[..i], &args[i + 1..]),
        None => (args, &args[args.len()..]),
    };
    if command.is_empty() {
        eprintln!("usage: agentpet run [--session id] [--project path] [--agent kind] -- <command...>");
        std::process::exit(2);
    }

    let session = flag(flags, "--session").unwrap_or_else(|| {
        format!("run-{:08x}", std::process::id() as u64 ^ now_millis())
    });
    let project = flag(flags, "--project").unwrap_or_else(|| {
        std::env::current_dir().map(|d| d.to_string_lossy().into_owned()).unwrap_or_default()
    });
    let agent = flag(flags, "--agent").unwrap_or_else(|| "cli".into());

    let emit = {
        let agent = agent.clone();
        let session = session.clone();
        let project = project.clone();
        move |state: &str| {
            let p = Payload {
                agent: agent.clone(),
                event: state.to_string(),
                session: session.clone(),
                project: project.clone(),
                ..Payload::default()
            };
            if post(&p.to_json()).is_err() {
                queue(&p);
            }
        }
    };

    emit("working");

    // Heartbeat so a long-running agent's session stays fresh.
    let hb = {
        let emit = emit.clone();
        std::thread::spawn(move || loop {
            std::thread::sleep(std::time::Duration::from_secs(60));
            emit("working");
        })
    };
    let _ = hb; // detached; process exit ends it

    let status = std::process::Command::new(&command[0])
        .args(&command[1..])
        .status();

    emit("done");
    match status {
        Ok(s) => std::process::exit(s.code().unwrap_or(0)),
        Err(_) => {
            eprintln!("agentpet run: failed to launch {}", command[0]);
            std::process::exit(126);
        }
    }
}

#[derive(Default, Clone)]
struct Payload {
    agent: String,
    event: String,
    session: String,
    project: String,
    message: String,
    tool: String,
    file: String,
    desc: String,
    transcript: String,
    subagent: String,
    terminal_program: String,
    terminal_focus_url: String,
}

impl Payload {
    fn to_json(&self) -> String {
        serde_json::json!({
            "agent": self.agent, "event": self.event, "session": self.session,
            "project": self.project, "message": self.message, "tool": self.tool,
            "file": self.file, "desc": self.desc, "transcript": self.transcript,
            "subagent": self.subagent,
            "terminalProgram": self.terminal_program, "terminalFocusUrl": self.terminal_focus_url,
            "ts": now_millis(),
        })
        .to_string()
    }
}

fn post_and_exit(p: Payload) -> ! {
    if post(&p.to_json()).is_err() {
        // App not running , queue the event for replay on next launch.
        queue(&p);
    }
    std::process::exit(0);
}

/// Queue dir shared with the app: %LOCALAPPDATA%/AgentPet/queue (config_dir on
/// other platforms). One JSON line per file, name-ordered by timestamp.
pub fn queue_dir() -> Option<std::path::PathBuf> {
    dirs::config_dir().map(|d| d.join("AgentPet").join("queue"))
}

fn queue(p: &Payload) {
    let Some(dir) = queue_dir() else { return };
    if std::fs::create_dir_all(&dir).is_err() {
        return;
    }
    let name = format!("{}-{}.json", now_millis(), std::process::id());
    let _ = std::fs::write(dir.join(name), p.to_json());
}

fn now_millis() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn flag(args: &[String], name: &str) -> Option<String> {
    let mut it = args.iter();
    while let Some(a) = it.next() {
        if a == name {
            return it.next().cloned();
        }
    }
    None
}

pub(super) fn first_str(v: &Value, keys: &[&str]) -> Option<String> {
    for k in keys {
        if let Some(s) = v.get(*k).and_then(|x| x.as_str()) {
            if !s.is_empty() {
                return Some(s.to_string());
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    fn infer_antigravity_event(v: &serde_json::Value) -> Option<String> {
        if v.get("terminationReason").is_some() || v.get("fullyIdle").is_some() {
            Some("done".to_string())
        } else if v.get("toolCall").is_some()
            || v.get("invocationNum").is_some()
            || v.get("stepIdx").is_some()
        {
            Some("working".to_string())
        } else {
            None
        }
    }

    fn extract_project(v: &serde_json::Value) -> String {
        super::first_str(v, &["cwd", "projectRoot"])
            .or_else(|| {
                v.get("workspace_roots")
                    .and_then(|a| a.as_array())
                    .and_then(|a| a.first())
                    .and_then(|x| x.as_str())
                    .map(String::from)
            })
            .or_else(|| {
                v.get("workspacePaths")
                    .and_then(|a| a.as_array())
                    .and_then(|a| a.iter().find(|x| x.as_str().map(|s| !s.is_empty()).unwrap_or(false)))
                    .and_then(|x| x.as_str())
                    .map(String::from)
            })
            .unwrap_or_default()
    }

    // --- Antigravity event inference ---

    #[test]
    fn antigravity_step_idx_is_working() {
        let v = json!({"conversationId":"c1","workspacePaths":["/Users/me/proj"],"stepIdx":0,"toolCall":{"name":"run_command"}});
        assert_eq!(infer_antigravity_event(&v), Some("working".to_string()));
    }

    #[test]
    fn antigravity_invocation_num_is_working() {
        let v = json!({"conversationId":"c3","invocationNum":2,"initialNumSteps":5});
        assert_eq!(infer_antigravity_event(&v), Some("working".to_string()));
    }

    #[test]
    fn antigravity_termination_reason_is_done() {
        let v = json!({"conversationId":"c2","executionNum":1,"terminationReason":"model_stop","fullyIdle":true});
        assert_eq!(infer_antigravity_event(&v), Some("done".to_string()));
    }

    #[test]
    fn antigravity_fully_idle_alone_is_done() {
        let v = json!({"conversationId":"c4","fullyIdle":true});
        assert_eq!(infer_antigravity_event(&v), Some("done".to_string()));
    }

    #[test]
    fn antigravity_done_takes_priority_over_working_fields() {
        // terminationReason present alongside stepIdx — done wins (stop event).
        let v = json!({"conversationId":"c5","terminationReason":"model_stop","stepIdx":3});
        assert_eq!(infer_antigravity_event(&v), Some("done".to_string()));
    }

    #[test]
    fn antigravity_no_discriminator_returns_none() {
        let v = json!({"conversationId":"c6","workspacePaths":["/proj"]});
        assert_eq!(infer_antigravity_event(&v), None);
    }

    // --- project extraction ---

    #[test]
    fn project_from_cwd() {
        let v = json!({"cwd":"/home/user/proj","eventName":"PreToolUse"});
        assert_eq!(extract_project(&v), "/home/user/proj");
    }

    #[test]
    fn project_from_workspace_roots() {
        let v = json!({"workspace_roots":["/home/user/proj"]});
        assert_eq!(extract_project(&v), "/home/user/proj");
    }

    #[test]
    fn project_from_workspace_paths_camel_case() {
        let v = json!({"conversationId":"c1","workspacePaths":["/Users/me/proj"],"stepIdx":0});
        assert_eq!(extract_project(&v), "/Users/me/proj");
    }

    #[test]
    fn project_skips_empty_workspace_paths_entries() {
        let v = json!({"workspacePaths":["","/Users/me/proj"]});
        assert_eq!(extract_project(&v), "/Users/me/proj");
    }

    #[test]
    fn project_empty_when_no_field() {
        let v = json!({"conversationId":"c1","stepIdx":0});
        assert_eq!(extract_project(&v), "");
    }
}

/// Minimal HTTP POST to the local listener, bounded by short timeouts so a hook
/// never hangs the agent that invoked it.
fn post(body: &str) -> std::io::Result<()> {
    use std::time::Duration;
    let addr = std::net::SocketAddr::from(([127, 0, 0, 1], crate::server::HOOK_PORT));
    let mut stream = TcpStream::connect_timeout(&addr, Duration::from_millis(500))?;
    stream.set_write_timeout(Some(Duration::from_millis(500)))?;
    stream.set_read_timeout(Some(Duration::from_millis(500)))?;
    let req = format!(
        "POST /event HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    stream.write_all(req.as_bytes())?;
    let mut _resp = String::new();
    let _ = stream.read_to_string(&mut _resp);
    Ok(())
}
