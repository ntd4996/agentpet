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

const CATALOG: &[(&str, &str, Option<&str>)] = &[
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
    ("grok", "Grok Build", Some("xAI Grok Build CLI (~/.grok/hooks/agentpet.json)")),
    ("jcode", "jcode", Some("jcode lifecycle hooks (~/.jcode/config.toml, in WSL when present)")),
];

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
            events: &["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop", "SubagentStop", "SessionEnd", "Interrupt"] },
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
        // xAI Grok Build: ~/.grok/hooks/agentpet.json, Claude-compatible nested
        // shape (PascalCase config keys). PreToolUse is omitted , Grok treats a
        // hook's exit 2 as deny/keep-working, and our hook always exits 0.
        "grok" => Spec { style: Style::ClaudeNested, rel_path: &[".grok", "hooks", "agentpet.json"],
            events: &["SessionStart", "UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"] },
        _ => return None,
    })
}

pub fn catalog() -> Vec<AgentInfo> {
    CATALOG.iter().map(|(kind, name, note)| AgentInfo {
        kind: kind.to_string(),
        display_name: name.to_string(),
        installed: is_installed(kind),
        note: note.map(|s| s.to_string()),
    }).collect()
}

fn config_path_for(kind: &str, home: &std::path::Path) -> Option<PathBuf> {
    let mut p = home.to_path_buf();
    for part in spec(kind)?.rel_path { p.push(part); }
    Some(p)
}
fn config_path(kind: &str) -> Option<PathBuf> {
    config_path_for(kind, &dirs::home_dir()?)
}

fn hook_command() -> String {
    let exe = std::env::current_exe().map(|p| p.to_string_lossy().into_owned()).unwrap_or_else(|_| "agentpet".into());
    format!("\"{}\" hook --agent", exe)
}
fn full_command(kind: &str) -> String { format!("{} {}", hook_command(), kind) }

fn migration_marker_path(home: &std::path::Path, version: &str) -> PathBuf {
    home.join(".agentpet").join(format!("hook-migration-{version}"))
}

fn migration_needed(marker: &std::path::Path) -> bool {
    !marker.exists()
}

fn is_ours(cmd: &str) -> bool {
    let l = cmd.to_lowercase();
    l.contains("agentpet") && l.contains("hook")
}

fn read_json(path: &std::path::Path) -> Value {
    std::fs::read_to_string(path).ok()
        .and_then(|s| if s.trim().is_empty() { None } else { serde_json::from_str(&s).ok() })
        .unwrap_or_else(|| json!({}))
}
fn write_json(path: &std::path::Path, v: &Value) -> std::io::Result<()> {
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
    if kind == "jcode" {
        return jcode_target()
            // A read error here only means "not detected": nothing is written.
            .map(|t| crate::jcode::is_installed(&std::fs::read_to_string(&t.config).unwrap_or_default(), crate::jcode::EVENTS))
            .unwrap_or(false);
    }
    let Some(home) = dirs::home_dir() else { return false };
    is_installed_at(kind, &home)
}

fn is_installed_at(kind: &str, home: &std::path::Path) -> bool {
    let (Some(path), Some(s)) = (config_path_for(kind, home), spec(kind)) else { return false };
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
    if kind == "jcode" { return jcode_install(); }
    let home = dirs::home_dir().ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "home directory not found"))?;
    let path = config_path_for(kind, &home).ok_or_else(|| {
        std::io::Error::new(std::io::ErrorKind::Other, "unknown agent")
    })?;
    install_at(kind, &home, &path)
}

fn install_at(kind: &str, home: &std::path::Path, path: &std::path::Path) -> std::io::Result<()> {
    let Some(s) = spec(kind) else {
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
    if kind == "codex" { enable_codex_hooks_at(home)?; }
    Ok(())
}

/// Re-applies hooks for agents that are already enabled, once per app version.
/// The marker is written before installs so a failed migration is not retried
/// on every launch; users can reinstall a failing agent from Settings.
pub fn migrate_installed_hooks() {
    let Some(home) = dirs::home_dir() else { return };
    let marker = migration_marker_path(&home, env!("CARGO_PKG_VERSION"));
    if !migration_needed(&marker) { return; }
    if let Some(dir) = marker.parent() {
        if let Err(e) = std::fs::create_dir_all(dir) {
            eprintln!("AgentPet hook migration marker failed: {e}");
            return;
        }
    }
    if let Err(e) = std::fs::write(&marker, b"") {
        eprintln!("AgentPet hook migration marker failed: {e}");
        return;
    }

    let kinds: Vec<_> = home_migration_kinds().collect();
    migrate_installed_hooks_for(&home, &kinds);

    // jcode may resolve into WSL or %APPDATA%, so only the real startup wrapper
    // handles it. This function runs on a background thread (see lib.rs).
    if is_installed("jcode") {
        if let Err(e) = install("jcode") {
            eprintln!("AgentPet hook migration failed for jcode: {e}");
        }
    }
}

/// Agent kinds whose settings files are rooted under the caller-provided home.
/// jcode is intentionally excluded because its config may live outside it.
fn home_migration_kinds() -> impl Iterator<Item = &'static str> {
    CATALOG.iter().map(|(kind, _, _)| *kind).filter(|kind| *kind != "jcode")
}

