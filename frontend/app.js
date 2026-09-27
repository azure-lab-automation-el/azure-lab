'use strict';
// Esther Cloud Admin UI. Talks only to /api (same origin). No tokens or secrets live here.
const $ = (s, r = document) => r.querySelector(s);
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const SUFFIX = '@estherh.v6.rocks'; const GP = 'Esther Hospital - ';
const S = { me: null, users: [], groups: [], byUpn: new Map(), requests: [], configured: true };
const lc = (s) => (s || '').toLowerCase();
const nameOf = (upn) => S.byUpn.get(lc(upn))?.displayName || upn || '';
const deptOf = (g) => g.displayName.replace(GP, '');
const COLORS = ['#3b82f6', '#0891b2', '#16a34a', '#d97706', '#1d4ed8', '#0284c7', '#0d9488', '#dc2626', '#2563eb', '#65a30d'];
function avatar(name, size = '') { const n = String(name || '?').trim(); const ini = n.split(/\s+/).map((w) => w[0]).slice(0, 2).join('').toUpperCase(); let h = 0; for (const c of n) h = (h * 31 + c.charCodeAt(0)) >>> 0; return `<span class="avatar ${size}" style="background:${COLORS[h % COLORS.length]}">${esc(ini)}</span>`; }
const chip = (u) => (u.accountEnabled === false ? '<span class="pill off">Disabled</span>' : '<span class="pill active">Active</span>');

// ---------- app sign-in (Esther Cloud Admin app roles) ----------
const PORTAL_APP = { clientId: '2981ce39-bbc6-4ba2-b931-9cae155cd895', authority: 'https://login.microsoftonline.com/f80b4063-5bc4-47e4-9ea6-a2a19ed79fa3' };
// Only origins registered as redirect URIs on the app; other hostnames use the allowlist.
const APP_ORIGINS = ['https://www.estherdaxes.cloud-ip.cc', 'https://agreeable-smoke-09274440f.5.azurestaticapps.net', 'https://estherdaxes.esther-hospital.dedyn.io'];
let msalApp = null; let msalAccount = null;
async function appSignIn() {
  if (!window.msal || sessionStorage.getItem('esther-app-signin') === 'off' || !APP_ORIGINS.includes(location.origin)) return;
  try {
    msalApp = new msal.PublicClientApplication({ auth: { clientId: PORTAL_APP.clientId, authority: PORTAL_APP.authority, redirectUri: location.origin + '/' }, cache: { cacheLocation: 'sessionStorage' } });
    await msalApp.initialize();
    const res = await msalApp.handleRedirectPromise();
    msalAccount = res?.account || msalApp.getAllAccounts()[0] || null;
    if (!msalAccount) {
      const me = await fetch('/.auth/me').then((r) => r.json()).catch(() => ({}));
      await msalApp.loginRedirect({ scopes: ['openid', 'profile'], loginHint: me?.clientPrincipal?.userDetails, redirectStartPage: location.href });
      await new Promise(() => {});
    }
  } catch (e) { sessionStorage.setItem('esther-app-signin', 'off'); msalApp = null; console.warn('App sign-in unavailable, using the allowlist:', e.errorCode || e.message); }
}
async function appToken() {
  if (!msalApp || !msalAccount) return '';
  try { return (await msalApp.acquireTokenSilent({ scopes: ['openid', 'profile'], account: msalAccount })).idToken || ''; } catch { return ''; }
}
async function api(path, opts = {}) {
  const tok = await appToken();
  const r = await fetch('/api/' + path, { headers: { 'content-type': 'application/json', ...(tok ? { 'x-esther-token': tok } : {}) }, ...opts });
  const b = await r.json().catch(() => ({})); if (!r.ok) throw new Error(b.error || `HTTP ${r.status}`); return b;
}
function banner(msg) { const b = $('#banner'); b.hidden = !msg; b.textContent = msg || ''; }
function show(view) {
  document.querySelectorAll('.view').forEach((s) => { s.hidden = s.id !== view; });
  document.querySelectorAll('nav button').forEach((b) => b.classList.toggle('on', b.dataset.view === view));
  if (view === 'requests') loadRequests();
  if (view === 'reports') renderReport();
  if (view === 'admin') loadAdmin();
  if (view === 'helpdesk') renderHelpdesk();
}

