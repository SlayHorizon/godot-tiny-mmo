// Tiny MMO admin dashboard — vanilla JS, no build step.
//
// Single-page app: token-protected, polls /api/status + /api/worlds on a
// 5s interval, exposes per-world Save / Shutdown / Broadcast actions.
//
// The token is sent in every request body (and ?token=... on GETs) because
// the embedded HTTP server doesn't parse headers. localStorage persists it
// across reloads — clear it via the Sign out button.

const API_BASE = window.location.origin;
const POLL_MS = 5000;
const HEARTBEAT_FRESH_S = 30; // older than this = "stale" warning color
const TOKEN_KEY = "tinymmo.dashboard.token";

const $ = (id) => document.getElementById(id);

const el = {
  loginView:        $("loginView"),
  appView:          $("appView"),
  tokenInput:       $("tokenInput"),
  loginBtn:         $("loginBtn"),
  loginErr:         $("loginErr"),

  connDot:          $("connDot"),
  connText:         $("connText"),
  masterUptime:     $("masterUptime"),
  refreshBtn:       $("refreshBtn"),
  logoutBtn:        $("logoutBtn"),

  worldsBody:       $("worldsBody"),
  worldsMeta:       $("worldsMeta"),

  broadcastModal:   $("broadcastModal"),
  broadcastTarget:  $("broadcastTarget"),
  broadcastText:    $("broadcastText"),
  broadcastSend:    $("broadcastSend"),
  broadcastCancel:  $("broadcastCancel"),
  broadcastErr:     $("broadcastErr"),
};

let token = "";
let pollTimer = null;
let broadcastTargetId = 0;

// ---------- HTTP helper ----------

async function api(path, body) {
  const method = body ? "POST" : "GET";
  const payload = { ...(body || {}), token };
  const url = method === "GET"
    ? `${API_BASE}${path}?token=${encodeURIComponent(token)}`
    : `${API_BASE}${path}`;
  try {
    const res = await fetch(url, {
      method,
      headers: { "Content-Type": "application/json" },
      body: method === "POST" ? JSON.stringify(payload) : undefined,
    });
    const text = await res.text();
    try { return JSON.parse(text); }
    catch { return { ok: false, error: "invalid_json", raw: text }; }
  } catch (e) {
    return { ok: false, error: "network_error", message: String(e) };
  }
}

// ---------- Auth flow ----------

function showLogin(message) {
  el.appView.classList.add("hidden");
  el.loginView.classList.remove("hidden");
  el.loginErr.textContent = message || "";
  el.tokenInput.focus();
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
}

function showApp() {
  el.loginView.classList.add("hidden");
  el.appView.classList.remove("hidden");
}

async function tryLogin(t) {
  token = t;
  // Probe /api/status to verify the token before we commit to it.
  const r = await api("/api/status");
  if (r.ok) {
    localStorage.setItem(TOKEN_KEY, t);
    showApp();
    await refreshAll();
    pollTimer = setInterval(refreshAll, POLL_MS);
    return true;
  }
  if (r.error === "unauthorized") showLogin("Invalid token.");
  else showLogin(`Couldn't reach server: ${r.error || "unknown"}`);
  token = "";
  return false;
}

function logout() {
  localStorage.removeItem(TOKEN_KEY);
  token = "";
  showLogin();
}

// ---------- Rendering ----------

function setConn(ok, text) {
  el.connDot.classList.remove("ok", "bad");
  el.connDot.classList.add(ok ? "ok" : "bad");
  el.connText.textContent = text;
}