/// Reinstall already-enabled hooks only within `home`; safe for isolated tests.
fn migrate_installed_hooks_for(home: &std::path::Path, kinds: &[&str]) {
    for &kind in kinds {
        let installed = is_installed_at(kind, home);
        if !installed { continue; }
        let Some(path) = config_path_for(kind, home) else { continue };
        let result = install_at(kind, home, &path);
        if let Err(e) = result {
            eprintln!("AgentPet hook migration failed for {kind}: {e}");
        }
    }
}

fn uninstall(kind: &str) -> std::io::Result<()> {
    if kind == "jcode" { return jcode_uninstall(); }
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
         \x20     if (p && p.on) p.on(\"error\", () => {{}})\n\
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
fn enable_codex_hooks_at(home: &std::path::Path) -> std::io::Result<()> {
    let path = home.join(".codex").join("config.toml");
    let text = read_config(&path)?;
    let mut doc = text.parse::<toml_edit::DocumentMut>().map_err(|e| {
        std::io::Error::new(std::io::ErrorKind::InvalidData, format!("{}: {e}", path.display()))
    })?;
    if !doc.contains_key("features") {
        doc["features"] = toml_edit::Item::Table(toml_edit::Table::new());
    }
    let features = doc["features"].as_table_like_mut().ok_or_else(|| {
        std::io::Error::new(std::io::ErrorKind::InvalidData, "Codex features must be a TOML table")
    })?;
    if features.get("hooks").and_then(toml_edit::Item::as_bool) == Some(true) { return Ok(()); }
    features.insert("hooks", toml_edit::value(true));
    if let Some(dir) = path.parent() { std::fs::create_dir_all(dir)?; }
    std::fs::write(&path, doc.to_string())
}

// ----- jcode (TOML [hooks], usually inside WSL) -----------------------------

/// Where jcode's config lives and what hook command jcode should run.
struct JcodeTarget {
    config: PathBuf,
    command: String,
}

/// Prefer the default WSL distro's `~/.jcode` (jcode is a Linux/macOS CLI and on
/// Windows it typically runs under WSL), else a native `%USERPROFILE%\.jcode`.
/// simplify: default distro only; a per-distro picker is the upgrade path.
fn jcode_target() -> Option<JcodeTarget> {
    let exe = std::env::current_exe().ok()?;
    let (home, via_wsl) = jcode_home()?;
    let config = home.join(".jcode").join("config.toml");
    let command = if via_wsl {
        crate::jcode::hook_command(&windows_to_wsl_path(&exe.to_string_lossy()), true)
    } else {
        crate::jcode::hook_command(&exe.to_string_lossy(), false)
    };
    Some(JcodeTarget { config, command })
}

/// `C:\Users\A\x.exe` -> `/mnt/c/Users/A/x.exe` (WSL's default automount root).
/// simplify: assumes automount root /mnt; a custom root in /etc/wsl.conf would
/// need `wslpath -u` instead.
pub fn windows_to_wsl_path(p: &str) -> String {
    let p = p.trim_start_matches(r"\\?\");
    let mut chars = p.chars();
    match (chars.next(), chars.next()) {
        (Some(d), Some(':')) if d.is_ascii_alphabetic() => {
            format!("/mnt/{}{}", d.to_ascii_lowercase(), p[2..].replace('\\', "/"))
        }
        _ => p.replace('\\', "/"),
    }
}

fn jcode_write(path: &PathBuf, text: &str) -> std::io::Result<()> {
    if let Some(dir) = path.parent() { std::fs::create_dir_all(dir)?; }
    // Write-then-rename: jcode re-reads config.toml on change, never a partial one.
    let tmp = path.with_extension("toml.agentpet-tmp");
    std::fs::write(&tmp, text)?;
    std::fs::rename(&tmp, path)
}

/// Reads config.toml. A missing file is an empty config (first install); ANY
/// other error (a `\\wsl.localhost` hiccup while the VM starts, a permission
/// error, non-UTF-8 content) is returned so the caller aborts. Treating those as
/// "empty" would make install rewrite the file with only the `[hooks]` block and
/// wipe the user's jcode config.
fn read_config(path: &PathBuf) -> std::io::Result<String> {
    match std::fs::read_to_string(path) {
        Ok(s) => Ok(s),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(String::new()),
        Err(e) => Err(e),
    }
}

fn jcode_install() -> std::io::Result<()> {
    // Enabling jcode is the one moment we look for it inside WSL (see the note on
    // jcode_home): opt-in, with a timeout, and we are already off the UI thread.
    probe_jcode_wsl();
    let t = jcode_target().ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "jcode config not found"))?;
    let existing = read_config(&t.config)?;
    let updated = crate::jcode::install(&existing, &t.command, crate::jcode::EVENTS)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
    if updated != existing { jcode_write(&t.config, &updated)?; }
    Ok(())
}

fn jcode_uninstall() -> std::io::Result<()> {
    // No probe here: uninstall edits the config where install put it (the cached
    // WSL home). If WSL is down the read fails and we abort instead of editing
    // the native config and leaving the WSL hooks behind.
    let Some(t) = jcode_target() else { return Ok(()) };
    let existing = read_config(&t.config)?;
    let updated = crate::jcode::uninstall(&existing, crate::jcode::EVENTS);
    if updated != existing { jcode_write(&t.config, &updated)?; }
    Ok(())
}

#[cfg(test)]
mod jcode_path_tests {
    use super::windows_to_wsl_path;

    #[test]
    fn converts_drive_paths() {
        assert_eq!(windows_to_wsl_path(r"C:\Users\HocSys\AppData\Local\AgentPet\agentpet.exe"),
                   "/mnt/c/Users/HocSys/AppData/Local/AgentPet/agentpet.exe");
        assert_eq!(windows_to_wsl_path(r"\\?\D:\A B\x.exe"), "/mnt/d/A B/x.exe");
    }
}

// ----- jcode home (shared by limits and the jcode hooks) --------------------
//
// jcode usually runs inside WSL, so its home is `\\wsl.localhost\<distro>\<home>`.
// Finding it needs `wsl.exe`, which boots the WSL VM (vmmem) when it is off. So:
//   * `jcode_home()` NEVER spawns anything: it answers from a cache (memory,
//     seeded from a small marker file) and falls back to the native home.
//   * `probe_jcode_wsl()` is the only place that spawns `wsl.exe`. It has a
//     timeout and is meant to run only once jcode is known to be in use (the
//     user enables jcode in Settings > Agents), always off the UI thread. A hung
//     `wsl.exe` (broken distro, first-run prompt) can therefore never block a
//     caller of `jcode_home()`.
// Claude-only users, with or without WSL, never trigger a probe.

use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

/// How long `wsl.exe` gets before it is killed. Booting a cold VM takes a few seconds.
#[cfg_attr(not(windows), allow(dead_code))]
const WSL_PROBE_TIMEOUT: Duration = Duration::from_secs(8);

/// `%APPDATA%\AgentPet\jcode_wsl_home`: one line, the UNC home of the WSL distro
/// where jcode lives. Written by a successful probe so later launches know
/// without spawning `wsl.exe`. Delete the file to forget it.
fn wsl_marker() -> Option<PathBuf> {
    dirs::config_dir().map(|d| d.join("AgentPet").join("jcode_wsl_home"))
}

fn wsl_cache() -> &'static Mutex<Option<PathBuf>> {
    static C: OnceLock<Mutex<Option<PathBuf>>> = OnceLock::new();
    C.get_or_init(|| {
        let saved = wsl_marker()
            .and_then(|p| std::fs::read_to_string(p).ok())
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .map(PathBuf::from);
        Mutex::new(saved)
    })
}

