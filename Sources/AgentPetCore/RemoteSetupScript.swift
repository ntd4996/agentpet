import Foundation

/// Generates the self-contained bash setup script served over `GET /setup.sh`
/// or copied from the Settings UI onto a remote server/VPS.
public enum RemoteSetupScript {
    public static func generate() -> String {
        return #"""
#!/usr/bin/env bash
# ==============================================================================
# AgentPet Remote Server Setup Script
# Configures coding agent hooks on remote Linux/Unix servers to forward events
# to your local AgentPet via SSH Remote Port Forwarding (`ssh -R`).
# ==============================================================================

set -e

PORT="3838"
ENDPOINT="http://127.0.0.1:3838"
TOKEN=""
HOST_LABEL="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "remote-vps")"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token) TOKEN="$2"; shift 2 ;;
    --port) PORT="$2"; ENDPOINT="http://127.0.0.1:$PORT"; shift 2 ;;
    --url) ENDPOINT="${2%/}"; shift 2 ;;
    --host) HOST_LABEL="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$TOKEN" ]; then
  echo "❌ Error: --token is required."
  echo "Usage: curl -fsSL http://127.0.0.1:3838/setup.sh | bash -s -- --token <YOUR_TOKEN> [--port 3838]"
  exit 1
fi

AGENTPET_DIR="$HOME/.agentpet"
HOOK_SCRIPT="$AGENTPET_DIR/agentpet-hook.sh"
SEND_CLI="$AGENTPET_DIR/agentpet-send"

mkdir -p "$AGENTPET_DIR"

echo "🐶 Setting up AgentPet Remote Hooks on $HOST_LABEL..."

# 1. Generate hook script (~/.agentpet/agentpet-hook.sh)
cat << 'EOF' > "$HOOK_SCRIPT"
#!/usr/bin/env bash
# AgentPet Remote Hook Forwarder (Non-blocking fail-safe)
AGENT="generic"
SESSION=""
EVENT=""
MESSAGE=""
MODEL=""
TITLE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --event) EVENT="$2"; shift 2 ;;
    --session) SESSION="$2"; shift 2 ;;
    --message) MESSAGE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

ENDPOINT="__AGENTPET_ENDPOINT__"
TOKEN="__AGENTPET_TOKEN__"
HOSTNAME="__AGENTPET_HOST__"

(
  if [ -n "$STDIN_DATA" ]; then
    curl -s --connect-timeout 2 --max-time 3 \
      -X POST "${ENDPOINT}/api/events?agent=${AGENT}&host=${HOSTNAME}" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      --data-raw "$STDIN_DATA" &> /dev/null
  else
    JSON="{\"agent\":\"$AGENT\",\"event\":\"${EVENT:-working}\",\"sessionId\":\"${SESSION:-remote-$HOSTNAME}\",\"message\":\"$MESSAGE\",\"model\":\"$MODEL\",\"title\":\"$TITLE\",\"host\":\"$HOSTNAME\"}"
    curl -s --connect-timeout 2 --max-time 3 \
      -X POST "${ENDPOINT}/api/events?agent=${AGENT}&host=${HOSTNAME}" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      --data-raw "$JSON" &> /dev/null
  fi
) &> /dev/null &

exit 0
EOF

# Substitute config values into the hook script
sed -i.bak "s|__AGENTPET_ENDPOINT__|$ENDPOINT|g" "$HOOK_SCRIPT" 2>/dev/null || sed -i "" "s|__AGENTPET_ENDPOINT__|$ENDPOINT|g" "$HOOK_SCRIPT"
sed -i.bak "s|__AGENTPET_TOKEN__|$TOKEN|g" "$HOOK_SCRIPT" 2>/dev/null || sed -i "" "s|__AGENTPET_TOKEN__|$TOKEN|g" "$HOOK_SCRIPT"
sed -i.bak "s|__AGENTPET_HOST__|$HOST_LABEL|g" "$HOOK_SCRIPT" 2>/dev/null || sed -i "" "s|__AGENTPET_HOST__|$HOST_LABEL|g" "$HOOK_SCRIPT"
rm -f "${HOOK_SCRIPT}.bak"

chmod +x "$HOOK_SCRIPT"

# 2. Generate generic CLI helper (~/.agentpet/agentpet-send)
cat << 'EOF' > "$SEND_CLI"
#!/usr/bin/env bash
# Generic AgentPet event dispatcher for custom scripts
EVENT="${1:-working}"
MESSAGE="${2:-Running remote task}"
AGENT="${3:-generic}"
"$HOME/.agentpet/agentpet-hook.sh" --agent "$AGENT" --event "$EVENT" --message "$MESSAGE"
EOF
chmod +x "$SEND_CLI"

