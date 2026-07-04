//! Writes/removes AgentPet's hook entries in each agent's config, using Windows
//! paths (%USERPROFILE%\.claude\settings.json, ...). Ported from the macOS app's
//! AgentHooks + HookInstaller. Our entries are identified by their command
//! string so install is idempotent and foreign hooks are never touched.

use serde::Serialize;
use serde_json::{json, Value};
use std::path::PathBuf;

#[derive(Serialize, Clone)]
pub struct AgentInfo {
    pub kind: String,
    pub display_name: String,
    pub installed: bool,
    pub note: Option<String>,
}

#[derive(Clone, Copy, PartialEq)]
enum Style {
    ClaudeNested,      // {"hooks": {Event: [{"hooks": [{"type":"command","command":..}]}]}}
    CursorFlat,        // {"version":1,"hooks":{event:[{"command":..,"type":"command"}]}}
    WindsurfFlat,      // {"hooks":{event:[{"command":..,"show_output":false}]}}
    KiroFlat,          // agent file: {"name":..,"hooks":{event:[{"command":..}]}}
    AntigravityNested, // {"agentpet": {Event: [..]}} (matcher events vs bare handlers)
    OpencodePlugin,    // a JS plugin file
    PiExtension,       // a TS extension file for Pi (~/.pi/agent/extensions)
}

struct Spec {
    style: Style,
    rel_path: &'static [&'static str],
    events: &'static [&'static str],
}