// ---------- users ----------
function renderUsers() {
  const q = lc($('#q').value); const d = $('#deptFilter').value; const off = $('#showDisabled').checked;
  const rows = S.users.filter((u) => (!d || u.department === d) && (!off || u.accountEnabled === false) &&
    (!q || lc([u.displayName, u.userPrincipalName, u.jobTitle].join(' ')).includes(q)));
  $('#userTable tbody').innerHTML = rows.map((u) => `<tr data-upn="${esc(u.userPrincipalName)}"><td><div class="person">${avatar(u.displayName)}<div>${esc(u.displayName)}<div class="muted">${esc(u.userPrincipalName.replace(SUFFIX, ''))}</div></div></div></td><td>${esc(u.department)}</td><td>${esc(u.jobTitle)}</td><td>${esc(nameOf(u.manager))}</td><td>${chip(u)}</td></tr>`).join('') || '<tr><td colspan="5">No users match.</td></tr>';
}
function groupsOf(upn) { return S.groups.filter((g) => g.members.some((m) => lc(m) === lc(upn))); }
function openUser(upn) {
  const u = S.byUpn.get(lc(upn)); if (!u) return;
  const reports = S.users.filter((x) => lc(x.manager) === lc(upn));
  const gs = groupsOf(upn);
  $('#detail').innerHTML = `<p><button data-back>&larr; Users</button></p>
  <div class="card"><div class="hero">${avatar(u.displayName, 'lg')}<div><h2>${esc(u.displayName)} ${chip(u)}</h2>
    <div>${esc(u.jobTitle)} &middot; ${esc(u.department)}</div><div class="muted">${esc(u.userPrincipalName)}</div></div></div>
    <p>Manager: ${u.manager ? `<a href="#" data-open="${esc(u.manager)}">${esc(nameOf(u.manager))}</a>` : '<span class="muted">none</span>'}</p>
    <div class="actions">
      <button data-act="updateUser">Edit title / department</button>
      <button data-act="setManager">Change manager</button>
      <button data-act="addToGroup">Add to group</button>
      ${u.accountEnabled === false ? '<button data-act="enableUser">Enable</button>' : '<button class="danger" data-act="disableUser">Disable</button>'}
      <button data-act="resetPassword">Reset password</button>
    </div></div>
  <div class="card"><h3>Groups</h3>${gs.map((g) => `<div>${esc(g.displayName)} <button data-act="removeFromGroup" data-group="${esc(g.displayName)}">Remove</button></div>`).join('') || '<p class="muted">No groups</p>'}</div>
  <div class="card"><h3>Direct reports (${reports.length})</h3>${reports.map((r) => `<div class="person">${avatar(r.displayName, 'sm')}<div><a href="#" data-open="${esc(r.userPrincipalName)}">${esc(r.displayName)}</a><div class="muted">${esc(r.jobTitle)}</div></div></div>`).join('') || '<p class="muted">None</p>'}</div>
  <div class="card"><h3>History</h3>${(S.requests || []).filter((r) => lc(r.userPrincipalName) === lc(u.userPrincipalName) || lc(r.manager) === lc(u.userPrincipalName)).slice(0, 10).map((r) => `<div><span class="pill ${esc(r.state)}">${esc(r.state)}</span> ${esc(LABEL[r.action] || r.action)} <span class="muted">by ${esc(r.requestedBy)} &middot; <a href="${esc(r.url)}" target="_blank" rel="noopener">#${r.number}</a></span></div>`).join('') || '<p class="muted">No portal changes yet</p>'}</div>`;
  $('#detail').dataset.upn = upn; show('detail');
}