echo "  ✔ Created $HOOK_SCRIPT"
echo "  ✔ Created $SEND_CLI"

# 3. Detect and configure coding agents
INSTALLED_COUNT=0

# Python helper for safe JSON manipulation
update_json_hooks() {
  local file="$1"
  local agent="$2"
  python3 -c "
import json, os, sys

path = os.path.expanduser('$file')
os.makedirs(os.path.dirname(path), exist_ok=True)
data = {}
if os.path.exists(path):
    try:
        with open(path, 'r') as f:
            data = json.load(f)
    except Exception:
        pass

agent = '$agent'
hook_cmd = '$HOOK_SCRIPT --agent ' + agent

if agent in ['claude', 'codex']:
    hooks = data.setdefault('hooks', {})
    events = ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'Stop', 'SubagentStop', 'SessionEnd']
    for ev in events:
        groups = hooks.setdefault(ev, [])
        # filter out existing agentpet hooks
        groups = [g for g in groups if not any('agentpet-hook.sh' in str(h.get('command','')) for h in g.get('hooks', []))]
        groups.append({'hooks': [{'type': 'command', 'command': hook_cmd}]})
        hooks[ev] = groups
elif agent == 'antigravity':
    # Antigravity hook format: under 'agentpet' group
    ag_group = data.setdefault('agentpet', {})
    for ev in ['PreInvocation', 'PreToolUse', 'PostToolUse', 'Stop']:
        if ev in ['PreToolUse', 'PostToolUse']:
            groups = ag_group.setdefault(ev, [])
            groups = [g for g in groups if not any('agentpet-hook.sh' in str(h.get('command','')) for h in g.get('hooks', []))]
            groups.append({'hooks': [{'type': 'command', 'command': hook_cmd}]})
            ag_group[ev] = groups
        else:
            handlers = ag_group.setdefault(ev, [])
            handlers = [h for h in handlers if 'agentpet-hook.sh' not in str(h.get('command',''))]
            handlers.append({'type': 'command', 'command': hook_cmd})
            ag_group[ev] = handlers
elif agent in ['cursor', 'copilot']:
    hooks = data.setdefault('hooks', {})
    events = ['sessionStart', 'beforeSubmitPrompt', 'preToolUse', 'stop', 'sessionEnd'] if agent == 'cursor' else ['SessionStart', 'UserPromptSubmit', 'PostToolUse', 'Stop']
    for ev in events:
        entries = hooks.setdefault(ev, [])
        entries = [e for e in entries if 'agentpet-hook.sh' not in str(e.get('command',''))]
        entries.append({'command': hook_cmd, 'type': 'command'})
        hooks[ev] = entries

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null && return 0 || return 1
}

# Claude Code
if [ -d "$HOME/.claude" ] || command -v claude &>/dev/null; then
  if update_json_hooks "$HOME/.claude/settings.json" "claude"; then
    echo "  ✔ Hooked into Claude Code (~/.claude/settings.json)"
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
  fi
fi

# Antigravity / Gemini CLI
if [ -d "$HOME/.gemini" ] || command -v agy &>/dev/null; then
  mkdir -p "$HOME/.gemini/config"
  if update_json_hooks "$HOME/.gemini/config/hooks.json" "antigravity"; then
    echo "  ✔ Hooked into Antigravity (~/.gemini/config/hooks.json)"
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
  fi
fi

# Cursor
if [ -d "$HOME/.cursor" ]; then
  if update_json_hooks "$HOME/.cursor/hooks.json" "cursor"; then
    echo "  ✔ Hooked into Cursor (~/.cursor/hooks.json)"
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
  fi
fi

# Windsurf
if [ -d "$HOME/.codeium/windsurf" ]; then
  mkdir -p "$HOME/.codeium/windsurf"
  if update_json_hooks "$HOME/.codeium/windsurf/hooks.json" "windsurf"; then
    echo "  ✔ Hooked into Windsurf (~/.codeium/windsurf/hooks.json)"
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
  fi
fi

# GitHub Copilot
if [ -d "$HOME/.copilot" ]; then
  mkdir -p "$HOME/.copilot/hooks"
  if update_json_hooks "$HOME/.copilot/hooks/agentpet.json" "copilot"; then
    echo "  ✔ Hooked into GitHub Copilot CLI (~/.copilot/hooks/agentpet.json)"
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
  fi
fi

# OpenCode Plugin
if [ -d "$HOME/.config/opencode" ] || command -v opencode &>/dev/null; then
  mkdir -p "$HOME/.config/opencode/plugin" "$HOME/.config/opencode/plugins"
  for PDIR in "$HOME/.config/opencode/plugin" "$HOME/.config/opencode/plugins"; do
    cat << EOF > "$PDIR/agentpet.js"
