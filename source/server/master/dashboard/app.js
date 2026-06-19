// Tiny MMO admin dashboard.
//
// Two-view navigation:
//   home   : worlds list (the "realm picker").
//   world  : drill-down into one world — sub-tabs for Players / Chat / Logs
//            scoped to that world, plus header actions (Save / Broadcast /
//            Shutdown).
//
// Master-process logs live in a modal accessible from the top bar so master
// health stays one click away from any view.
//
// Polls every 5s. Token persisted in localStorage and sent as `?token=` on
// GETs / in the JSON body on POSTs.

const API_BASE = window.location.origin;
const POLL_MS = 5000;
const HEARTBEAT_FRESH_S = 30;
const TOKEN_KEY = "tinymmo.dashboard.token";

const $ = (id) => document.getElementById(id);

let token = "";
let pollTimer = null;

// View state
let view = "home";              // "home" | "world"
let activeWorldId = 0;
let activeWorldName = "";
let activeTab = "players";      // active sub-tab inside the world view
let activeWorldSnapshot = null; // last full world record (for header stats)

// Modal context
let broadcastTargetId = 0;
let actionContext = null;       // { kind, world_id, player_id, player_name }

// ---------- HTTP ----------

async function api(path, body) {
  const method = body ? "POST" : "GET";
  const payload = { ...(body || {}), token };
  const url = method === "GET"
    ? `${API_BASE}${path}${path.includes("?") ? "&" : "?"}token=${encodeURIComponent(token)}`
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
  $("appView").classList.add("hidden");
  $("loginView").classList.remove("hidden");
  $("loginErr").textContent = message || "";
  $("tokenInput").focus();
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
}

function showApp() {
  $("loginView").classList.add("hidden");
  $("appView").classList.remove("hidden");
}