// ---------- actions ----------
const LABEL = { updateUser: 'Edit title / department', setManager: 'Change manager', addToGroup: 'Add to group', removeFromGroup: 'Remove from group', disableUser: 'Disable user', enableUser: 'Enable user', resetPassword: 'Reset password' };
function isSpecial(action) { return (S.me?.policy?.special || []).includes(action); }
function noteFor(action) {
  if (!S.configured) return 'Preview mode: requests are checked but not filed yet.';
  if (!isSpecial(action)) return 'Standard change: applied right away, then read back.';
  return S.me?.approver ? 'Special change: you are an approver, so it applies right away.' : 'Special change: an approver has to approve it before it applies.';
}
function userOptions(sel, except) { return '<option value="">(none)</option>' + S.users.filter((x) => lc(x.userPrincipalName) !== lc(except)).sort((a, b) => a.displayName.localeCompare(b.displayName)).map((x) => `<option value="${esc(x.userPrincipalName)}" ${lc(x.userPrincipalName) === lc(sel) ? 'selected' : ''}>${esc(x.displayName)} - ${esc(x.jobTitle)}</option>`).join(''); }
function deptOptions(sel) { return S.groups.map(deptOf).sort().map((d) => `<option ${d === sel ? 'selected' : ''}>${esc(d)}</option>`).join(''); }
function openAction(action, group) {
  const upn = $('#detail').dataset.upn; const u = S.byUpn.get(lc(upn));
  const f = $('#actionFields');
  f.innerHTML = { updateUser: `<label>Department <select name="department">${deptOptions(u.department)}</select></label><label>Job title <input name="jobTitle" value="${esc(u.jobTitle)}"></label>`,
    setManager: `<label>New manager <select name="manager" required>${userOptions(u.manager, upn)}</select></label>`,
    addToGroup: `<label>Group <select name="group">${S.groups.filter((g) => !groupsOf(upn).includes(g)).map((g) => `<option>${esc(g.displayName)}</option>`).join('')}</select></label>`,
    removeFromGroup: `<input type="hidden" name="group" value="${esc(group)}"><p>${esc(group)}</p>` }[action] || '';
  $('#actionTitle').textContent = `${LABEL[action]}: ${u.displayName}`;
  $('#actionNote').textContent = action === 'resetPassword' ? noteFor(action) + ' A temporary password is shown here once, only in this tab. Keep the tab open until it appears.' : noteFor(action);
  $('#actionOk').disabled = false;
  const dlg = $('#actionDialog'); $('#actionForm').reset(); dlg.returnValue = '';
  dlg.onclose = async () => {
    if (dlg.returnValue !== 'ok') return;
    const data = { action, userPrincipalName: upn, ...Object.fromEntries(new FormData($('#actionForm')).entries()) };
    if (action === 'resetPassword') return resetPassword(data);
    await submit(data);
  };
  dlg.showModal();
}
async function submit(data) {
  try {
    const r = await api('requests', { method: 'POST', body: JSON.stringify(data) });
    banner(r.note ? `${r.note}` : r.state === 'pending' ? `Filed as request #${r.number}. Waiting for an approver.` : `Filed as request #${r.number}. Applying now; the list refreshes after the readback.`);
  } catch (e) { banner('Not filed: ' + e.message); }
}

// ---------- create ----------
function slug(s) { return lc(s).normalize('NFKD').replace(/[^a-z]/g, ''); }
function suggestUpn() {
  const f = $('#createForm'); const base = `${slug(f.first.value)}.${slug(f.last.value)}`; let c = base; let i = 2;
  while (S.byUpn.has(lc(c + SUFFIX))) c = base + i++;
  if (!f.userPrincipalName.dataset.touched) f.userPrincipalName.value = f.first.value && f.last.value ? c + SUFFIX : '';
}

// ---------- groups / org ----------
function renderGroups() {
  $('#groupList').innerHTML = S.groups.slice().sort((a, b) => a.displayName.localeCompare(b.displayName)).map((g) => `<details class="card"><summary><span class="logo sm">${esc(deptOf(g)[0])}</span><b>${esc(deptOf(g))}</b> <span class="muted">${g.members.length} members</span></summary><div class="members">${g.members.map((m) => `<div class="person">${avatar(nameOf(m), 'sm')}<div><a href="#" data-open="${esc(m)}">${esc(nameOf(m))}</a><div class="muted">${esc(S.byUpn.get(lc(m))?.jobTitle || '')}</div></div></div>`).join('')}</div></details>`).join('');
}
function renderOrg() {
  const kids = new Map(); for (const u of S.users) { const k = lc(u.manager); if (!kids.has(k)) kids.set(k, []); kids.get(k).push(u); }
  const node = (u, depth) => `<li><a href="#" data-open="${esc(u.userPrincipalName)}">${esc(u.displayName)}</a> <span class="muted">${esc(u.jobTitle)}</span>${depth < 3 && kids.get(lc(u.userPrincipalName)) ? `<ul class="tree">${kids.get(lc(u.userPrincipalName)).sort((a, b) => a.department.localeCompare(b.department)).map((c) => node(c, depth + 1)).join('')}</ul>` : ''}</li>`;
  const roots = S.users.filter((u) => !u.manager && u.department);
  $('#orgTree').innerHTML = `<ul class="tree">${roots.map((r) => node(r, 0)).join('')}</ul>`;
}

