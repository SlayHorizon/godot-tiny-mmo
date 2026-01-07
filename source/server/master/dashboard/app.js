const API = "http://127.0.0.1:8089";
const $ = (id) => document.getElementById(id);

const el = {
  connDot: $("connDot"),
  connText: $("connText"),
  lastRefresh: $("lastRefresh"),

  btnRefresh: $("btnRefresh"),
  btnLoad: $("btnLoad"),
  btnFind: $("btnFind"),
  btnUpdate: $("btnUpdate"),
  btnSave: $("btnSave"),

  kpiOnline: $("kpiOnline"),
  kpiAccounts: $("kpiAccounts"),
  overviewRaw: $("overviewRaw"),
  overviewStamp: $("overviewStamp"),

  accountsMeta: $("accountsMeta"),
  accountsList: $("accountsList"),
  accountsRaw: $("accountsRaw"),
  accountQuery: $("accountQuery"),
  resultsStamp: $("resultsStamp"),

  selectedHint: $("selectedHint"),
  editor: $("editor"),
  status: $("status"),
  raw: $("raw"),
};

let selected = null; // { username, id }

const stamp = () => new Date().toLocaleString();
const setText = (node, v) => (node.textContent = v);
const setJSON = (node, v) => (node.textContent = JSON.stringify(v, null, 2));

async function fetchJSON(path, { method = "GET", body } = {}) {
  const res = await fetch(API + path, {
    method,
    headers: body ? { "Content-Type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });

  const text = await res.text();
  try { return JSON.parse(text); }
  catch { return { ok: false, error: "invalid_json", raw: text }; }
}

function setConn(ok, text) {
  el.connDot.classList.remove("ok", "bad");
  el.connDot.classList.add(ok ? "ok" : "bad");
  setText(el.connText, text);
}

function setStatus(msg, payload) {
  setText(el.status, msg);
  if (payload !== undefined) setJSON(el.raw, payload);
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"
  }[c]));
}

function renderList(items) {
  el.accountsList.innerHTML = "";

  if (!Array.isArray(items) || items.length === 0) {
    el.accountsList.innerHTML = `<div class="muted">No results.</div>`;
    return;
  }

  for (const a of items) {
    const id = a.id ?? "—";
    const username = a.username ?? "—";
    const peer = a.peer_id ?? 0;

    const div = document.createElement("div");
    div.className = "list-item";
    div.innerHTML = `
      <div class="id">${esc(username)} <span class="muted">#${esc(id)}</span></div>
      <div class="sub">peer_id: ${esc(peer)}</div>
    `;
    div.onclick = () => {
      selected = { username, id };
      setText(el.selectedHint, `${username} (#${id})`);
      el.editor.value = JSON.stringify(a, null, 2);
      setStatus("Loaded into editor.");
    };
    el.accountsList.appendChild(div);
  }
}

async function ping() {
  const r = await fetchJSON("/v1/ping");
  setConn(!!r.ok, r.ok ? "Connected" : "Disconnected");
}

async function loadOverview() {
  const r = await fetchJSON("/v1/overview");
  setJSON(el.overviewRaw, r);
  setText(el.overviewStamp, `Fetched: ${stamp()}`);

  setText(el.kpiOnline, r.ok ? String(r.online_players ?? "—") : "—");
  setText(el.kpiAccounts, r.ok ? String(r.registered_accounts ?? "—") : "—");
}

async function loadAccounts() {
  const r = await fetchJSON("/v1/accounts");
  setJSON(el.accountsRaw, r);
  setText(el.resultsStamp, `Fetched: ${stamp()}`);

  if (!r.ok) {
    setText(el.accountsMeta, `Error: ${r.error ?? "unknown"}`);
    renderList([]);
    setStatus("Failed to load accounts.", r);
    return;
  }

  setText(el.accountsMeta, `Total: ${r.total ?? 0} (preview: ${r.preview?.length ?? 0})`);
  renderList(r.preview ?? []);
  setStatus("Accounts loaded.", r);
}

async function findAccounts(q) {
  const r = await fetchJSON("/v1/accounts/find", { method: "POST", body: { q } });
  setText(el.resultsStamp, `Fetched: ${stamp()}`);

  if (!r.ok) {
    renderList([]);
    setText(el.accountsMeta, `Error: ${r.error ?? "unknown"}`);
    setStatus("Search failed.", r);
    return;
  }

  const matches = r.matches ?? [];
  setText(el.accountsMeta, `Search results: ${r.total_matches ?? matches.length}`);
  renderList(matches);
  setStatus("Search done.", r);
}

async function updateAccount() {
  if (!selected) return setStatus("No account selected.");

  let parsed;
  try { parsed = JSON.parse(el.editor.value); }
  catch (e) { return setStatus(`Invalid JSON: ${e.message}`); }

  const patch = {};
  if ("peer_id" in parsed) patch.peer_id = parsed.peer_id;
  if ("username" in parsed) patch.username = parsed.username;

  const r = await fetchJSON("/v1/accounts/update", {
    method: "POST",
    body: { username: selected.username, patch }
  });

  if (!r.ok) return setStatus(`Update failed: ${r.error ?? "unknown"}`, r);

  const updated = r.updated ?? parsed;
  selected = { username: updated.username ?? selected.username, id: updated.id ?? selected.id };
  setText(el.selectedHint, `${selected.username} (#${selected.id})`);
  el.editor.value = JSON.stringify(updated, null, 2);

  setStatus("Updated.", r);
  await loadAccounts(); // keep same behavior
}

async function saveAccounts() {
  const r = await fetchJSON("/v1/save", { method: "POST", body: {} });
  setStatus(r.ok ? "Saved." : `Save failed: ${r.error ?? "unknown"}`, r);
}

async function refreshAll() {
  setText(el.lastRefresh, stamp());
  await ping();
  await loadOverview();
}

el.btnRefresh.onclick = refreshAll;

el.btnLoad.onclick = async () => {
  setText(el.lastRefresh, stamp());
  await ping();
  await loadAccounts();
};

el.btnFind.onclick = () => findAccounts(el.accountQuery.value);
el.btnUpdate.onclick = updateAccount;
el.btnSave.onclick = saveAccounts;

// heartbeat
setInterval(ping, 5000);

// init
(async () => {
  setText(el.lastRefresh, stamp());
  await refreshAll();
  setStatus("Ready.");
})();