function fmtDuration(s) {
  s = Math.max(0, Math.floor(s || 0));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${sec}s`;
  return `${sec}s`;
}

function fmtAgo(unix) {
  if (!unix) return "—";
  const ago = Math.floor(Date.now() / 1000) - unix;
  return `${fmtDuration(ago)} ago`;
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, c => ({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;" }[c]));
}

function renderWorlds(rows) {
  if (!rows || rows.length === 0) {
    el.worldsBody.innerHTML = `<tr><td colspan="7" class="muted center">No worlds connected.</td></tr>`;
    el.worldsMeta.textContent = "0 worlds";
    return;
  }
  el.worldsMeta.textContent = `${rows.length} world${rows.length === 1 ? "" : "s"}`;
  const now = Math.floor(Date.now() / 1000);
  el.worldsBody.innerHTML = rows.map(w => {
    const hbAgo = w.last_heartbeat ? (now - w.last_heartbeat) : Infinity;
    const stale = hbAgo > HEARTBEAT_FRESH_S;
    return `
      <tr>
        <td><strong>${esc(w.name)}</strong></td>
        <td class="small muted">${esc(w.address)}:${esc(w.port)}</td>
        <td>${esc(w.population)}</td>
        <td>${esc(w.instances)}</td>
        <td>${fmtDuration(w.uptime_s)}</td>
        <td class="${stale ? "heartbeat-stale" : ""}">${fmtAgo(w.last_heartbeat)}</td>
        <td class="actions">
          <button class="btn" data-act="save" data-id="${w.world_id}">Save</button>
          <button class="btn" data-act="broadcast" data-id="${w.world_id}" data-name="${esc(w.name)}">Broadcast</button>
          <button class="btn danger" data-act="shutdown" data-id="${w.world_id}">Shutdown</button>
        </td>
      </tr>
    `;
  }).join("");
}

// ---------- Refresh loop ----------

async function refreshAll() {
  const status = await api("/api/status");
  if (!status.ok) {
    setConn(false, status.error === "unauthorized" ? "Unauthorized" : "Disconnected");
    if (status.error === "unauthorized") {
      logout();
    }
    return;
  }
  setConn(true, "Connected");
  el.masterUptime.textContent = fmtDuration(status.uptime_s);

  const w = await api("/api/worlds");
  if (w.ok) renderWorlds(w.worlds);
}

// ---------- Per-world actions ----------

async function doSave(worldId) {
  const r = await api("/api/worlds/save", { world_id: worldId });
  alert(r.ok ? "Save requested." : `Save failed: ${r.error || "unknown"}`);
  await refreshAll();
}

async function doShutdown(worldId) {
  if (!confirm("Shut this world down? Connected players will be disconnected.")) return;
  const r = await api("/api/worlds/shutdown", { world_id: worldId });
  alert(r.ok ? "Shutdown requested." : `Shutdown failed: ${r.error || "unknown"}`);
  await refreshAll();
}

function openBroadcast(worldId, worldName) {
  broadcastTargetId = worldId;
  el.broadcastTarget.textContent = worldName;
  el.broadcastText.value = "";
  el.broadcastErr.textContent = "";
  el.broadcastModal.classList.remove("hidden");
  el.broadcastText.focus();
}

function closeBroadcast() {
  el.broadcastModal.classList.add("hidden");
  broadcastTargetId = 0;
}

async function sendBroadcast() {
  const msg = el.broadcastText.value.trim();
  if (!msg) { el.broadcastErr.textContent = "Message can't be empty."; return; }
  if (msg.length > 280) { el.broadcastErr.textContent = "Max 280 characters."; return; }
  const r = await api("/api/worlds/broadcast", { world_id: broadcastTargetId, message: msg });
  if (!r.ok) {
    el.broadcastErr.textContent = `Send failed: ${r.error || "unknown"}`;
    return;
  }
  closeBroadcast();
}

// ---------- Event wiring ----------

el.loginBtn.onclick = () => tryLogin(el.tokenInput.value.trim());
el.tokenInput.addEventListener("keydown", (e) => { if (e.key === "Enter") el.loginBtn.click(); });

el.refreshBtn.onclick = refreshAll;
el.logoutBtn.onclick = logout;

el.worldsBody.addEventListener("click", (e) => {
  const btn = e.target.closest("button[data-act]");
  if (!btn) return;
  const act = btn.dataset.act;
  const id = parseInt(btn.dataset.id, 10);
  if (act === "save") doSave(id);
  else if (act === "shutdown") doShutdown(id);
  else if (act === "broadcast") openBroadcast(id, btn.dataset.name);
});

el.broadcastSend.onclick = sendBroadcast;
el.broadcastCancel.onclick = closeBroadcast;
el.broadcastText.addEventListener("keydown", (e) => {
  if ((e.ctrlKey || e.metaKey) && e.key === "Enter") sendBroadcast();
  if (e.key === "Escape") closeBroadcast();
});

// ---------- Boot ----------

(async () => {
  const stored = localStorage.getItem(TOKEN_KEY) || "";
  if (stored) {
    if (!(await tryLogin(stored))) {
      // tryLogin already shows the login view with an error.
    }
  } else {
    showLogin();
  }
})();