// ---------- requests ----------
function reqRow(r, withButtons) {
  const own = lc(r.requestedBy) === lc(S.me.user);
  const btn = withButtons ? `${S.me.approver && !own ? `<button class="primary" data-decide="approve" data-n="${r.number}">Approve</button>` : ''}${S.me.approver || own ? `<button data-decide="reject" data-n="${r.number}">Reject</button>` : ''}` : '';
  return `<div class="card"><span class="pill ${esc(r.kind)}">${esc(r.kind)}</span> <span class="pill ${esc(r.state)}">${esc(r.state)}</span>
    <b>${esc(LABEL[r.action] || r.action)}</b> ${esc(nameOf(r.userPrincipalName))}${r.group ? ' &rarr; ' + esc(r.group) : ''}${r.manager ? ' &rarr; ' + esc(nameOf(r.manager)) : ''}${r.jobTitle ? ' &middot; ' + esc(r.jobTitle) : ''}
    <div class="muted">by ${esc(r.requestedBy)} &middot; ${esc(r.reason)} &middot; <a href="${esc(r.url)}" target="_blank" rel="noopener">#${r.number}</a></div><div class="actions">${btn}</div></div>`;
}
async function loadRequests() {
  try {
    const r = await api('requests'); S.configured = r.configured; S.requests = r.requests;
    const pending = r.requests.filter((x) => x.state === 'pending');
    $('#pendingCount').textContent = pending.length ? String(pending.length) : ''; if ($('#stats').innerHTML) renderStats();
    $('#pendingList').innerHTML = pending.map((x) => reqRow(x, true)).join('') || '<p class="muted">Nothing waiting.</p>';
    $('#recentList').innerHTML = r.requests.filter((x) => x.state !== 'pending').slice(0, 20).map((x) => reqRow(x, false)).join('') || `<p class="muted">${r.configured ? 'No requests yet.' : 'Requests are in preview mode until the request token is set up.'}</p>`;
  } catch (e) { $('#pendingList').textContent = 'Could not load requests: ' + e.message; }
}