fn spec(kind: &str) -> Option<Spec> {
    Some(match kind {
        "claude" => Spec { style: Style::ClaudeNested, rel_path: &[".claude", "settings.json"],
            events: &["SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SubagentStop", "SessionEnd"] },
        "codex" => Spec { style: Style::ClaudeNested, rel_path: &[".codex", "hooks.json"],
            events: &["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop", "SubagentStop"] },
        "gemini" => Spec { style: Style::ClaudeNested, rel_path: &[".gemini", "settings.json"],
            events: &["SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "Notification", "AfterAgent", "SessionEnd"] },
        "cursor" => Spec { style: Style::CursorFlat, rel_path: &[".cursor", "hooks.json"],
            events: &["sessionStart", "beforeSubmitPrompt", "preToolUse", "stop", "subagentStop", "sessionEnd"] },
        "copilot" => Spec { style: Style::CursorFlat, rel_path: &[".copilot", "hooks", "agentpet.json"],
            events: &["SessionStart", "UserPromptSubmit", "PostToolUse", "Stop"] },
        "windsurf" => Spec { style: Style::WindsurfFlat, rel_path: &[".codeium", "windsurf", "hooks.json"],
            events: &["pre_user_prompt", "post_cascade_response"] },
        "antigravity" => Spec { style: Style::AntigravityNested, rel_path: &[".gemini", "config", "hooks.json"],
            events: &["PreInvocation", "PreToolUse", "PostToolUse", "Stop"] },
        "kiro" => Spec { style: Style::KiroFlat, rel_path: &[".kiro", "agents", "default.json"],
            events: &["agentSpawn", "userPromptSubmit", "postToolUse", "stop"] },
        "opencode" => Spec { style: Style::OpencodePlugin, rel_path: &[".config", "opencode", "plugin", "agentpet.js"],
            events: &[] },
        "droid" => Spec { style: Style::ClaudeNested, rel_path: &[".factory", "hooks.json"],
            events: &["SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SubagentStop", "SessionEnd"] },
        "pi" => Spec { style: Style::PiExtension, rel_path: &[".pi", "agent", "extensions", "agentpet.ts"],
            events: &[] },
        _ => return None,
    })
}

pub fn catalog() -> Vec<AgentInfo> {
    let entries: &[(&str, &str, Option<&str>)] = &[
        ("claude", "Claude Code", None),
        ("codex", "Codex", Some("After enabling, run /hooks in Codex and Trust the AgentPet hook")),
        ("gemini", "Gemini CLI", None),
        ("cursor", "Cursor", None),
        ("opencode", "opencode", None),
        ("windsurf", "Windsurf", Some("No \"needs input\" alerts (Windsurf has no such hook)")),
        ("antigravity", "Antigravity", Some("No \"needs input\" alerts (Antigravity has no notification hook)")),
        ("copilot", "GitHub Copilot", Some("Copilot CLI only (~/.copilot/hooks)")),
        ("kiro", "Kiro CLI", Some("Hooks the default Kiro CLI agent")),
        ("droid", "Factory Droid", Some("Factory Droid CLI (~/.factory/hooks.json)")),
        ("pi", "Pi", Some("Pi extension (~/.pi/agent/extensions). No \"needs input\" alerts")),
    ];
    entries.iter().map(|(kind, name, note)| AgentInfo {
        kind: kind.to_string(),
        display_name: name.to_string(),
        installed: is_installed(kind),
        note: note.map(|s| s.to_string()),
    }).collect()
}

fn config_path(kind: &str) -> Option<PathBuf> {
    let mut p = dirs::home_dir()?;
    for part in spec(kind)?.rel_path { p.push(part); }
    Some(p)
}

fn hook_command() -> String {
    let exe = std::env::current_exe().map(|p| p.to_string_lossy().into_owned()).unwrap_or_else(|_| "agentpet".into());
    format!("\"{}\" hook --agent", exe)
}
fn full_command(kind: &str) -> String { format!("{} {}", hook_command(), kind) }

fn is_ours(cmd: &str) -> bool {
    let l = cmd.to_lowercase();
    l.contains("agentpet") && l.contains("hook")
}

fn read_json(path: &PathBuf) -> Value {
    std::fs::read_to_string(path).ok()
        .and_then(|s| if s.trim().is_empty() { None } else { serde_json::from_str(&s).ok() })
        .unwrap_or_else(|| json!({}))
}
fn write_json(path: &PathBuf, v: &Value) -> std::io::Result<()> {
    if let Some(dir) = path.parent() { std::fs::create_dir_all(dir)?; }
    std::fs::write(path, serde_json::to_string_pretty(v).unwrap_or_default())
}

// ----- per-style entry helpers --------------------------------------------
fn container_key(style: Style) -> &'static str {
    if style == Style::AntigravityNested { "agentpet" } else { "hooks" }
}
fn antigravity_matcher(event: &str) -> bool {
    matches!(event, "PreToolUse" | "PostToolUse")
}
fn group_is_ours(entry: &Value) -> bool {
    entry.get("hooks").and_then(|h| h.as_array())
        .map(|a| a.iter().any(|h| h.get("command").and_then(|c| c.as_str()).map(is_ours).unwrap_or(false)))
        .unwrap_or(false)
}
fn flat_is_ours(entry: &Value) -> bool {
    entry.get("command").and_then(|c| c.as_str()).map(is_ours).unwrap_or(false)
}
fn entry_is_ours(style: Style, event: &str, entry: &Value) -> bool {
    match style {
        Style::ClaudeNested => group_is_ours(entry),
        Style::AntigravityNested => if antigravity_matcher(event) { group_is_ours(entry) } else { flat_is_ours(entry) },
        _ => flat_is_ours(entry),
    }
}
fn make_entry(style: Style, event: &str, cmd: &str) -> Value {
    match style {
        Style::ClaudeNested => json!({ "hooks": [{ "type": "command", "command": cmd }] }),
        Style::CursorFlat => json!({ "command": cmd, "type": "command" }),
        Style::WindsurfFlat => json!({ "command": cmd, "show_output": false }),
        Style::KiroFlat => json!({ "command": cmd }),
        Style::AntigravityNested => if antigravity_matcher(event) {
            json!({ "matcher": "*", "hooks": [{ "type": "command", "command": cmd }] })
        } else {
            json!({ "type": "command", "command": cmd })
        },
        Style::OpencodePlugin | Style::PiExtension => Value::Null,
    }
}

// ----- public API ----------------------------------------------------------
pub fn is_installed(kind: &str) -> bool {
    let (Some(path), Some(s)) = (config_path(kind), spec(kind)) else { return false };
    if s.style == Style::OpencodePlugin || s.style == Style::PiExtension {
        return std::fs::read_to_string(&path).map(|c| is_ours(&c)).unwrap_or(false);
    }
    let v = read_json(&path);
    let Some(map) = v.get(container_key(s.style)).and_then(|h| h.as_object()) else { return false };
    s.events.iter().any(|event| {
        map.get(*event).and_then(|a| a.as_array())
            .map(|arr| arr.iter().any(|e| entry_is_ours(s.style, event, e)))
            .unwrap_or(false)
    })
}

pub fn toggle(kind: &str) -> Result<bool, String> {
    if is_installed(kind) {
        uninstall(kind).map_err(|e| e.to_string())?;
        Ok(false)
    } else {
        install(kind).map_err(|e| e.to_string())?;
        Ok(true)
    }
}

fn install(kind: &str) -> std::io::Result<()> {
    let (Some(path), Some(s)) = (config_path(kind), spec(kind)) else {
        return Err(std::io::Error::new(std::io::ErrorKind::Other, "unknown agent"));
    };
    let cmd = full_command(kind);

    if s.style == Style::OpencodePlugin {
        if let Some(dir) = path.parent() { std::fs::create_dir_all(dir)?; }
        return std::fs::write(&path, opencode_plugin(&binary_from(&cmd)));
    }
    if s.style == Style::PiExtension {
        if let Some(dir) = path.parent() { std::fs::create_dir_all(dir)?; }
        return std::fs::write(&path, pi_extension(&binary_from(&cmd)));
    }

    let mut v = read_json(&path);
    let Some(obj) = v.as_object_mut() else {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,
            format!("{} is not a JSON object; fix or remove it and try again", path.display())));
    };
    if s.style == Style::CursorFlat { obj.entry("version").or_insert(json!(1)); }
    // A fresh Kiro agent file needs a name to be a valid agent.
    if s.style == Style::KiroFlat && obj.get("name").is_none() {
        let name = path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_else(|| "default".into());
        obj.insert("name".to_string(), json!(name));
    }
    let key = container_key(s.style);
    if !obj.get(key).map_or(false, |h| h.is_object()) { obj.insert(key.to_string(), json!({})); }
    let map = obj.get_mut(key).and_then(|h| h.as_object_mut()).unwrap();
    for event in s.events {
        let mut kept: Vec<Value> = map.get(*event).and_then(|a| a.as_array())
            .map(|a| a.iter().filter(|e| !entry_is_ours(s.style, event, e)).cloned().collect())
            .unwrap_or_default();
        kept.push(make_entry(s.style, event, &cmd));
        map.insert((*event).to_string(), Value::Array(kept));
    }
    write_json(&path, &v)?;
    if kind == "codex" { enable_codex_hooks(); }
    Ok(())
}