/// The home directory jcode uses, as a path this process can open, plus whether
/// it is inside WSL. Cache lookup only (see the block comment above): the WSL
/// home is known after `probe_jcode_wsl` found one, else the native home.
pub fn jcode_home() -> Option<(PathBuf, bool)> {
    if let Some(wsl) = wsl_cache().lock().unwrap_or_else(|e| e.into_inner()).clone() {
        return Some((wsl, true));
    }
    dirs::home_dir().map(|h| (h, false))
}

/// Looks for jcode in the default WSL distro and remembers the answer (also
/// forgets a stale one). BLOCKS up to `WSL_PROBE_TIMEOUT` plus a UNC lookup, so
/// call it from a worker (`spawn_blocking` / a thread), never from the UI thread.
pub fn probe_jcode_wsl() {
    #[cfg(windows)]
    {
        let found = wsl_default_home().and_then(|(distro, home)| {
            let unc = PathBuf::from(format!(r"\\wsl.localhost\{}{}", distro, home.replace('/', r"\")));
            unc.join(".jcode").is_dir().then_some(unc)
        });
        *wsl_cache().lock().unwrap_or_else(|e| e.into_inner()) = found.clone();
        if let Some(m) = wsl_marker() {
            match found {
                Some(unc) => {
                    if let Some(dir) = m.parent() { let _ = std::fs::create_dir_all(dir); }
                    let _ = std::fs::write(m, unc.to_string_lossy().as_bytes());
                }
                None => { let _ = std::fs::remove_file(m); }
            }
        }
    }
}

/// Runs `cmd` with stdout captured and kills it after `timeout`. `None` on a
/// spawn error, a timeout, or a non-zero exit. Std only, so it is unit-tested.
#[cfg_attr(not(windows), allow(dead_code))]
fn run_with_timeout(mut cmd: std::process::Command, timeout: Duration) -> Option<Vec<u8>> {
    use std::io::Read;
    use std::process::Stdio;
    let mut child = cmd.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().ok()?;
    let mut stdout = child.stdout.take()?;
    // Read on a thread so a full pipe can't stall the child while we poll it.
    let reader = std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = stdout.read_to_end(&mut buf);
        buf
    });
    let deadline = Instant::now() + timeout;
    let status = loop {
        match child.try_wait() {
            Ok(Some(st)) => break st,
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(40)),
            // Timed out (or wait failed): kill it. The reader thread ends by
            // itself once the pipe closes, so it is not joined here.
            _ => { let _ = child.kill(); let _ = child.wait(); return None; }
        }
    };
    if !status.success() { return None; }
    reader.join().ok()
}