function renderStats() {
  const off = S.users.filter((u) => u.accountEnabled === false).length; const mgr = S.users.filter((u) => !u.manager).length;
  $('#stats').innerHTML = [[S.users.length, 'People'], [S.groups.length, 'Departments'], [off, 'Disabled'], [mgr, 'Without manager'], [S.requests.filter((r) => r.state === 'pending').length, 'Waiting for approval']].map(([n, l]) => `<div class="stat"><b>${n}</b><span>${l}</span></div>`).join('');
}
function applyTheme(t) { document.documentElement.dataset.theme = t; try { localStorage.setItem('esther-theme', t); } catch {} }
applyTheme((() => { try { return localStorage.getItem('esther-theme'); } catch { return null; } })() || 'dark');
$('#theme').addEventListener('click', () => applyTheme(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark'));
// ---------- password reset ----------
// One-time RSA-OAEP key pair made in this tab; the private key cannot be exported and is dropped after use.
async function resetPassword(data) {
  const kp = await crypto.subtle.generateKey({ name: 'RSA-OAEP', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, false, ['encrypt', 'decrypt']);
  const jwk = await crypto.subtle.exportKey('jwk', kp.publicKey);
  let r; try { r = await api('requests', { method: 'POST', body: JSON.stringify({ ...data, publicKey: { kty: jwk.kty, n: jwk.n, e: jwk.e } }) }); } catch (e) { return banner('Not filed: ' + e.message); }
  if (!r.number) return banner(r.note || 'Not filed.');
  banner(r.state === 'pending' ? `Filed as request #${r.number}. Waiting for an approver; keep this tab open to receive the temporary password.` : `Filed as request #${r.number}. Setting the password...`);
  const until = Date.now() + 6 * 3600e3; let key = kp.privateKey;
  while (key && Date.now() < until) {
    await new Promise((ok) => setTimeout(ok, 8000));
    let s; try { s = await api(`requests/${r.number}/secret`); } catch { continue; }
    if (s.failed) { key = null; return banner(`Password reset #${r.number} failed. See the request for details.`); }
    if (!s.ready) continue;
    const pt = await crypto.subtle.decrypt({ name: 'RSA-OAEP' }, key, Uint8Array.from(atob(s.ciphertext), (c) => c.charCodeAt(0))); key = null;
    const pw = new TextDecoder().decode(pt); const d = document.createElement('dialog');
    d.innerHTML = `<h3>Temporary password</h3><p>${esc(nameOf(data.userPrincipalName))} must change it at next sign-in. It will not be shown again.</p><p><code class="pw"></code></p><div class="actions"><button type="button" data-copy>Copy</button><button type="button" class="primary" data-done>Done</button></div>`;
    d.querySelector('.pw').textContent = pw; document.body.append(d);
    d.querySelector('[data-copy]').onclick = () => navigator.clipboard.writeText(pw);
    d.querySelector('[data-done]').onclick = () => { d.close(); d.remove(); }; d.showModal(); banner(`Password reset #${r.number} done.`); return;
  }
}

// ---------- templates ----------
function headOf(dept) { const m = S.users.filter((u) => u.department === dept); return m.find((u) => !m.some((x) => lc(x.userPrincipalName) === lc(u.manager))); }
function onDeptChange() {
  const f = $('#createForm'); const d = f.department.value; const t = S.me?.templates?.departments?.[d];
  $('#titleList').innerHTML = (t?.titles || []).map((x) => `<option value="${esc(x)}">`).join('');
  const h = headOf(d); if (h && !f.manager.dataset.touched) f.manager.value = h.userPrincipalName;
}

// ---------- reports ----------
let lastReport = [];
function renderReport() {
  const k = $('#reportSel').value; let head = []; let rows = [];
  const depts = [...new Set(S.users.map((u) => u.department))].sort();
  if (k === 'dept') { head = ['Department', 'People', 'Head', 'Disabled']; rows = depts.map((d) => { const m = S.users.filter((u) => u.department === d); return [d, m.length, headOf(d)?.displayName || '', m.filter((u) => u.accountEnabled === false).length]; }); }
  if (k === 'nomgr') { head = ['Name', 'UPN', 'Department', 'Title']; rows = S.users.filter((u) => !u.manager).map((u) => [u.displayName, u.userPrincipalName, u.department, u.jobTitle]); }
  if (k === 'disabled') { head = ['Name', 'UPN', 'Department']; rows = S.users.filter((u) => u.accountEnabled === false).map((u) => [u.displayName, u.userPrincipalName, u.department]); }
  if (k === 'titles') { head = ['Department', 'Title', 'People']; const c = {}; S.users.forEach((u) => { const key = u.department + '|' + u.jobTitle; c[key] = (c[key] || 0) + 1; }); rows = Object.entries(c).sort().map(([key, n]) => [...key.split('|'), n]); }
  if (k === 'span') { head = ['Manager', 'Title', 'Direct reports']; const c = {}; S.users.forEach((u) => { if (u.manager) c[lc(u.manager)] = (c[lc(u.manager)] || 0) + 1; }); rows = Object.entries(c).sort((a, b) => b[1] - a[1]).map(([m, n]) => [nameOf(m), S.byUpn.get(m)?.jobTitle || '', n]); }
  if (k === 'rules') { head = ['Rule', 'Findings', 'Examples']; const staff = S.users.filter((u) => u.department); const tp = S.me?.templates?.departments || {};
    const chk = [['Everyone except the CEO has a manager', staff.filter((u) => !u.manager && !/chief executive/i.test(u.jobTitle || '')).map((u) => u.displayName)],
      ['Manager is an existing, enabled user', staff.filter((u) => u.manager && (!S.byUpn.get(lc(u.manager)) || S.byUpn.get(lc(u.manager)).accountEnabled === false)).map((u) => u.displayName)],
      ['In their department group', staff.filter((u) => !S.groups.some((g) => deptOf(g) === u.department && g.members.some((m) => lc(m) === lc(u.userPrincipalName)))).map((u) => u.displayName)],
      ['Disabled users removed from groups', staff.filter((u) => u.accountEnabled === false && S.groups.some((g) => g.members.some((m) => lc(m) === lc(u.userPrincipalName)))).map((u) => u.displayName)],
      ['Title matches the department template', staff.filter((u) => tp[u.department] && u.jobTitle && !tp[u.department].titles.includes(u.jobTitle)).map((u) => `${u.displayName} (${u.jobTitle})`)]];
    rows = chk.map(([t, h]) => [t, h.length ? h.length : 'OK', h.slice(0, 3).join(', ')]); }
  lastReport = [head, ...rows];
  $('#reportOut').innerHTML = `<table><thead><tr>${head.map((h) => `<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${rows.map((r) => `<tr>${r.map((c) => `<td>${esc(c)}</td>`).join('')}</tr>`).join('') || `<tr><td colspan="${head.length}">Nothing to show.</td></tr>`}</tbody></table>`;
}
function downloadCsv() {
  const csv = lastReport.map((r) => r.map((c) => `"${String(c ?? '').replace(/"/g, '""')}"`).join(',')).join('\n');
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv' })); a.download = `esther-${$('#reportSel').value}.csv`; a.click();
}

// ---------- bulk ----------
let bulkRows = [];
function parseCsv(t) {
  const lines = t.trim().split(/\r?\n/).filter(Boolean); if (lines.length < 2) return [];
  const split = (l) => { const out = []; let cur = ''; let q = false; for (let i = 0; i < l.length; i++) { const ch = l[i]; if (q) { if (ch === '"' && l[i + 1] === '"') { cur += '"'; i++; } else if (ch === '"') q = false; else cur += ch; } else if (ch === '"') q = true; else if (ch === ',') { out.push(cur); cur = ''; } else cur += ch; } out.push(cur); return out.map((x) => x.trim()); };
  const h = split(lines[0]); return lines.slice(1).map((l) => Object.fromEntries(split(l).map((v, i) => [h[i], v]).filter(([k, v]) => k && v)));
}
function bulkPreview() {
  bulkRows = parseCsv($('#csvIn').value); const reason = $('#bulkReason').value.trim();
  bulkRows.forEach((r) => { if (!r.reason) r.reason = reason; });
  const bad = bulkRows.filter((r) => !r.action || !r.userPrincipalName);
  $('#bulkOut').innerHTML = `<p>${bulkRows.length} rows${bad.length ? `, <b>${bad.length} missing action or UPN</b>` : ''}. The server checks every row again before filing.</p><table><thead><tr><th>Action</th><th>User</th><th>Details</th></tr></thead><tbody>${bulkRows.slice(0, 50).map((r) => `<tr><td>${esc(r.action)}</td><td>${esc(r.displayName || nameOf(r.userPrincipalName))}</td><td class="muted">${esc([r.department, r.jobTitle, r.manager && 'mgr ' + nameOf(r.manager), r.group].filter(Boolean).join(' · '))}</td></tr>`).join('')}</tbody></table>`;
  $('#bulkSubmit').disabled = !bulkRows.length || bad.length > 0 || !reason;
}

// ---------- boot ----------
async function load() {
  await appSignIn();
  try {
    S.me = await api('me'); $('#who').textContent = `${S.me.user.split('@')[0]}${S.me.approver ? ' · approver' : S.me.helpdesk ? ' · help desk' : ''}`; $('#meAvatar').outerHTML = avatar(S.me.user.split('@')[0].replace(/[.-]/g, ' '), 'sm');
    const d = await api('directory');
    S.users = d.users.filter((u) => u.department); S.dirAt = d.generatedAt; S.groups = d.groups; S.byUpn = new Map(d.users.map((u) => [lc(u.userPrincipalName), u]));
    $('#snapshot').textContent = d.generatedAt ? `Directory as of ${new Date(d.generatedAt).toLocaleString()} (refreshes after every applied change).` : 'No directory snapshot yet.';
    const depts = S.groups.map(deptOf).sort();
    $('#deptFilter').innerHTML = '<option value="">All departments</option>' + depts.map((x) => `<option>${esc(x)}</option>`).join('');
    document.querySelectorAll('.deptSelect').forEach((s) => { s.innerHTML = deptOptions(''); });
    document.querySelectorAll('.userSelect').forEach((s) => { s.innerHTML = userOptions(''); });
    onDeptChange(); renderStats(); renderUsers(); renderGroups(); renderOrg(); loadRequests(); applyRole(); route();
  } catch (e) { banner(/^Not allowed/.test(e.message) ? 'You are signed in, but you have no Esther portal role. Ask an admin to add you to an Esther Portal group.' : 'Load failed: ' + e.message); }
}
document.addEventListener('click', async (e) => {
  const t = e.target.closest('[data-view],[data-open],[data-upn],[data-act],[data-back],[data-decide]'); if (!t) return;
  if (t.dataset.view) show(t.dataset.view);
  else if (t.dataset.open) { e.preventDefault(); openUser(t.dataset.open); }
  else if (t.dataset.upn) openUser(t.dataset.upn);
  else if (t.dataset.back !== undefined) show('users');
  else if (t.dataset.act) openAction(t.dataset.act, t.dataset.group);
  else if (t.dataset.decide) {
    t.disabled = true;
    try { const r = await api(`requests/${t.dataset.n}/${t.dataset.decide}`, { method: 'POST' }); banner(`Request #${r.number}: ${r.state}.`); }
    catch (err) { banner('Failed: ' + err.message); }
    loadRequests();
  }
});
['#q', '#deptFilter', '#showDisabled'].forEach((s) => $(s).addEventListener('input', renderUsers));
$('#createForm').addEventListener('change', (e) => { if (e.target.name === 'department') onDeptChange(); if (e.target.name === 'manager') e.target.dataset.touched = '1'; });
$('#reportSel').addEventListener('change', renderReport); $('#csvBtn').addEventListener('click', downloadCsv);
$('#bulkPreview').addEventListener('click', bulkPreview);
$('#csvFile').addEventListener('change', async (e) => { const f = e.target.files[0]; if (f) { $('#csvIn').value = await f.text(); bulkPreview(); } });
$('#bulkSubmit').addEventListener('click', async () => { $('#bulkSubmit').disabled = true; await submit({ batch: bulkRows }); });
$('#createForm').addEventListener('input', (e) => { if (e.target.name === 'userPrincipalName') e.target.dataset.touched = '1'; else if (e.target.name === 'first' || e.target.name === 'last') suggestUpn(); });
$('#createForm').addEventListener('submit', async (e) => {
  e.preventDefault(); const f = new FormData(e.target);
  await submit({ action: 'createUser', userPrincipalName: f.get('userPrincipalName'), displayName: `${f.get('first')} ${f.get('last')}`.trim(), department: f.get('department'), jobTitle: f.get('jobTitle'), manager: f.get('manager'), reason: f.get('reason') });
});

// ---------- admin console ----------
S.log = null;
const ago = (t) => { const s = (Date.now() - Date.parse(t)) / 1000; return s < 90 ? 'just now' : s < 5400 ? `${Math.round(s / 60)} min ago` : s < 129600 ? `${Math.round(s / 3600)} h ago` : `${Math.round(s / 86400)} d ago`; };
const stCls = (x) => ({ success: 'applied', applied: 'applied', failure: 'rejected', rejected: 'rejected', cancelled: 'rejected', pending: 'pending', in_progress: 'pending', queued: 'pending' }[x] || '');
async function loadAdmin() {
  try { S.log = await api('admin/log'); } catch (e) { $('#admAsOf').textContent = 'Could not load the log: ' + e.message; return; }
  const L = S.log; const ev = L.events || []; const day = Date.now() - 864e5;
  const req24 = ev.filter((x) => x.source === 'request' && Date.parse(x.ts) > day).length;
  const fail7 = (L.workflows || []).reduce((a, w) => a + w.fail7, 0); const ok7 = (L.workflows || []).reduce((a, w) => a + w.ok7, 0);
  $('#admStats').innerHTML = [[L.directory?.users ?? '-', 'Accounts'], [L.directory?.disabled ?? '-', 'Disabled'], [req24, 'Requests, 24 h'], [ok7 ? Math.round((100 * ok7) / (ok7 + fail7)) + '%' : '-', 'Automation success, 7 d'], [fail7, 'Failed runs, 7 d']]
    .map(([b, t]) => `<div class="stat"><b>${esc(b)}</b><span>${esc(t)}</span></div>`).join('');
  const key = ['esther-apply', 'esther-swa-deploy', 'esther-password', 'esther-scheduled', 'esther-costs-read'];
  $('#admFlows').innerHTML = (L.workflows || []).sort((a, b) => (key.indexOf(a.name) + 1 || 99) - (key.indexOf(b.name) + 1 || 99)).slice(0, 10)
    .map((w) => `<a class="flow" href="${esc(w.url)}" target="_blank" rel="noopener"><span class="pill ${stCls(w.last)}">${esc(w.last || '?')}</span><b>${esc(w.name)}</b><span class="muted">${w.lastAt ? ago(w.lastAt) : ''} · 7 d: ${w.ok7} ok / ${w.fail7} failed</span></a>`).join('');
  $('#admAsOf').textContent = `Log built ${L.generatedAt ? ago(L.generatedAt) : 'never'} (refreshes on every deploy, which follows every applied change). Directory snapshot ${L.directory?.generatedAt ? ago(L.directory.generatedAt) : 'n/a'}.`;
  const C = L.cost; const vm = L.vms || [];
  $('#admCost').innerHTML = C ? `<div class="stat"><b>${esc(C.currency)} ${esc(C.last30dTotal)}</b><span>Total, 30 days</span></div>
    <div class="meters">${(C.byMeter || []).map((m) => `<div><span>${esc(m.meter)}</span><b>${esc(C.currency)} ${esc(m.cost.toFixed(4))}</b></div>`).join('') || '<p class="muted">No usage.</p>'}</div>
    <div class="meters">${vm.map((v) => `<div><span>VM ${esc(v.name)} (${esc(v.size)})</span><b class="${/running/i.test(v.power) ? 'warnTxt' : 'okTxt'}">${esc(v.power || 'unknown')}</b></div>`).join('')}</div>
    <p class="muted">Read ${C.readAt ? ago(C.readAt) : 'n/a'} by esther-costs-read (daily, read-only). No budgets or billing are touched.</p>` : '<p class="muted">No cost read yet.</p>';
  renderLog();
}
function logRows() {
  const src = $('#admSrc').value; const st = $('#admStatus').value; const q = lc($('#admQ').value);
  return (S.log?.events || []).filter((x) => (!src || x.source === src) && (!st || x.status === st) && (!q || lc(`${x.actor} ${x.action} ${x.target} ${x.detail}`).includes(q)));
}
function renderLog() {
  $('#admTable tbody').innerHTML = logRows().slice(0, 200).map((x) => `<tr data-href="${esc(x.url)}"><td title="${esc(x.ts)}">${esc(new Date(x.ts).toLocaleString())}</td><td><span class="src ${esc(x.source)}">${esc(x.source)}</span></td><td>${esc(x.actor)}</td><td><b>${esc(LABEL[x.action] || x.action)}</b><div class="muted">${esc(x.detail)}</div></td><td>${esc(x.source === 'request' ? nameOf(x.target) : x.target)}</td><td><span class="pill ${stCls(x.status)}">${esc(x.status)}</span></td></tr>`).join('') || '<tr><td colspan="6" class="muted">No matching entries.</td></tr>';
}
['#admSrc', '#admStatus', '#admQ'].forEach((s) => $(s).addEventListener('input', renderLog));
$('#admTable').addEventListener('click', (e) => { const r = e.target.closest('tr[data-href]'); if (r && r.dataset.href) window.open(r.dataset.href, '_blank', 'noopener'); });
$('#admCsv').addEventListener('click', () => {
  const q = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const csv = ['time,source,actor,action,target,status,detail,url'].concat(logRows().map((x) => [x.ts, x.source, x.actor, x.action, x.target, x.status, x.detail, x.url].map(q).join(','))).join('\n');
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv' })); a.download = `estherdaxes-activity-${new Date().toISOString().slice(0, 10)}.csv`; a.click();
});

// ---------- help desk ----------
function renderHelpdesk() {
  const q = lc($('#hdq').value).trim();
  const hits = q.length < 2 ? [] : S.users.filter((u) => lc(`${u.displayName} ${u.userPrincipalName} ${u.jobTitle || ''}`).includes(q)).slice(0, 12);
  $('#hdResults').innerHTML = q.length < 2 ? '<p class="muted">Type at least 2 letters.</p>' : hits.map((u) => `<button class="hdhit" data-hd="${esc(u.userPrincipalName)}">${avatar(u.displayName, 'sm')}<span><b>${esc(u.displayName)}</b><small>${esc(u.jobTitle || '')} · ${esc(u.department || '')}</small></span>${chip(u)}</button>`).join('') || '<p class="muted">No one matches.</p>';
}
function hdCard(upn) {
  const u = S.byUpn.get(lc(upn)); if (!u) return;
  const mine = S.requests.filter((r) => lc(r.userPrincipalName) === lc(upn)).slice(0, 5);
  $('#hdCard').innerHTML = `<div class="card hd"><div class="hero">${avatar(u.displayName, 'lg')}<div><h2>${esc(u.displayName)}</h2><div class="muted">${esc(u.userPrincipalName)}</div><div>${esc(u.jobTitle || '')} · ${esc(u.department || '')} ${chip(u)}</div></div></div>
    <dl class="kv"><dt>Manager</dt><dd>${esc(nameOf(u.manager) || '-')}</dd><dt>Groups</dt><dd>${groupsOf(upn).map((g) => esc(deptOf(g))).join(', ') || '-'}</dd></dl>
    <div class="actions"><button class="primary" data-act="resetPassword">Reset password</button>${u.accountEnabled === false ? '<button data-act="enableUser">Re-enable sign-in</button>' : ''}</div>
    <h3>Recent requests for this person</h3>${mine.map((r) => reqRow(r, false)).join('') || '<p class="muted">None.</p>'}</div>`;
  $('#detail').dataset.upn = u.userPrincipalName;
}
$('#hdq').addEventListener('input', renderHelpdesk);
$('#hdResults').addEventListener('click', (e) => { const b = e.target.closest('[data-hd]'); if (b) hdCard(b.dataset.hd); });
function applyRole() {
  const hd = !!S.me?.helpdesk;
  document.querySelectorAll('nav [data-view="create"],nav [data-view="bulk"],nav .adminOnly').forEach((b) => { b.hidden = hd; });
  if (hd && !location.hash) show('helpdesk');
}
function route() { const h = decodeURIComponent(location.hash.slice(1)); if (h.startsWith('user=')) openUser(h.slice(5)); else if (h && document.getElementById(h)) show(h); else if (!h && !S.me?.helpdesk) show('dashboard'); }
window.addEventListener('hashchange', route);
load();