fn uninstall(kind: &str) -> std::io::Result<()> {
    let (Some(path), Some(s)) = (config_path(kind), spec(kind)) else { return Ok(()) };
    // Files we own outright: just delete.
    if kind == "copilot" || s.style == Style::OpencodePlugin || s.style == Style::PiExtension {
        let _ = std::fs::remove_file(&path);
        return Ok(());
    }
    let mut v = read_json(&path);
    let Some(obj) = v.as_object_mut() else { return Ok(()) };
    let key = container_key(s.style);
    if let Some(map) = obj.get_mut(key).and_then(|h| h.as_object_mut()) {
        for event in s.events {
            if let Some(arr) = map.get(*event).and_then(|a| a.as_array()) {
                let kept: Vec<Value> = arr.iter().filter(|e| !entry_is_ours(s.style, event, e)).cloned().collect();
                if kept.is_empty() { map.remove(*event); } else { map.insert((*event).to_string(), Value::Array(kept)); }
            }
        }
        if map.is_empty() { obj.remove(key); }
    }
    write_json(&path, &v)
}

/// Extracts the quoted binary path from a hook command for the opencode plugin.
fn binary_from(cmd: &str) -> String {
    if let Some(start) = cmd.find('"') {
        if let Some(end) = cmd[start + 1..].find('"') {
            return cmd[start + 1..start + 1 + end].to_string();
        }
    }
    cmd.split(' ').next().unwrap_or(cmd).to_string()
}