async function tryLogin(t) {
  token = t;
  const r = await api("/v1/status");
  if (r.ok) {
    localStorage.setItem(TOKEN_KEY, t);
    showApp();
    enterHome();
    pollTimer = setInterval(refreshCurrent, POLL_MS);
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

// ---------- Format ----------

const esc = (s) => String(s).replace(/[&<>"']/g, c =>
  ({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;" }[c]));

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
  return `${fmtDuration(Math.floor(Date.now() / 1000) - unix)} ago`;
}

function fmtTime(ms) {
  if (!ms) return "—";
  return new Date(ms).toLocaleTimeString();
}

function setConn(ok, text) {
  $("connDot").classList.remove("ok", "bad");
  $("connDot").classList.add(ok ? "ok" : "bad");
  $("connText").textContent = text;
}

// ---------- View transitions ----------

function enterHome() {
  view = "home";
  activeWorldId = 0;
  activeWorldName = "";
  activeWorldSnapshot = null;
  $("homeView").classList.remove("hidden");
  $("worldView").classList.add("hidden");
  refreshCurrent();
}

function enterWorld(worldId, worldName) {
  view = "world";
  activeWorldId = worldId;
  activeWorldName = worldName;
  activeTab = "players";
  $("homeView").classList.add("hidden");
  $("worldView").classList.remove("hidden");
  $("worldName").textContent = worldName;
  // Paint the active sub-tab right away.
  document.querySelectorAll(".tab").forEach(b => b.classList.toggle("active", b.dataset.tab === activeTab));
  document.querySelectorAll(".tab-pane").forEach(p => p.classList.toggle("active", p.id === `tab-${activeTab}`));
  refreshCurrent();
}

function switchSubTab(name) {
  activeTab = name;
  document.querySelectorAll(".tab").forEach(b => b.classList.toggle("active", b.dataset.tab === name));
  document.querySelectorAll(".tab-pane").forEach(p => p.classList.toggle("active", p.id === `tab-${name}`));
  refreshCurrent();
}

// ---------- Refresh dispatch ----------

async function refreshCurrent() {
  if (!(await refreshStatus())) return;
  if (view === "home") {
    await refreshWorldsList();
    await refreshAccounts();
  } else if (view === "world") {
    // Worlds list gives us the header stats; sub-tab fetches scoped data.
    await refreshWorldHeader();
    if (activeTab === "players") await refreshPlayers();
    else if (activeTab === "chat") await refreshChat();
    else if (activeTab === "logs") await refreshLogs();
  }
}

async function refreshStatus() {
  const r = await api("/v1/status");
  if (!r.ok) {
    setConn(false, r.error === "unauthorized" ? "Unauthorized" : "Disconnected");
    if (r.error === "unauthorized") logout();
    return false;
  }
  setConn(true, "Connected");
  $("masterUptime").textContent = fmtDuration(r.uptime_s);
  return true;
}

// ---------- HOME — worlds list ----------

async function refreshWorldsList() {
  const w = await api("/v1/worlds");
  if (!w.ok) return;
  const rows = w.worlds || [];
  $("worldsMeta").textContent = `${rows.length} world${rows.length === 1 ? "" : "s"} — tap a row to inspect`;
  const body = $("worldsBody");
  if (rows.length === 0) {
    body.innerHTML = `<tr><td colspan="7" class="muted center">No worlds connected.</td></tr>`;
    return;
  }
  const now = Math.floor(Date.now() / 1000);
  body.innerHTML = rows.map(w => {
    const hbAgo = w.last_heartbeat ? (now - w.last_heartbeat) : Infinity;
    const stale = hbAgo > HEARTBEAT_FRESH_S;
    return `
      <tr class="world-row" data-world-id="${w.world_id}" data-world-name="${esc(w.name)}">
        <td><strong>${esc(w.name)}</strong></td>
        <td class="small muted">${esc(w.address)}:${esc(w.port)}</td>
        <td>${esc(w.population)}</td>
        <td>${esc(w.instances)}</td>
        <td>${fmtDuration(w.uptime_s)}</td>
        <td class="${stale ? "heartbeat-stale" : ""}">${fmtAgo(w.last_heartbeat)}</td>
        <td class="open-hint">→</td>
      </tr>
    `;
  }).join("");
}

// ---------- HOME — accounts ----------

let lastAccounts = [];
let resetPwUsername = "";

async function refreshAccounts() {
  const r = await api("/v1/accounts");
  if (!r.ok) return;
  lastAccounts = r.accounts || [];
  renderAccounts();
}

function renderAccounts() {
  const filter = ($("accountFilter").value || "").toLowerCase();
  const rows = filter
    ? lastAccounts.filter(a =>
        String(a.username || "").toLowerCase().includes(filter) ||
        String(a.id).includes(filter))
    : lastAccounts;
  $("accountsMeta").textContent = `${rows.length} account${rows.length === 1 ? "" : "s"}${filter ? ` (of ${lastAccounts.length})` : ""}`;
  const body = $("accountsBody");
  if (rows.length === 0) {
    body.innerHTML = `<tr><td colspan="4" class="muted center">${filter ? "No matches." : "No accounts."}</td></tr>`;
    return;
  }
  body.innerHTML = rows.map(a => `
    <tr>
      <td class="small muted">${esc(a.id)}</td>
      <td><strong>${esc(a.username)}</strong></td>
      <td class="small">${esc(a.last_world_name || "—")}</td>
      <td class="actions">
        <button class="btn small" data-acct-reset="${esc(a.username)}">Reset password</button>
      </td>
    </tr>
  `).join("");
}

function openResetPw(username) {
  resetPwUsername = username;
  $("resetPwTitle").textContent = `Reset password — ${username}`;
  $("resetPwInput").value = "";
  $("resetPwErr").textContent = "";
  // Default to visible — you're setting a value, not typing your own secret,
  // so confirming exactly what you pasted matters more than masking.
  $("resetPwInput").type = "text";
  $("resetPwToggle").textContent = "Hide";
  $("resetPwModal").classList.remove("hidden");
  $("resetPwInput").focus();
}

function closeResetPw() { $("resetPwModal").classList.add("hidden"); resetPwUsername = ""; }

async function confirmResetPw() {
  const pw = $("resetPwInput").value;
  if (!pw) { $("resetPwErr").textContent = "Password can't be empty."; return; }
  const r = await api("/v1/accounts/reset_password", { username: resetPwUsername, new_password: pw });
  if (!r.ok) { $("resetPwErr").textContent = `Failed: ${r.error || "unknown"}`; return; }
  closeResetPw();
  alert(`Password reset for "${r.username}".`);
}

// ---------- WORLD header ----------

async function refreshWorldHeader() {
  const w = await api("/v1/worlds");
  if (!w.ok) return;
  const wd = (w.worlds || []).find(x => x.world_id === activeWorldId);
  if (!wd) {
    // World dropped off the master — bounce back to home so we don't act
    // against something that no longer exists.
    enterHome();
    return;
  }
  activeWorldSnapshot = wd;
  activeWorldName = wd.name;
  $("worldName").textContent = wd.name;
  $("worldSubtitle").textContent = `${wd.address}:${wd.port}`;
  $("kpiPlayers").textContent = wd.population;
  $("kpiInstances").textContent = wd.instances;
  $("kpiUptime").textContent = fmtDuration(wd.uptime_s);
  const stale = wd.last_heartbeat ? (Math.floor(Date.now() / 1000) - wd.last_heartbeat > HEARTBEAT_FRESH_S) : true;
  $("kpiHeartbeat").textContent = fmtAgo(wd.last_heartbeat);
  $("kpiHeartbeat").className = `v ${stale ? "heartbeat-stale" : ""}`;
}

// ---------- WORLD sub-tab: Players ----------

let lastPlayers = [];

async function refreshPlayers() {
  const r = await api(`/v1/players?world_id=${activeWorldId}`);
  if (!r.ok) return;
  lastPlayers = r.players || [];
  renderPlayers();
}

function renderPlayers() {
  const filter = ($("playerFilter").value || "").toLowerCase();
  const rows = filter
    ? lastPlayers.filter(p =>
        String(p.name || "").toLowerCase().includes(filter) ||
        String(p.account || "").toLowerCase().includes(filter))
    : lastPlayers;
  $("playersMeta").textContent = `${rows.length} online${filter ? ` (of ${lastPlayers.length})` : ""}`;
  const body = $("playersBody");
  if (rows.length === 0) {
    body.innerHTML = `<tr><td colspan="6" class="muted center">${filter ? "No matches." : "Nobody online."}</td></tr>`;
    return;
  }
  body.innerHTML = rows.map(p => {
    const roles = (p.roles || []).map(r =>
      `<span class="role-pill ${esc(r)}">${esc(r)}</span>`).join("");
    // Mute / Jail buttons flip text + style based on current state. Spares
    // operators the "did the unmute already fire?" guessing game.
    const muteBtn = p.is_muted
      ? `<button class="btn small primary" data-pact="unmute" data-pid="${p.player_id}" data-pname="${esc(p.name)}">Unmute</button>`
      : `<button class="btn small" data-pact="mute" data-pid="${p.player_id}" data-pname="${esc(p.name)}">Mute</button>`;
    const jailBtn = p.is_jailed
      ? `<button class="btn small primary" data-pact="unjail" data-pid="${p.player_id}" data-pname="${esc(p.name)}">Unjail</button>`
      : `<button class="btn small" data-pact="jail" data-pid="${p.player_id}" data-pname="${esc(p.name)}">Jail</button>`;
    // Tiny status badges next to the name so the row reads at a glance.
    const badges = [
      p.is_muted ? `<span class="badge mute" title="Muted">🔇</span>` : "",
      p.is_jailed ? `<span class="badge jail" title="Jailed">🔒</span>` : "",
    ].join("");
    return `
      <tr>
        <td><strong>${esc(p.name)}</strong> ${badges}</td>
        <td class="small muted">${esc(p.account)}</td>
        <td class="small">${esc(p.instance || "—")}</td>
        <td>${esc(p.level)}</td>
        <td>${roles || `<span class="muted small">—</span>`}</td>
        <td class="actions">
          <button class="btn small" data-pact="chat" data-pid="${p.player_id}" data-pname="${esc(p.name)}">Chat</button>
          ${muteBtn}
          ${jailBtn}
          <button class="btn small" data-pact="grant" data-pid="${p.player_id}" data-pname="${esc(p.name)}">Role</button>
          <button class="btn small danger" data-pact="kick" data-pid="${p.player_id}" data-pname="${esc(p.name)}">Kick</button>
        </td>
      </tr>
    `;
  }).join("");
}

// ---------- WORLD sub-tab: Chat ----------

let lastChatMessages = [];

async function refreshChat() {
  const r = await api(`/v1/chat?world_id=${activeWorldId}`);
  if (!r.ok) return;
  lastChatMessages = r.messages || [];
  renderChat();
}

function renderChat() {
  const channelFilter = $("chatChannelFilter").value;
  const textFilter = ($("chatTextFilter").value || "").toLowerCase();
  const msgs = lastChatMessages.filter(m => {
    if (channelFilter && m.channel_name !== channelFilter) return false;
    if (textFilter) {
      const hay = [m.name, m.account, m.instance, m.text].map(s => String(s || "").toLowerCase()).join(" ");
      if (!hay.includes(textFilter)) return false;
    }
    return true;
  });
  $("chatMeta").textContent = `${msgs.length} of ${lastChatMessages.length} recent`;
  const feed = $("chatFeed");
  if (msgs.length === 0) {
    feed.innerHTML = `<div class="empty">${lastChatMessages.length === 0 ? "No recent channel chat." : "No messages match the current filters."}</div>`;
    return;
  }
  const nearBottom = feed.scrollHeight - feed.scrollTop - feed.clientHeight < 40;
  // Each row: meta line (channel | instance | sender display + account + #id | time), then the text.
  // Showing account_name is what lets a moderator disambiguate two "John"s.
  feed.innerHTML = msgs.map(m => {
    const ch = m.channel_name || `Ch.${m.channel}`;
    const inst = m.instance || "—";
    return `
      <div class="msg">
        <div class="meta">
          <span class="world">${esc(ch)}</span> ·
          <span>${esc(inst)}</span> ·
          <span class="sender">${esc(m.name)}</span>
          <span class="muted small">@${esc(m.account || "?")} #${esc(m.id)}</span> ·
          ${fmtTime(m.time_ms)}
        </div>
        <div>${esc(m.text)}</div>
      </div>
    `;
  }).join("");
  if (nearBottom) feed.scrollTop = feed.scrollHeight;
}

// ---------- WORLD sub-tab: Logs ----------

async function refreshLogs() {
  const r = await api(`/v1/logs?world_id=${activeWorldId}&limit=200`);
  if (!r.ok) return;
  const lines = r.lines || [];
  $("logsMeta").textContent = `${lines.length} lines`;
  const feed = $("logsFeed");
  const nearBottom = feed.scrollHeight - feed.scrollTop - feed.clientHeight < 40;
  feed.textContent = lines.join("\n") || "(empty)";
  if (nearBottom) feed.scrollTop = feed.scrollHeight;
}

// ---------- Master logs modal ----------

async function openMasterLogs() {
  $("masterLogsModal").classList.remove("hidden");
  const r = await api("/v1/logs?limit=300");
  $("masterLogsFeed").textContent = r.ok ? ((r.lines || []).join("\n") || "(empty)") : `Failed: ${r.error || "unknown"}`;
}

function closeMasterLogs() { $("masterLogsModal").classList.add("hidden"); }

// ---------- World header actions ----------

async function doSave() {
  if (!activeWorldId) return;
  const r = await api("/v1/worlds/save", { world_id: activeWorldId });
  alert(r.ok ? "Save requested." : `Save failed: ${r.error || "unknown"}`);
}

async function doShutdown() {
  if (!activeWorldId) return;
  if (!confirm(`Shut down "${activeWorldName}"? Connected players will be disconnected.`)) return;
  const r = await api("/v1/worlds/shutdown", { world_id: activeWorldId });
  alert(r.ok ? "Shutdown requested." : `Shutdown failed: ${r.error || "unknown"}`);
  enterHome(); // The world is about to drop off the master.
}

function openBroadcast() {
  if (!activeWorldId) return;
  broadcastTargetId = activeWorldId;
  $("broadcastTarget").textContent = activeWorldName;
  $("broadcastText").value = "";
  $("broadcastErr").textContent = "";
  $("broadcastModal").classList.remove("hidden");
  $("broadcastText").focus();
}

function closeBroadcast() { $("broadcastModal").classList.add("hidden"); broadcastTargetId = 0; }

async function sendBroadcast() {
  const msg = $("broadcastText").value.trim();
  if (!msg) { $("broadcastErr").textContent = "Message can't be empty."; return; }
  if (msg.length > 280) { $("broadcastErr").textContent = "Max 280 characters."; return; }
  const r = await api("/v1/worlds/broadcast", { world_id: broadcastTargetId, message: msg });
  if (!r.ok) { $("broadcastErr").textContent = `Send failed: ${r.error || "unknown"}`; return; }
  closeBroadcast();
}

// ---------- Player actions ----------

function openPlayerAction(kind, playerId, playerName) {
  // Direct unmute/unjail skip the modal entirely — they're one-click reverts
  // with no parameters. We confirm via a quick optimistic refresh.
  if (kind === "unmute" || kind === "unjail") {
    quickAction(kind, playerId);
    return;
  }
  if (kind === "chat") {
    openPlayerChatHistory(playerId, playerName);
    return;
  }
  actionContext = { kind, world_id: activeWorldId, player_id: playerId, player_name: playerName };
  const titles = { mute: "Mute", jail: "Jail", grant: "Grant role", kick: "Kick" };
  $("actionTitle").textContent = `${titles[kind]} ${playerName}`;
  $("actionErr").textContent = "";

  const fields = $("actionFields");
  if (kind === "mute" || kind === "jail") {
    fields.innerHTML = `
      <label class="field-label">Reason (optional)</label>
      <input id="actReason" placeholder="e.g. spamming chat" />
      <label class="field-label">Duration</label>
      <input id="actDuration" placeholder="blank = permanent · e.g. 30m, 1h30m, 2d" />
      <div id="actDurationPreview" class="muted small" style="margin-bottom: 8px;">Permanent.</div>
      <div class="row" style="margin-bottom: 8px; flex-wrap: wrap;">
        <button type="button" class="btn small dur-pick" data-dur="10m">10m</button>
        <button type="button" class="btn small dur-pick" data-dur="1h">1h</button>
        <button type="button" class="btn small dur-pick" data-dur="6h">6h</button>
        <button type="button" class="btn small dur-pick" data-dur="1d">1d</button>
        <button type="button" class="btn small dur-pick" data-dur="7d">7d</button>
        <button type="button" class="btn small ghost" data-dur="">Permanent</button>
      </div>
    `;
    // Wire the preview to update as you type, and the quick-picks to fill it.
    const input = $("actDuration");
    const preview = $("actDurationPreview");
    const update = () => {
      const ms = parseDuration(input.value);
      preview.textContent = ms > 0 ? `= ${humanizeDuration(ms)}` : "Permanent.";
    };
    input.addEventListener("input", update);
    fields.querySelectorAll(".dur-pick").forEach(b => {
      b.onclick = () => { input.value = b.dataset.dur; update(); };
    });
  } else if (kind === "grant") {
    // Look up the player's current roles from the most-recent fetch so the
    // moderator can revoke any (effectively "demote to default") AND grant
    // new ones from one place.
    const p = (lastPlayers || []).find(x => x.player_id === actionContext.player_id);
    const current = (p && p.roles) ? p.roles : [];
    const currentHTML = current.length
      ? current.map(r => `<span class="role-pill ${esc(r)}">${esc(r)} <button class="role-x" data-revoke="${esc(r)}" title="Revoke">×</button></span>`).join(" ")
      : `<span class="muted small">No roles (default player).</span>`;
    fields.innerHTML = `
      <label class="field-label">Current roles</label>
      <div id="actCurrentRoles" style="margin-bottom: 12px;">${currentHTML}</div>
      <label class="field-label">Grant new role</label>
      <select id="actRole">
        <option value="">— pick a role —</option>
        <option value="moderator">moderator</option>
        <option value="admin">admin</option>
        <option value="senior_admin">senior_admin</option>
      </select>
    `;
  } else if (kind === "kick") {
    fields.innerHTML = `<p class="muted">This will immediately disconnect the player. They can reconnect after.</p>`;
  }
  $("actionModal").classList.remove("hidden");
}

function closeAction() { $("actionModal").classList.add("hidden"); actionContext = null; }

async function confirmAction() {
  if (!actionContext) return;
  const { kind, world_id, player_id } = actionContext;
  let path, body;
  if (kind === "mute") {
    path = "/v1/players/mute";
    body = { world_id, player_id, reason: $("actReason").value, duration_ms: parseDuration($("actDuration").value) };
  } else if (kind === "jail") {
    path = "/v1/players/jail";
    body = { world_id, player_id, reason: $("actReason").value, duration_ms: parseDuration($("actDuration").value) };
  } else if (kind === "grant") {
    // Empty role = the user only wanted to revoke (handled inline via ×).
    // Confirm just closes the modal in that case.
    const role = $("actRole").value;
    if (!role) { closeAction(); await refreshCurrent(); return; }
    path = "/v1/players/grant";
    body = { world_id, player_id, role };
  } else if (kind === "kick") {
    path = "/v1/players/kick";
    body = { world_id, player_id };
  } else return;
  const r = await api(path, body);
  if (!r.ok) { $("actionErr").textContent = `Failed: ${r.error || "unknown"}`; return; }
  closeAction();
  await refreshCurrent();
}


// One-click revert for unmute/unjail. Skips the modal entirely.
async function quickAction(kind, playerId) {
  const path = `/v1/players/${kind}`;
  const r = await api(path, { world_id: activeWorldId, player_id: playerId });
  if (!r.ok) {
    alert(`${kind} failed: ${r.error || "unknown"}`);
    return;
  }
  await refreshCurrent();
}


// --- Duration parsing ---
//
// Accepts tokens like "30m", "1h30m", "1d 6h", "2d". Returns 0 (= permanent)
// for empty or unparseable input. Mirrors the server's parse_duration_ms on
// ChatCommand but lives client-side so the input is responsive.
function parseDuration(s) {
  s = String(s || "").trim().toLowerCase();
  if (!s) return 0;
  const units = { s: 1000, m: 60_000, h: 3_600_000, d: 86_400_000 };
  let total = 0;
  let any = false;
  // Each match is "<digits><unit-letter>", with optional whitespace before/after.
  s.replace(/(\d+)\s*([smhd])/g, (_, n, u) => {
    total += parseInt(n, 10) * units[u];
    any = true;
    return "";
  });
  return any ? total : 0;
}

function humanizeDuration(ms) {
  if (ms <= 0) return "permanent";
  let s = Math.floor(ms / 1000);
  const d = Math.floor(s / 86400); s -= d * 86400;
  const h = Math.floor(s / 3600);  s -= h * 3600;
  const m = Math.floor(s / 60);    s -= m * 60;
  const parts = [];
  if (d) parts.push(`${d}d`);
  if (h) parts.push(`${h}h`);
  if (m) parts.push(`${m}m`);
  if (s && parts.length < 2) parts.push(`${s}s`);
  return parts.join(" ");
}


// --- Per-player chat history modal ---
//
// Click "Chat" on a player row → fetch the world's recent chat, filter to
// just that player's messages, render in a modal. Channel-only (DMs are
// excluded by the recent-buffer on the world side); a future "View DMs"
// flow would query the SQLite messages table via a new endpoint.
async function openPlayerChatHistory(playerId, playerName) {
  $("chatHistoryTitle").textContent = `Recent chat — ${playerName}`;
  $("chatHistoryFeed").innerHTML = `<div class="muted center" style="padding: 16px;">Loading…</div>`;
  $("chatHistoryModal").classList.remove("hidden");
  const r = await api(`/v1/chat?world_id=${activeWorldId}`);
  const feed = $("chatHistoryFeed");
  if (!r.ok) {
    feed.innerHTML = `<div class="err">Failed: ${r.error || "unknown"}</div>`;
    return;
  }
  const mine = (r.messages || []).filter(m => Number(m.id) === Number(playerId));
  if (mine.length === 0) {
    feed.innerHTML = `<div class="empty">No recent channel chat from this player.</div>`;
    return;
  }
  feed.innerHTML = mine.map(m => `
    <div class="msg">
      <div class="meta">
        <span class="world">${esc(m.channel_name || `Ch.${m.channel}`)}</span> ·
        <span>${esc(m.instance || "—")}</span> ·
        ${fmtTime(m.time_ms)}
      </div>
      <div>${esc(m.text)}</div>
    </div>
  `).join("");
}

function closeChatHistory() { $("chatHistoryModal").classList.add("hidden"); }


// Revoke a single role via the × on a role pill inside the grant modal. We
// stay in the modal afterward so the moderator can revoke several in a row
// or grant a replacement.
async function revokeRole(role) {
  if (!actionContext) return;
  const { world_id, player_id } = actionContext;
  const r = await api("/v1/players/revoke", { world_id, player_id, role });
  if (!r.ok) { $("actionErr").textContent = `Revoke failed: ${r.error || "unknown"}`; return; }
  await refreshCurrent();
  // Re-open the modal with the refreshed role list so the UI reflects the change.
  openPlayerAction("grant", player_id, actionContext.player_name);
}

// ---------- Event wiring ----------

$("loginBtn").onclick = () => tryLogin($("tokenInput").value.trim());
$("tokenInput").addEventListener("keydown", (e) => { if (e.key === "Enter") $("loginBtn").click(); });

$("refreshBtn").onclick = refreshCurrent;
$("logoutBtn").onclick = logout;
$("masterLogsBtn").onclick = openMasterLogs;
$("masterLogsClose").onclick = closeMasterLogs;
$("chatHistoryClose").onclick = closeChatHistory;

$("backBtn").onclick = enterHome;
$("worldSaveBtn").onclick = doSave;
$("worldBroadcastBtn").onclick = openBroadcast;
$("worldShutdownBtn").onclick = doShutdown;

document.querySelectorAll(".tab").forEach(btn => {
  btn.onclick = () => switchSubTab(btn.dataset.tab);
});

$("worldsBody").addEventListener("click", (e) => {
  const row = e.target.closest("tr.world-row");
  if (!row) return;
  enterWorld(parseInt(row.dataset.worldId, 10), row.dataset.worldName);
});

$("playersBody").addEventListener("click", (e) => {
  const btn = e.target.closest("button[data-pact]");
  if (!btn) return;
  openPlayerAction(btn.dataset.pact, parseInt(btn.dataset.pid, 10), btn.dataset.pname);
});

$("playerFilter").addEventListener("input", renderPlayers);

$("accountFilter").addEventListener("input", renderAccounts);
$("accountsBody").addEventListener("click", (e) => {
  const btn = e.target.closest("button[data-acct-reset]");
  if (!btn) return;
  openResetPw(btn.dataset.acctReset);
});
$("resetPwConfirm").onclick = confirmResetPw;
$("resetPwCancel").onclick = closeResetPw;
$("resetPwToggle").onclick = () => {
  const inp = $("resetPwInput");
  const reveal = inp.type === "password";
  inp.type = reveal ? "text" : "password";
  $("resetPwToggle").textContent = reveal ? "Hide" : "Show";
};
$("resetPwInput").addEventListener("keydown", (e) => {
  if (e.key === "Enter") confirmResetPw();
  if (e.key === "Escape") closeResetPw();
});

$("chatChannelFilter").addEventListener("change", renderChat);
$("chatTextFilter").addEventListener("input", renderChat);

$("broadcastSend").onclick = sendBroadcast;
$("broadcastCancel").onclick = closeBroadcast;
$("broadcastText").addEventListener("keydown", (e) => {
  if ((e.ctrlKey || e.metaKey) && e.key === "Enter") sendBroadcast();
  if (e.key === "Escape") closeBroadcast();
});

$("actionConfirm").onclick = confirmAction;
$("actionCancel").onclick = closeAction;
// Delegated: the × buttons on role pills inside the grant modal.
$("actionFields").addEventListener("click", (e) => {
  const x = e.target.closest("button[data-revoke]");
  if (!x) return;
  revokeRole(x.dataset.revoke);
});

// ---------- Boot ----------

(async () => {
  const stored = localStorage.getItem(TOKEN_KEY) || "";
  if (stored) await tryLogin(stored);
  else showLogin();
})();