/// (distro, $HOME) of the default WSL distro, via `wsl.exe`. None without WSL
/// or when it does not answer in time.
#[cfg(windows)]
fn wsl_default_home() -> Option<(String, String)> {
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    let mut cmd = std::process::Command::new("wsl.exe");
    cmd.args(["-e", "sh", "-c", "printf '%s\\n%s' \"$WSL_DISTRO_NAME\" \"$HOME\""])
        .creation_flags(CREATE_NO_WINDOW);
    let out = run_with_timeout(cmd, WSL_PROBE_TIMEOUT)?;
    let text = String::from_utf8_lossy(&out).replace('\r', "");
    let mut it = text.lines();
    let distro = it.next()?.trim().to_string();
    let home = it.next()?.trim().to_string();
    (!distro.is_empty() && home.starts_with('/')).then_some((distro, home))
}

#[cfg(test)]
mod read_config_tests {
    use super::*;

    #[test]
    fn missing_file_is_empty_but_other_errors_abort() {
        let dir = std::env::temp_dir().join(format!("ap-readcfg-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        assert_eq!(read_config(&dir.join("nope.toml")).unwrap(), "");
        // Non-UTF-8 content must be an error, never silently "empty".
        let bad = dir.join("bad.toml");
        std::fs::write(&bad, [0xff, 0xfe, 0x00]).unwrap();
        assert!(read_config(&bad).is_err());
        // A directory where a file is expected is not NotFound either.
        assert!(read_config(&dir).is_err());
        std::fs::remove_dir_all(&dir).ok();
    }
}

#[cfg(test)]
mod timeout_tests {
    use super::*;

    #[cfg(unix)]
    #[test]
    fn returns_output_of_a_quick_command() {
        let mut c = std::process::Command::new("sh");
        c.args(["-c", "printf hi"]);
        assert_eq!(run_with_timeout(c, Duration::from_secs(5)).as_deref(), Some(&b"hi"[..]));
    }

    #[cfg(unix)]
    #[test]
    fn kills_a_hung_command() {
        let mut c = std::process::Command::new("sh");
        c.args(["-c", "sleep 30"]);
        let t = Instant::now();
        assert!(run_with_timeout(c, Duration::from_millis(300)).is_none());
        assert!(t.elapsed() < Duration::from_secs(5), "must not wait for the child");
    }

    #[cfg(unix)]
    #[test]
    fn non_zero_exit_is_none() {
        let mut c = std::process::Command::new("sh");
        c.args(["-c", "exit 3"]);
        assert!(run_with_timeout(c, Duration::from_secs(5)).is_none());
    }
}

#[cfg(test)]
mod codex_spec_tests {
    use super::*;

    #[test]
    fn enabling_codex_replaces_false_in_features_only() {
        let home = migration_tests::temp_home();
        let path = home.join(".codex/config.toml");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        for text in [
            "[features]\nhooks = false\n",
            "[other]\nhooks = true\n[features]\nhooks = false # user setting\nkeep = true\n",
            "# user config\n[features] # feature flags\n'hooks' = false\n[other]\nhooks = false\n",
            "features = { hooks = false, keep = true }\n",
            "[features]\nkeep = true\n[other]\nhooks = false\n",
            "",
        ] {
            std::fs::write(&path, text).unwrap();
            enable_codex_hooks_at(&home).unwrap();
            let updated = std::fs::read_to_string(&path).unwrap();
            let parsed = updated.parse::<toml_edit::DocumentMut>().expect("enabled config must be valid TOML");
            assert_eq!(parsed["features"]["hooks"].as_bool(), Some(true));
            let original = text.parse::<toml_edit::DocumentMut>().unwrap();
            if original.get("other").is_some() {
                assert_eq!(parsed["other"].to_string(), original["other"].to_string());
            }
            enable_codex_hooks_at(&home).unwrap();
            assert_eq!(std::fs::read_to_string(&path).unwrap(), updated);
        }
        std::fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn enabling_codex_does_not_overwrite_invalid_or_unreadable_toml() {
        let home = migration_tests::temp_home();
        let path = home.join(".codex/config.toml");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        for bytes in [b"[features\nhooks=false".as_slice(), b"features = false", &[0xff]] {
            std::fs::write(&path, bytes).unwrap();
            assert!(enable_codex_hooks_at(&home).is_err());
            assert_eq!(std::fs::read(&path).unwrap(), bytes);
        }
        std::fs::remove_file(&path).unwrap();
        std::fs::create_dir(&path).unwrap();
        assert!(enable_codex_hooks_at(&home).is_err());
        std::fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn codex_registers_session_end_and_interrupt() {
        let events = spec("codex").unwrap().events;
        assert!(events.contains(&"SessionEnd"));
        assert!(events.contains(&"Interrupt"));
    }
}

#[cfg(test)]
mod migration_tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    pub(super) fn temp_home() -> PathBuf {
        static NEXT_ID: AtomicU64 = AtomicU64::new(0);
        let suffix = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
        let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!("agentpet-hook-migration-{}-{suffix}-{id}", std::process::id()));
        std::fs::create_dir(&path).unwrap();
        path
    }

    #[test]
    fn marker_runs_once_per_version() {
        let home = temp_home();
        let marker = migration_marker_path(&home, "1.0.0");
        assert!(migration_needed(&marker));
        std::fs::create_dir_all(marker.parent().unwrap()).unwrap();
        std::fs::write(&marker, b"").unwrap();
        assert!(!migration_needed(&marker));
        assert!(migration_needed(&migration_marker_path(&home, "1.0.1")));
        std::fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn home_migration_kinds_exclude_agents_outside_home() {
        assert!(!home_migration_kinds().any(|kind| kind == "jcode"));
    }

    #[test]
    fn migrates_installed_codex_without_creating_uninstalled_gemini() {
        let home = temp_home();
        let codex = config_path_for("codex", &home).unwrap();
        let old_events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop", "SubagentStop"];
        let mut hooks = serde_json::Map::new();
        for event in old_events {
            hooks.insert(event.into(), json!([{ "hooks": [{ "type": "command", "command": "agentpet hook --agent codex" }] }]));
        }
        hooks.insert("SessionEnd".into(), json!([{ "hooks": [{ "type": "command", "command": "someone-else" }] }]));
        let mut root = serde_json::Map::new();
        root.insert("hooks".into(), Value::Object(hooks));
        write_json(&codex, &Value::Object(root)).unwrap();

        let kinds: Vec<_> = home_migration_kinds().collect();
        migrate_installed_hooks_for(&home, &kinds);

        let migrated = read_json(&codex);
        let codex_hooks = migrated.get("hooks").unwrap();
        for event in spec("codex").unwrap().events {
            assert!(codex_hooks.get(event).and_then(Value::as_array).is_some(), "missing {event}");
        }
        assert_eq!(
            codex_hooks.get("SessionEnd").unwrap().as_array().unwrap().len(),
            2,
            "foreign hook must remain alongside AgentPet's hook"
        );
        assert!(!home.join(".gemini/settings.json").exists());
        migrate_installed_hooks_for(&home, &kinds);
        assert_eq!(
            read_json(&codex).get("hooks").unwrap().get("SessionEnd").unwrap().as_array().unwrap().len(),
            2
        );
        std::fs::remove_dir_all(home).unwrap();
    }
}
