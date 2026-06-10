import { invoke } from "@tauri-apps/api/core";

interface AgentInfo {
  kind: string;
  display_name: string;
  installed: boolean;
  note: string | null;
}

const root = document.getElementById("agents")!;

async function refresh() {
  const agents = await invoke<AgentInfo[]>("list_agents");
  root.innerHTML = "";
  for (const a of agents) {
    const row = document.createElement("div");
    row.className = "agent-row";

    const meta = document.createElement("div");
    meta.className = "meta";
    const status = a.note
      ? `<div class="note">${escapeHtml(a.note)}</div>`
      : a.installed
      ? `<div class="ok">Hook installed</div>`
      : "";
    meta.innerHTML = `<div class="name">${escapeHtml(a.display_name)}</div>${status}`;

    const btn = document.createElement("button");
    btn.textContent = a.installed ? "Remove" : "Install";
    if (a.installed) btn.classList.add("remove");
    btn.onclick = async () => {
      btn.disabled = true;
      try { await invoke("toggle_install", { kind: a.kind }); } catch (e) { alert(String(e)); }
      await refresh();
    };

    row.appendChild(meta);
    row.appendChild(btn);
    root.appendChild(row);
  }
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c] || c));
}

refresh();