// AgentPet integration for OpenCode (auto-generated)
import { spawn } from "node:child_process";

export default async function ({ directory }) {
  const sid = "opencode:" + (directory || "default");
  const send = (state, message) => {
    try {
      const args = ["--agent", "opencode", "--event", state, "--session", sid, "--project", directory || ""];
      if (message) args.push("--message", message);
      const p = spawn("$HOOK_SCRIPT", args, { stdio: "ignore", detached: true });
      if (p && p.unref) p.unref();
    } catch (e) {}

    try {
      fetch("$ENDPOINT/api/events?agent=opencode&host=$HOST_LABEL", {
        method: "POST",
        headers: {
          "Authorization": "Bearer $TOKEN",
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          agent: "opencode",
          event: state,
          sessionId: sid,
          project: directory || "",
          host: "$HOST_LABEL",
          message: message || undefined
        })
      }).catch(() => {});
    } catch (e) {}
  };

  return {
    event: async ({ event }) => {
      if (!event || !event.type) return;
      if (event.type === "session.created" || event.type === "turn.start") {
        send("working");
      } else if (event.type === "session.idle" || event.type === "turn.end") {
        send("done");
      } else if (event.type === "session.status") {
        const st = event.properties && event.properties.status && event.properties.status.type;
        if (st === "idle") {
          send("done");
        } else if (st === "busy" || st === "running") {
          send("working");
        }
      }
    },
    "chat.message": async (input, output) => {
      send("working", "Processing prompt");
    }
  };
}
EOF
  done
  echo "  ✔ Hooked into OpenCode (~/.config/opencode/plugin/agentpet.js)"
  INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
fi

# Oh My Pi (omp.sh)
if [ -d "$HOME/.omp" ] || command -v omp &>/dev/null; then
  mkdir -p "$HOME/.omp/agent/extensions" "$HOME/.omp/extensions"
  for EDIR in "$HOME/.omp/agent/extensions" "$HOME/.omp/extensions"; do
    cat << EOF > "$EDIR/agentpet.ts"
// AgentPet integration for Oh My Pi (auto-generated)
import { spawn } from "node:child_process";

export default function (pi: any) {
  const send = (state: string, ctx: any, extra: any = {}) => {
    try {
      const cwd = (ctx && typeof ctx.cwd === "string" && ctx.cwd) || process.cwd();
      const sessionFile = ctx && ctx.sessionManager && typeof ctx.sessionManager.getSessionFile === "function"
        ? ctx.sessionManager.getSessionFile() : null;
      const file = typeof sessionFile === "string" && sessionFile.trim() ? sessionFile.trim() : null;
      const sid = "omp:" + (file || cwd);
      
      const args = ["--agent", "omp", "--event", state, "--session", sid];
      if (extra && extra.message) {
        args.push("--message", String(extra.message));
      }
      const p = spawn("$HOOK_SCRIPT", args, { stdio: "ignore", detached: true });
      if (p && p.unref) p.unref();

      fetch("$ENDPOINT/api/events?agent=omp&host=$HOST_LABEL", {
        method: "POST",
        headers: {
          "Authorization": "Bearer $TOKEN",
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          agent: "omp",
          event: state,
          sessionId: sid,
          project: cwd,
          host: "$HOST_LABEL",
          message: extra && extra.message ? String(extra.message) : undefined
        })
      }).catch(() => {});
    } catch (e) {}
  };

  pi.on("session_start", async (_e: any, ctx: any) => send("session_start", ctx));
  pi.on("agent_start", async (_e: any, ctx: any) => send("agent_start", ctx));
  pi.on("tool_approval_requested", async (e: any, ctx: any) => {
    const tool = e && typeof e.toolName === "string" ? e.toolName
      : (typeof e?.tool === "string" ? e.tool : (e?.tool?.name || "tool"));
    send("waiting", ctx, { message: "Needs approval for " + tool });
  });
  pi.on("tool_approval_resolved", async (_e: any, ctx: any) => send("working", ctx));
  pi.on("agent_end", async (_e: any, ctx: any) => send("agent_end", ctx));
  pi.on("session_shutdown", async (_e: any, ctx: any) => send("session_shutdown", ctx));
}
EOF
  done
  echo "  ✔ Hooked into Oh My Pi (~/.omp/agent/extensions/agentpet.ts)"
  INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
fi

echo ""
echo "🎉 AgentPet Remote Setup Complete!"
echo "   - Registered hooks for $INSTALLED_COUNT detected coding agents"
echo "   - Generic Webhook: $SEND_CLI <event> <message>"
echo "   - Forwarding to: $ENDPOINT/api/events"
"""#
    }
}