fn opencode_plugin(binary: &str) -> String {
    let bin = serde_json::to_string(binary).unwrap_or_else(|_| format!("\"{}\"", binary));
    format!(
        "// AgentPet integration (auto-generated, safe to delete to uninstall).\n\
         const AGENTPET_BIN = {bin}\n\
         export const AgentPet = async ({{ directory }}) => {{\n\
         \x20 const sid = \"opencode:\" + (directory || \"default\")\n\
         \x20 const send = (state) => {{ try {{ Bun.spawn([AGENTPET_BIN, \"hook\", \"--agent\", \"opencode\", \"--event\", state, \"--session\", sid, \"--project\", directory || \"\"]) }} catch (e) {{}} }}\n\
         \x20 return {{ \"session.created\": async () => {{ send(\"working\") }}, \"session.idle\": async () => {{ send(\"done\") }} }}\n\
         }}\n"
    )
}

/// The Pi extension: reports session lifecycle through the `agentpet hook` CLI.
fn pi_extension(binary: &str) -> String {
    let bin = serde_json::to_string(binary).unwrap_or_else(|_| format!("\"{}\"", binary));
    format!(
        "// AgentPet integration (auto-generated, safe to delete to uninstall).\n\
         // Reports Pi session lifecycle to AgentPet's menu bar app.\n\
         import {{ spawn }} from \"node:child_process\"\n\
         const AGENTPET_BIN = {bin}\n\
         export default function (pi) {{\n\
         \x20 const send = (state, ctx) => {{\n\
         \x20   try {{\n\
         \x20     const cwd = (ctx && ctx.cwd) || process.cwd()\n\
         \x20     const file = ctx && ctx.sessionManager && ctx.sessionManager.getSessionFile ? ctx.sessionManager.getSessionFile() : null\n\
         \x20     const sid = \"pi:\" + (file || cwd)\n\
         \x20     const p = spawn(AGENTPET_BIN, [\"hook\", \"--agent\", \"pi\", \"--event\", state, \"--session\", sid, \"--project\", cwd], {{ stdio: \"ignore\" }})\n\
         \x20     if (p && p.unref) p.unref()\n\
         \x20   }} catch (e) {{}}\n\
         \x20 }}\n\
         \x20 pi.on(\"session_start\", async (_e, ctx) => send(\"registered\", ctx))\n\
         \x20 pi.on(\"agent_start\", async (_e, ctx) => send(\"working\", ctx))\n\
         \x20 pi.on(\"agent_end\", async (_e, ctx) => send(\"done\", ctx))\n\
         \x20 pi.on(\"session_shutdown\", async (_e, ctx) => send(\"done\", ctx))\n\
         }}\n"
    )
}

/// Ensure `[features] hooks = true` in ~/.codex/config.toml (modern key; the
/// `codex_hooks` alias is ignored by recent Codex).
fn enable_codex_hooks() {
    let Some(home) = dirs::home_dir() else { return };
    let path = home.join(".codex").join("config.toml");
    let text = std::fs::read_to_string(&path).unwrap_or_default();
    let already = text.lines().any(|l| {
        let c = l.trim().replace(' ', "");
        !c.starts_with('#') && c.starts_with("hooks=true")
    });
    if already { return; }
    let updated = if let Some(idx) = text.lines().position(|l| l.trim() == "[features]") {
        let mut lines: Vec<String> = text.lines().map(|s| s.to_string()).collect();
        lines.insert(idx + 1, "hooks = true".into());
        lines.join("\n")
    } else {
        let mut t = text;
        if !t.is_empty() && !t.ends_with('\n') { t.push('\n'); }
        t.push_str("\n[features]\nhooks = true\n");
        t
    };
    if let Some(dir) = path.parent() { let _ = std::fs::create_dir_all(dir); }
    let _ = std::fs::write(&path, updated);
}
