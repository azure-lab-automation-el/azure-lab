'use strict';
// Estherdaxes Pro: Dashboard (charts), Lifecycle (joiner / mover / leaver) and Audit log search.
// Loaded after app.js and reuses its helpers (S, $, esc, lc, api, submit, nameOf, avatar, deptOf, LABEL, GP).
// Charts are plain SVG: no chart library, nothing to pay for, nothing loaded from third parties.
Object.assign(LABEL, { createUser: 'Create user', joiner: 'Joiner', mover: 'Mover', leaver: 'Leaver', bulk: 'Bulk change' });
const P = { range: '30', page: 0, open: null };
const fmt = (n) => Number(n).toLocaleString('en-US');
const dayKey = (t) => new Date(t).toISOString().slice(0, 10);
const lastDays = (n) => Array.from({ length: n }, (_, i) => dayKey(Date.now() - (n - 1 - i) * 864e5));
async function ensureLog() { if (S.log || S.me?.helpdesk) return S.log; try { S.log = await api('admin/log'); } catch { S.log = null; } return S.log; }
const cssVar = (n) => getComputedStyle(document.documentElement).getPropertyValue(n).trim();

// ---------- tiny SVG chart kit ----------
function spark(vals, w = 120, h = 34) {
  const max = Math.max(1, ...vals); const st = w / Math.max(1, vals.length - 1);
  const pts = vals.map((v, i) => `${(i * st).toFixed(1)},${(h - 3 - (v / max) * (h - 6)).toFixed(1)}`).join(' ');
  return `<svg class="spark" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none"><defs><linearGradient id="sg" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="#3b9eff" stop-opacity=".45"/><stop offset="1" stop-color="#3b9eff" stop-opacity="0"/></linearGradient></defs><polygon fill="url(#sg)" points="0,${h} ${pts} ${w},${h}"/><polyline fill="none" stroke="#3b9eff" stroke-width="2" stroke-linejoin="round" points="${pts}"/></svg>`;
}
function hbars(rows, opts = {}) { // rows: [{label, a, b}] a = main, b = stacked secondary
  const max = Math.max(1, ...rows.map((r) => r.a + (r.b || 0)));
  return `<div class="hbars">${rows.map((r) => `<div class="hb" ${r.key ? `data-key="${esc(r.key)}"` : ''}><span class="hbl" title="${esc(r.label)}">${esc(r.label)}</span><span class="hbt"><i style="width:${(100 * r.a) / max}%"></i>${r.b ? `<i class="b2" style="width:${(100 * r.b) / max}%"></i>` : ''}</span><b>${fmt(r.a + (r.b || 0))}</b></div>`).join('')}</div>${opts.legend ? `<div class="legend">${opts.legend}</div>` : ''}`;
}
function donut(parts, center, sub) { // parts: [{v, c, label}]
  const tot = parts.reduce((a, p) => a + p.v, 0) || 1; const R = 52; const C = 2 * Math.PI * R; let off = 0;
  const arcs = parts.map((p) => { const len = (p.v / tot) * C; const s = `<circle r="${R}" cx="70" cy="70" fill="none" stroke="${p.c}" stroke-width="16" stroke-dasharray="${len} ${C - len}" stroke-dashoffset="${-off}" transform="rotate(-90 70 70)" stroke-linecap="butt"/>`; off += len; return s; }).join('');
  return `<div class="donut"><svg viewBox="0 0 140 140"><circle r="${R}" cx="70" cy="70" fill="none" stroke="var(--line)" stroke-width="16"/>${arcs}<text x="70" y="68" text-anchor="middle" class="dc">${esc(center)}</text><text x="70" y="88" text-anchor="middle" class="ds">${esc(sub)}</text></svg>
    <div class="legend col">${parts.map((p) => `<span><i style="background:${p.c}"></i>${esc(p.label)} <b>${fmt(p.v)}</b></span>`).join('')}</div></div>`;
}
function columns(days, series, h = 170) { // series: [{name, c, vals}]
  const W = 640; const n = days.length; const bw = W / n; const max = Math.max(1, ...days.map((_, i) => series.reduce((a, s) => a + s.vals[i], 0)));
  let bars = ''; days.forEach((d, i) => { let y = h - 18; series.forEach((s) => { const v = s.vals[i]; if (!v) return; const bh = (v / max) * (h - 34); y -= bh; bars += `<rect x="${(i * bw + bw * 0.18).toFixed(1)}" y="${y.toFixed(1)}" width="${(bw * 0.64).toFixed(1)}" height="${bh.toFixed(1)}" rx="3" fill="${s.c}"><title>${d}: ${v} ${s.name}</title></rect>`; }); });
  const lab = days.map((d, i) => (i % Math.ceil(n / 7) === 0 || i === n - 1 ? `<text x="${(i * bw + bw / 2).toFixed(1)}" y="${h - 3}" text-anchor="middle" class="ax">${d.slice(5)}</text>` : '')).join('');
  const grid = [0.25, 0.5, 0.75, 1].map((f) => `<line x1="0" x2="${W}" y1="${(h - 18 - f * (h - 34)).toFixed(1)}" y2="${(h - 18 - f * (h - 34)).toFixed(1)}" class="gl"/><text x="2" y="${(h - 21 - f * (h - 34)).toFixed(1)}" class="ax">${Math.round(f * max)}</text>`).join('');
  return `<svg class="cols" viewBox="0 0 ${W} ${h}">${grid}${bars}${lab}</svg><div class="legend">${series.map((s) => `<span><i style="background:${s.c}"></i>${esc(s.name)} <b>${fmt(s.vals.reduce((a, b) => a + b, 0))}</b></span>`).join('')}</div>`;
}
function line(days, vals, unit, h = 150) {
  const W = 640; const max = Math.max(...vals, 0) || 1; const st = W / Math.max(1, days.length - 1);
  const pts = vals.map((v, i) => `${(i * st).toFixed(1)},${(h - 20 - (v / max) * (h - 36)).toFixed(1)}`).join(' ');
  const lab = days.map((d, i) => (i % Math.ceil(days.length / 6) === 0 || i === days.length - 1 ? `<text x="${Math.min(W - 16, Math.max(16, i * st)).toFixed(1)}" y="${h - 4}" text-anchor="middle" class="ax">${d.slice(5)}</text>` : '')).join('');
  return `<svg class="cols" viewBox="0 0 ${W} ${h}"><defs><linearGradient id="lg" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="#22c3ff" stop-opacity=".35"/><stop offset="1" stop-color="#22c3ff" stop-opacity="0"/></linearGradient></defs>
    <line x1="0" x2="${W}" y1="${h - 20}" y2="${h - 20}" class="gl"/><polygon fill="url(#lg)" points="0,${h - 20} ${pts} ${W},${h - 20}"/><polyline fill="none" stroke="#22c3ff" stroke-width="2.4" points="${pts}"/>
    ${vals.map((v, i) => (v ? `<circle cx="${(i * st).toFixed(1)}" cy="${(h - 20 - (v / max) * (h - 36)).toFixed(1)}" r="3" fill="#22c3ff"><title>${days[i]}: ${unit} ${v.toFixed(4)}</title></circle>` : '')).join('')}${lab}<text x="4" y="12" class="ax">max ${unit} ${max.toFixed(4)}</text></svg>`;
}

// ---------- dashboard ----------
async function renderDash() {
  const u = S.users; if (!u.length) return;
  const act = u.filter((x) => x.accountEnabled !== false).length; const off = u.length - act;
  const depts = S.groups.map(deptOf);
  const byDept = depts.map((d) => ({ label: d, key: d, a: u.filter((x) => x.department === d && x.accountEnabled !== false).length, b: u.filter((x) => x.department === d && x.accountEnabled === false).length })).sort((a, b) => b.a + b.b - (a.a + a.b));
  const reports = new Map(); u.forEach((x) => { if (x.manager) reports.set(lc(x.manager), (reports.get(lc(x.manager)) || 0) + 1); });
  const mgrs = [...reports.entries()].sort((a, b) => b[1] - a[1]).slice(0, 7).map(([m, n]) => ({ label: nameOf(m), a: n }));
  const noMgr = u.filter((x) => !x.manager).length;
  const hour = new Date().getHours(); const hi = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
  $('#dashHead').innerHTML = `<div><h1>${hi}, ${esc((S.me?.user || '').split('@')[0].split(/[.-]/)[0].replace(/^./, (c) => c.toUpperCase()))}</h1><p class="muted">Esther Hospital identity overview · directory as of ${S.dirAt ? new Date(S.dirAt).toLocaleString() : 'n/a'}</p></div>
    <div class="quick"><button class="primary" data-view="lifecycle" data-lc="joiner">+ New joiner</button><button data-view="lifecycle" data-lc="mover">Move someone</button><button data-view="lifecycle" data-lc="leaver">Offboard</button></div>`;
  const L = await ensureLog(); const ev = L?.events || [];
  const d14 = lastDays(14); const cnt = (src) => d14.map((d) => ev.filter((e) => e.source === src && dayKey(e.ts) === d).length);
  const req30 = ev.filter((e) => e.source === 'request' && Date.parse(e.ts) > Date.now() - 30 * 864e5).length;
  const wf = L?.workflows || []; const ok7 = wf.reduce((a, w) => a + w.ok7, 0); const f7 = wf.reduce((a, w) => a + w.fail7, 0);
  const cost = L?.cost; const pend = (S.requests || []).filter((r) => r.state === 'pending').length;
  const kpi = [
    ['People', fmt(u.length), `${fmt(act)} active`, spark(d14.map((d) => u.length))],
    ['Active accounts', `${Math.round((100 * act) / u.length)}%`, `${off} disabled`, `<div class="ring" style="--p:${(100 * act) / u.length}"></div>`],
    ['Departments', depts.length, `${noMgr} without manager`, ''],
    ['Requests, 30 d', L ? req30 : '-', `${pend} waiting for approval`, L ? spark(cnt('request')) : ''],
    ['Automation, 7 d', L && ok7 + f7 ? `${Math.round((100 * ok7) / (ok7 + f7))}%` : '-', L ? `${ok7} ok · ${f7} failed` : 'admins only', L ? spark(cnt('workflow')) : ''],
    ['Azure cost, 30 d', cost ? `$${cost.last30dTotal}` : '-', cost ? 'read-only, from the $200 credit' : 'no cost read yet', cost ? spark((cost.daily || []).map((x) => x.cost)) : ''],
  ];
  $('#dashKpi').innerHTML = kpi.map(([t, v, s, g]) => `<div class="kpi"><span class="kt">${esc(t)}</span><b>${esc(v)}</b><span class="ks">${esc(s)}</span>${g}</div>`).join('');
  $('#dashDept').innerHTML = hbars(byDept, { legend: '<span><i class="lg1"></i>Active</span><span><i class="lg2"></i>Disabled</span>' });
  $('#dashStatus').innerHTML = donut([{ v: act, c: '#3b82f6', label: 'Active' }, { v: off, c: '#f59e0b', label: 'Disabled' }], `${Math.round((100 * act) / u.length)}%`, 'active');
  $('#dashMgr').innerHTML = hbars(mgrs);
  $('#dashAct').innerHTML = L ? columns(d14, [{ name: 'Change requests', c: '#3b82f6', vals: cnt('request') }, { name: 'Workflow runs', c: '#22c3ff', vals: cnt('workflow') }, { name: 'Commits', c: '#1d4ed8', vals: cnt('commit') }]) : '<p class="muted">Activity is visible to admins and approvers.</p>';
  const wrows = wf.filter((w) => w.ok7 + w.fail7).sort((a, b) => b.ok7 + b.fail7 - (a.ok7 + a.fail7)).slice(0, 8).map((w) => ({ label: w.name.replace(/^esther-/, ''), a: w.ok7, b: w.fail7 }));
  $('#dashWf').innerHTML = L ? (wrows.length ? hbars(wrows, { legend: '<span><i class="lg1"></i>Succeeded</span><span><i class="lg3"></i>Failed</span>' }) : '<p class="muted">No runs in the last 7 days.</p>') : '<p class="muted">Admins only.</p>';
  $('#dashWf').classList.add('wf');
  const cd = lastDays(30); const cv = cd.map((d) => (cost?.daily || []).filter((x) => x.date === d).reduce((a, x) => a + x.cost, 0));
  $('#dashCost').innerHTML = cost ? line(cd, cv, '$') + `<p class="muted">Total $${cost.last30dTotal} in 30 days. ${(L.vms || []).map((v) => `VM ${esc(v.name)}: ${esc(v.power)}`).join(' · ')}. Read-only; no budgets or billing are touched.</p>` : '<p class="muted">No cost read yet.</p>';
  $('#dashFeed').innerHTML = ev.filter((e) => e.source !== 'commit').slice(0, 7).map((e) => `<div class="fe"><span class="dot ${esc(stCls(e.status))}"></span><div><b>${esc(LABEL[e.action] || e.action)}</b> <span class="muted">${esc(e.source === 'request' ? nameOf(e.target) : e.target)}</span><div class="muted sm">${esc(e.actor)} · ${ago(e.ts)}</div></div></div>`).join('') || '<p class="muted">No activity yet.</p>';
}
document.addEventListener('click', (e) => { const b = e.target.closest('#dashDept [data-key]'); if (b) { $('#deptFilter').value = b.dataset.key; show('users'); renderUsers(); } });

// ---------- lifecycle ----------
const titlesOf = (d) => [...new Set([...(S.me?.templates?.departments?.[d]?.titles || []), ...S.users.filter((x) => x.department === d).map((x) => x.jobTitle).filter(Boolean)])];
const deptSel = (sel) => S.groups.map(deptOf).sort().map((d) => `<option ${d === sel ? 'selected' : ''}>${esc(d)}</option>`).join('');
const personSel = (sel, filt = () => true) => '<option value="">Choose a person</option>' + S.users.filter(filt).sort((a, b) => a.displayName.localeCompare(b.displayName)).map((x) => `<option value="${esc(x.userPrincipalName)}" ${lc(x.userPrincipalName) === lc(sel) ? 'selected' : ''}>${esc(x.displayName)} · ${esc(x.department || '')}</option>`).join('');
function lcTab(t) {
  P.lc = t; document.querySelectorAll('#lcTabs button').forEach((b) => b.classList.toggle('on', b.dataset.lct === t));
  const f = $('#lcForm'); const now = new Date().toISOString().slice(0, 10);
  if (t === 'joiner') f.innerHTML = `<div class="grid2"><label>First name<input name="first" required></label><label>Last name<input name="last" required></label>
    <label>Department<select name="department">${deptSel('')}</select></label><label>Job title<input name="jobTitle" list="lcTitles" required><datalist id="lcTitles"></datalist></label>
    <label>Manager<select name="manager"></select></label><label>Start date<input type="date" name="start" value="${now}"></label>
    <label class="full">Sign-in name<input name="userPrincipalName" required></label><label class="full">Reason<input name="reason" placeholder="e.g. new hire, HR ticket 1234" required></label></div>`;
  if (t === 'mover') f.innerHTML = `<div class="grid2"><label class="full">Person<select name="upn" required>${personSel('', (x) => x.accountEnabled !== false)}</select></label>
    <label>New department<select name="department">${deptSel('')}</select></label><label>New job title<input name="jobTitle" list="lcTitles" required><datalist id="lcTitles"></datalist></label>
    <label>New manager<select name="manager"></select></label><label>Effective date<input type="date" name="start" value="${now}"></label>
    <label class="full">Reason<input name="reason" placeholder="e.g. internal transfer approved by HR" required></label></div>`;
  if (t === 'leaver') f.innerHTML = `<div class="grid2"><label class="full">Person<select name="upn" required>${personSel('', (x) => x.accountEnabled !== false)}</select></label>
    <label>Hand direct reports to<select name="manager"></select></label><label>Last day<input type="date" name="start" value="${now}"></label>
    <label class="chk full"><input type="checkbox" name="groups" checked> Remove from all groups</label><label class="chk full"><input type="checkbox" name="reports" checked> Move direct reports to the new manager</label>
    <label class="full">Reason<input name="reason" placeholder="e.g. resignation, HR ticket 1234" required></label></div>`;
  f.insertAdjacentHTML('beforeend', '<div class="actions"><button type="submit" class="primary" id="lcGo">Submit for approval</button></div>');
  lcSync(true);
}
function lcSync(first) {
  const f = $('#lcForm'); const t = P.lc; const v = (n) => f.elements[n]?.value || '';
  if (f.elements.department) { $('#lcTitles').innerHTML = titlesOf(v('department')).map((x) => `<option value="${esc(x)}">`).join(''); }
  const who = S.byUpn.get(lc(v('upn')));
  if (t === 'joiner' || t === 'mover') {
    const h = headOf(v('department')); const m = f.elements.manager;
    if (!m.dataset.touched || first || m.dataset.dept !== v('department')) { m.innerHTML = personSel(h?.userPrincipalName, (x) => x.accountEnabled !== false && lc(x.userPrincipalName) !== lc(v('upn'))); m.dataset.dept = v('department'); }
  }
  if (t === 'joiner') { const base = `${slug(v('first'))}.${slug(v('last'))}`; let c = base; let i = 2; while (S.byUpn.has(lc(c + SUFFIX))) c = base + i++; if (!f.elements.userPrincipalName.dataset.touched) f.elements.userPrincipalName.value = v('first') && v('last') ? c + SUFFIX : ''; }
  if (t === 'leaver' && (first || f.elements.manager.dataset.for !== v('upn'))) { f.elements.manager.innerHTML = personSel(who?.manager, (x) => x.accountEnabled !== false && lc(x.userPrincipalName) !== lc(v('upn'))); f.elements.manager.dataset.for = v('upn'); }
  const plan = lcPlan(); P.plan = plan;
  $('#lcPlan').innerHTML = `<h3>What will happen</h3>${who || t === 'joiner' ? `<div class="lcwho">${avatar(t === 'joiner' ? `${v('first')} ${v('last')}` : who.displayName, 'lg')}<div><b>${esc(t === 'joiner' ? `${v('first')} ${v('last')}`.trim() || 'New person' : who.displayName)}</b><div class="muted">${esc(t === 'joiner' ? v('userPrincipalName') : who.userPrincipalName)}</div>${who ? `<div class="muted">${esc(who.jobTitle || '')} · ${esc(who.department || '')}</div>` : ''}</div></div>` : '<p class="muted">Choose a person to see the plan.</p>'}
    <ol class="steps">${plan.steps.map((s) => `<li><span class="stp ${s.special ? 'sp' : ''}"></span><div><b>${esc(s.t)}</b>${s.d ? `<div class="muted">${esc(s.d)}</div>` : ''}</div></li>`).join('')}</ol>
    ${plan.steps.length ? `<p class="note">${plan.special ? (S.me?.approver ? 'You are an approver, so this applies as soon as you submit.' : 'Includes steps that need an approver who is not you. It waits in Requests.') : 'Standard change: applies as soon as it is filed.'} The whole plan is one reviewed change request; esther-apply then writes Entra and reads it back.</p>` : ''}`;
}
function lcPlan() {
  const f = $('#lcForm'); const t = P.lc; const v = (n) => f.elements[n]?.value?.trim() || ''; const pol = S.me?.policy?.special || [];
  const reason = v('reason') ? `${v('reason')}${v('start') ? ` (${t === 'leaver' ? 'last day' : 'effective'} ${v('start')})` : ''}` : '';
  const b = []; const steps = []; const add = (item, txt, d) => { b.push({ ...item, reason }); steps.push({ t: txt, d, special: pol.includes(item.action) }); };
  if (t === 'joiner') {
    if (v('first') && v('last')) add({ action: 'createUser', userPrincipalName: v('userPrincipalName'), displayName: `${v('first')} ${v('last')}`, department: v('department'), jobTitle: v('jobTitle'), manager: v('manager') },
      `Create account ${v('userPrincipalName')}`, `${v('jobTitle') || 'no title yet'} in ${v('department')}, manager ${nameOf(v('manager')) || '-'}, usage location IL`);
    if (b.length) steps.push({ t: `Add to ${GP}${v('department')}`, d: 'department group, done with the account' }, { t: 'Initial password', d: 'set once through the protected password flow (never shown in the portal)' });
  }
  const u = S.byUpn.get(lc(v('upn')));
  if (t === 'mover' && u) {
    const nd = v('department'); const groups = groupsOf(u.userPrincipalName);
    if (nd !== u.department || v('jobTitle') !== (u.jobTitle || '')) add({ action: 'updateUser', userPrincipalName: u.userPrincipalName, department: nd, jobTitle: v('jobTitle') }, 'Update department and title', `${u.department} / ${u.jobTitle || '-'} → ${nd} / ${v('jobTitle') || '-'}`);
    if (v('manager') && lc(v('manager')) !== lc(u.manager)) add({ action: 'setManager', userPrincipalName: u.userPrincipalName, manager: v('manager') }, 'Change manager', `${nameOf(u.manager) || '-'} → ${nameOf(v('manager'))}`);
    if (nd !== u.department) {
      groups.filter((g) => g.displayName.startsWith(GP) && deptOf(g) !== nd).forEach((g) => add({ action: 'removeFromGroup', userPrincipalName: u.userPrincipalName, group: g.displayName }, `Remove from ${g.displayName}`));
      if (!groups.some((g) => deptOf(g) === nd)) add({ action: 'addToGroup', userPrincipalName: u.userPrincipalName, group: GP + nd }, `Add to ${GP}${nd}`);
    }
  }
  if (t === 'leaver' && u) {
    add({ action: 'disableUser', userPrincipalName: u.userPrincipalName }, 'Block sign-in', 'the account stays for audit and can be re-enabled');
    if (f.elements.groups?.checked) groupsOf(u.userPrincipalName).forEach((g) => add({ action: 'removeFromGroup', userPrincipalName: u.userPrincipalName, group: g.displayName }, `Remove from ${g.displayName}`));
    const reps = S.users.filter((x) => lc(x.manager) === lc(u.userPrincipalName) && x.accountEnabled !== false);
    if (f.elements.reports?.checked && v('manager')) reps.forEach((x) => add({ action: 'setManager', userPrincipalName: x.userPrincipalName, manager: v('manager') }, `${x.displayName} now reports to ${nameOf(v('manager'))}`));
    else if (reps.length) steps.push({ t: `${reps.length} direct report(s) keep ${u.displayName} as manager`, d: 'the nightly rules check will flag them' });
  }
  return { batch: b, steps, special: b.some((x) => pol.includes(x.action)) };
}
$('#lcTabs')?.addEventListener('click', (e) => { const b = e.target.closest('[data-lct]'); if (b) lcTab(b.dataset.lct); });
$('#lcForm')?.addEventListener('input', (e) => { if (e.target.name === 'userPrincipalName' || e.target.name === 'manager') e.target.dataset.touched = '1'; lcSync(false); });
$('#lcForm')?.addEventListener('submit', async (e) => {
  e.preventDefault(); const p = lcPlan(); if (!p.batch.length) { banner('Nothing to change: pick a different department, title or manager.'); return; }
  $('#lcGo').disabled = true; await submit(p.batch.length === 1 ? { ...p.batch[0], lifecycle: P.lc } : { batch: p.batch, lifecycle: P.lc }); $('#lcGo').disabled = false; loadRequests();
});

// ---------- audit log ----------
function auFilter() {
  const q = lc($('#auQ').value).trim(); const src = $('#auSrc').value; const st = $('#auSt').value; const who = $('#auWho').value; const act = $('#auAct').value;
  const from = $('#auFrom').value ? Date.parse($('#auFrom').value) : P.range === 'all' ? 0 : Date.now() - Number(P.range) * 864e5; const to = $('#auTo').value ? Date.parse($('#auTo').value) + 864e5 : Infinity;
  return (S.log?.events || []).filter((x) => { const t = Date.parse(x.ts); return t >= from && t < to && (!src || x.source === src) && (!st || x.status === st) && (!who || x.actor === who) && (!act || x.action === act) && (!q || lc(`${x.actor} ${x.action} ${LABEL[x.action] || ''} ${x.target} ${nameOf(x.target)} ${x.detail} ${x.status}`).includes(q)); });
}
async function renderAudit() {
  if (!S.log) { $('#auMeta').textContent = 'Loading…'; await ensureLog(); }
  if (!S.log) { $('#auMeta').textContent = 'The audit log is visible to admins and approvers.'; return; }
  const ev = S.log.events || []; const opt = (arr, cur, all) => `<option value="">${all}</option>` + [...new Set(arr)].filter(Boolean).sort().map((x) => `<option ${x === cur ? 'selected' : ''} value="${esc(x)}">${esc(LABEL[x] || x)}</option>`).join('');
  if (!$('#auWho').dataset.ready) { $('#auWho').innerHTML = opt(ev.map((x) => x.actor), '', 'Anyone'); $('#auAct').innerHTML = opt(ev.map((x) => x.action), '', 'Any action'); $('#auWho').dataset.ready = '1'; }
  const rows = auFilter(); const per = 25; const pages = Math.max(1, Math.ceil(rows.length / per)); P.page = Math.min(P.page, pages - 1);
  const by = (k) => rows.reduce((m, x) => ((m[x[k]] = (m[x[k]] || 0) + 1), m), {});
  const bs = by('source');
  $('#auChips').innerHTML = [['', 'All', rows.length], ['request', 'Change requests', bs.request || 0], ['workflow', 'Workflow runs', bs.workflow || 0], ['commit', 'Commits', bs.commit || 0]].map(([k, l, n]) => `<button class="chipf ${$('#auSrc').value === k ? 'on' : ''}" data-src="${k}">${l} <b>${n}</b></button>`).join('');
  const d = lastDays(P.range === 'all' ? 30 : Math.min(30, Number(P.range))); $('#auSpark').innerHTML = columns(d, [{ name: 'events per day (current filter)', c: '#3b82f6', vals: d.map((k) => rows.filter((x) => dayKey(x.ts) === k).length) }], 90);
  $('#auTable tbody').innerHTML = rows.slice(P.page * per, P.page * per + per).map((x, i) => { const id = P.page * per + i; return `<tr data-i="${id}" class="${P.open === id ? 'open' : ''}"><td class="nw" title="${esc(x.ts)}">${esc(new Date(x.ts).toLocaleString())}</td><td><span class="src ${esc(x.source)}">${esc(x.source)}</span></td><td>${esc(x.actor)}</td><td><b>${esc(LABEL[x.action] || x.action)}</b></td><td>${esc(x.source === 'request' ? nameOf(x.target) : x.target)}</td><td><span class="pill ${stCls(x.status)}">${esc(x.status)}</span></td></tr>${P.open === id ? `<tr class="det"><td colspan="6"><dl class="kv"><dt>Time (UTC)</dt><dd>${esc(x.ts)}</dd><dt>Detail</dt><dd>${esc(x.detail || '-')}</dd><dt>Target</dt><dd>${esc(x.target)}</dd><dt>Evidence</dt><dd><a href="${esc(x.url)}" target="_blank" rel="noopener">${esc(x.url)}</a></dd></dl></td></tr>` : ''}`; }).join('') || '<tr><td colspan="6" class="muted">No events match.</td></tr>';
  $('#auMeta').textContent = `${fmt(rows.length)} of ${fmt(ev.length)} events · page ${P.page + 1} of ${pages} · log built ${S.log.generatedAt ? ago(S.log.generatedAt) : 'never'}, refreshed on every deploy`;
  $('#auPrev').disabled = P.page === 0; $('#auNext').disabled = P.page >= pages - 1;
}
const dl = (name, type, text) => { const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([text], { type })); a.download = name; a.click(); };
const stamp = () => new Date().toISOString().slice(0, 16).replace(/[:T]/g, '-');
if ($('#audit')) {
  ['#auQ', '#auSrc', '#auSt', '#auWho', '#auAct', '#auFrom', '#auTo'].forEach((s) => $(s).addEventListener('input', () => { P.page = 0; P.open = null; renderAudit(); }));
  $('#auRange').addEventListener('click', (e) => { const b = e.target.closest('[data-r]'); if (!b) return; P.range = b.dataset.r; P.page = 0; $('#auFrom').value = ''; $('#auTo').value = ''; document.querySelectorAll('#auRange button').forEach((x) => x.classList.toggle('on', x === b)); renderAudit(); });
  $('#auChips').addEventListener('click', (e) => { const b = e.target.closest('[data-src]'); if (b) { $('#auSrc').value = b.dataset.src; P.page = 0; renderAudit(); } });
  $('#auTable').addEventListener('click', (e) => { const r = e.target.closest('tr[data-i]'); if (r) { const i = Number(r.dataset.i); P.open = P.open === i ? null : i; renderAudit(); } });
  $('#auPrev').addEventListener('click', () => { P.page--; renderAudit(); }); $('#auNext').addEventListener('click', () => { P.page++; renderAudit(); });
  $('#auReset').addEventListener('click', () => { ['#auQ', '#auFrom', '#auTo'].forEach((s) => { $(s).value = ''; }); ['#auSrc', '#auSt', '#auWho', '#auAct'].forEach((s) => { $(s).value = ''; }); P.page = 0; renderAudit(); });
  $('#auCsv').addEventListener('click', () => { const q = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`; dl(`estherdaxes-audit-${stamp()}.csv`, 'text/csv', '\ufefftime_utc,source,actor,action,target,status,detail,evidence_url\n' + auFilter().map((x) => [x.ts, x.source, x.actor, x.action, x.target, x.status, x.detail, x.url].map(q).join(',')).join('\n')); });
  $('#auJson').addEventListener('click', () => dl(`estherdaxes-audit-${stamp()}.json`, 'application/json', JSON.stringify({ exportedAt: new Date().toISOString(), exportedBy: S.me?.user, filter: { q: $('#auQ').value, source: $('#auSrc').value, status: $('#auSt').value, actor: $('#auWho').value, action: $('#auAct').value, range: P.range, from: $('#auFrom').value, to: $('#auTo').value }, events: auFilter() }, null, 2)));
}

// ---------- scheduled tasks (dry-run) ----------
const OPL = { removeFromGroup: 'Remove from group', addToGroup: 'Add to group', setManager: 'Change manager', missingGroup: 'Group missing', report: 'Report', finding: 'Rule finding' };
async function renderSched() {
  if (!S.sched) { $('#scList').innerHTML = '<p class="muted">Loading…</p>'; try { S.sched = await api('admin/scheduled'); } catch { S.sched = null; } }
  if (!S.sched) { $('#scList').innerHTML = '<p class="muted">Scheduled tasks are visible to admins and approvers.</p>'; return; }
  const rep = S.sched.report || {}; const res = new Map((rep.tasks || []).map((t) => [t.id, t]));
  const ran = (rep.tasks || []).filter((t) => t.status === 'ran'); const would = ran.reduce((a, t) => a + (t.count || 0), 0);
  const next = new Date(); next.setUTCHours(1, 17, 0, 0); if (next < new Date()) next.setUTCDate(next.getUTCDate() + 1);
  $('#scKpi').innerHTML = [['Tasks', S.sched.tasks.length, 'all dry-run'], ['Would change', would, 'in the last run'], ['Last run', rep.generatedAt ? ago(rep.generatedAt) : 'never', rep.generatedAt ? new Date(rep.generatedAt).toLocaleString() : ''], ['Next run', next.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }), next.toLocaleDateString()]]
    .map(([l, v, s]) => `<div class="kpi"><span class="kl">${l}</span><b class="kv">${esc(String(v))}</b><span class="ks">${esc(s)}</span></div>`).join('');
  $('#scList').innerHTML = S.sched.tasks.map((t) => { const r = res.get(t.id) || {}; const n = r.count || 0; const st = r.status === 'ran' ? (n ? 'warn' : 'ok') : r.status === 'not-due' ? 'idle' : r.status ? 'bad' : 'idle';
    const label = r.status === 'ran' ? (n ? (t.kind === 'rules' || t.kind === 'empty-groups' ? `${n} finding${n > 1 ? 's' : ''}` : `would change ${n}`) : 'nothing to do') : r.status === 'not-due' ? 'not due today' : r.status || 'no run yet';
    return `<details class="sct ${st}" ${n ? 'open' : ''}><summary><span class="dot"></span><b>${esc(t.name)}</b><span class="when">${esc(t.when.replace('weekly:', 'weekly, ').replace('monthly:', 'monthly, day '))}</span><span class="pill mode">dry-run</span><span class="grow"></span><span class="res">${esc(label)}</span></summary>
      ${n ? `<table><thead><tr><th>Would do</th><th>Who</th><th>Detail</th></tr></thead><tbody>${r.ops.slice(0, 50).map((o) => `<tr><td><b>${esc(OPL[o.op] || o.op)}</b></td><td>${esc(o.upn ? nameOf(o.upn) : o.rule || '')}</td><td>${esc(o.group || (o.op === 'setManager' ? `${nameOf(o.from)} → ${o.to ? nameOf(o.to) : 'needs a person'}` : o.count ? `${o.count} (${o.severity})` : ''))}</td></tr>`).join('')}</tbody></table>${n > 50 ? `<p class="muted">and ${n - 50} more</p>` : ''}` : `<p class="muted">${r.error ? esc(r.error) : 'All clear in the last run.'}</p>`}</details>`; }).join('');
}

// ---------- dynamic group rules (preview only) ----------
function grEval(rules, users, groups) {
  const act = users.filter((u) => u.department && u.accountEnabled !== false);
  const reps = new Set(users.filter((u) => u.manager && u.accountEnabled !== false).map((u) => lc(u.manager)));
  const gm = new Map(groups.map((g) => [g.displayName, new Set((g.members || []).map(lc))]));
  return rules.map((r) => { const m = r.match || {}; const want = new Map();
    for (const u of act) { if (m.department && m.department !== '*' && !m.department.includes(u.department)) continue;
      if (m.hasReports && !reps.has(lc(u.userPrincipalName))) continue;
      if (m.titleContains && m.titleContains.length && !m.titleContains.some((t) => lc(u.jobTitle).includes(lc(t)))) continue;
      const g = r.group.replace('{department}', u.department); if (!want.has(g)) want.set(g, new Set()); want.get(g).add(lc(u.userPrincipalName)); }
    if (!r.group.includes('{') && !want.has(r.group)) want.set(r.group, new Set());
    return { ...r, groups: [...want].map(([g, set]) => { const cur = gm.get(g); return { group: g, exists: !!cur, members: set.size, add: [...set].filter((x) => !cur || !cur.has(x)), remove: cur && r.removeOthers ? [...cur].filter((x) => !set.has(x)) : [] }; }) }; });
}
function grDesc(m) { const p = []; if (m.department === '*') p.push('every department'); else if (m.department) p.push(m.department.join(', ')); if (m.titleContains?.length) p.push(`title has ${m.titleContains.join(' or ')}`); if (m.hasReports) p.push('has direct reports'); return p.join(' · ') || 'everyone'; }
async function renderGR() {
  if (!S.sched) { try { S.sched = await api('admin/scheduled'); } catch { S.sched = null; } }
  const rules = S.sched?.groupRules || []; const users = S.dir?.users || S.users || []; const groups = S.dir?.groups || S.groups || [];
  if (!rules.length || !users.length) { $('#grList').innerHTML = '<p class="muted">Loading…</p>'; return; }
  const ev = grEval(rules, users, groups); const all = ev.flatMap((r) => r.groups);
  const adds = all.reduce((a, g) => a + g.add.length, 0), rems = all.reduce((a, g) => a + g.remove.length, 0), neu = all.filter((g) => !g.exists).length;
  $('#grKpi').innerHTML = [['Rules', rules.length, 'all dry-run'], ['Groups governed', all.length, `${neu} would be created`], ['Would add', adds, 'members'], ['Would remove', rems, 'members']].map(([l, v, s]) => `<div class="kpi"><span class="kl">${l}</span><b class="kv">${v}</b><span class="ks">${s}</span></div>`).join('');
  $('#grList').innerHTML = ev.map((r) => { const a = r.groups.reduce((x, g) => x + g.add.length, 0), d = r.groups.reduce((x, g) => x + g.remove.length, 0); const st = a || d || r.groups.some((g) => !g.exists) ? 'warn' : 'ok';
    return `<details class="sct ${st}"><summary><span class="dot"></span><b>${esc(r.name)}</b><span class="when">${esc(grDesc(r.match))}</span><span class="pill mode">dry-run</span><span class="grow"></span><span class="res">${a || d ? `+${a} / -${d}` : 'in sync'}</span></summary>
      <table><thead><tr><th>Group</th><th>Members by rule</th><th>Would add</th><th>Would remove</th></tr></thead><tbody>${r.groups.slice(0, 20).map((g) => `<tr><td><b>${esc(g.group)}</b>${g.exists ? '' : ' <span class="pill mode">new</span>'}</td><td>${g.members}</td><td title="${esc(g.add.map(nameOf).join(', '))}">${g.add.length ? esc(g.add.slice(0, 4).map(nameOf).join(', ')) + (g.add.length > 4 ? ` +${g.add.length - 4}` : '') : '-'}</td><td>${g.remove.length ? esc(g.remove.slice(0, 4).map(nameOf).join(', ')) : '-'}</td></tr>`).join('')}</tbody></table></details>`; }).join('');
  if (!$('#gbDepts').dataset.ready) { const deps = [...new Set(users.map((u) => u.department).filter(Boolean))].sort(); $('#gbDepts').innerHTML = deps.map((d) => `<button class="chipf ${/Imaging|Laboratory/.test(d) ? 'on' : ''}" data-d="${esc(d)}">${esc(d)}</button>`).join(''); $('#gbDepts').dataset.ready = 1; }
  gbPreview();
}
function gbRule() { const d = [...document.querySelectorAll('#gbDepts .on')].map((b) => b.dataset.d); const t = $('#gbTitle').value.split(',').map((x) => x.trim()).filter(Boolean);
  const match = {}; if (d.length) match.department = d; if (t.length) match.titleContains = t; if ($('#gbMgr').checked) match.hasReports = true;
  return { id: lc($('#gbName').value).replace(/[^a-z0-9]+/g, '-'), name: $('#gbName').value, group: $('#gbGroup').value, match, removeOthers: true }; }
function gbPreview() { const users = S.dir?.users || S.users || []; const groups = S.dir?.groups || S.groups || []; if (!users.length) return;
  const r = grEval([gbRule()], users, groups)[0]; const g = r.groups[0] || { members: 0, add: [], exists: false };
  $('#gbPrev').innerHTML = `<div class="gbres"><b>${g.members}</b> people match · ${g.exists ? `+${g.add.length} / -${g.remove.length} vs today` : 'group would be created'}</div><div class="gbppl">${g.add.slice(0, 12).map((u) => `<span class="av">${esc(nameOf(u))}</span>`).join('')}${g.add.length > 12 ? `<span class="muted">+${g.add.length - 12} more</span>` : ''}</div>`; }
if ($('#grules')) {
  $('#gbDepts').addEventListener('click', (e) => { const b = e.target.closest('[data-d]'); if (b) { b.classList.toggle('on'); gbPreview(); } });
  ['#gbName', '#gbGroup', '#gbTitle', '#gbMgr'].forEach((s) => $(s).addEventListener('input', gbPreview));
  $('#gbCopy').addEventListener('click', async () => { const t = JSON.stringify(gbRule(), null, 2); try { await navigator.clipboard.writeText(t); $('#gbMsg').textContent = ' Copied. Add it to config/group-rules.json to include it in the nightly run.'; } catch { $('#gbMsg').textContent = ' ' + t; } });
}


// ---------- delegated administration (preview only) ----------
// Department admin = the most senior active person in the department (manager outside the department or none, most reports).
// Scope = everyone in the department. Direct reports in other departments stay with their own department admin.
function dgEval(users) {
  const act = users.filter((u) => u.accountEnabled !== false); const by = new Map(act.map((u) => [lc(u.userPrincipalName), u]));
  const kids = new Map(); for (const u of act) if (u.manager) { const m = lc(u.manager); if (!kids.has(m)) kids.set(m, []); kids.get(m).push(u); }
  const below = (upn, seen = new Set()) => { for (const c of kids.get(upn) || []) { const x = lc(c.userPrincipalName); if (!seen.has(x)) { seen.add(x); below(x, seen); } } return seen; };
  const deps = [...new Set(act.map((u) => u.department).filter(Boolean))].sort();
  return deps.map((d) => { const inD = act.filter((u) => u.department === d);
    const heads = inD.filter((u) => !u.manager || (by.get(lc(u.manager)) || {}).department !== d).sort((a, b) => (kids.get(lc(b.userPrincipalName)) || []).length - (kids.get(lc(a.userPrincipalName)) || []).length);
    const admin = heads[0] || null; const scope = new Set(inD.map((u) => lc(u.userPrincipalName)));
    // Reports who sit in another department stay with their own department admin; they are only counted here.
    const outside = inD.flatMap((u) => kids.get(lc(u.userPrincipalName)) || []).filter((c) => c.department !== d).length;
    return { department: d, admin, scope: [...scope], outside, heads: heads.length }; });
}
const T = (t) => (document.documentElement.lang === 'he' && window.HE_DICT && window.HE_DICT[t]) || t;
function renderDG() {
  const users = S.dir?.users || S.users || []; if (!users.length) { $('#dgList').innerHTML = '<p class="muted">Loading…</p>'; return; }
  const ev = dgEval(users); P.dg = ev; const noAdmin = ev.filter((r) => !r.admin).length; const multi = ev.filter((r) => r.heads > 1).length;
  $('#dgKpi').innerHTML = [['Departments', ev.length, 'one admin each'], ['Admins proposed', ev.length - noAdmin, noAdmin ? `${noAdmin} without a clear head` : 'all covered'], ['People in scope', ev.reduce((a, r) => a + r.scope.length, 0), 'across all departments'], ['Need a decision', multi, 'more than one possible head']].map(([l, v, s]) => `<div class="kpi"><span class="kl">${esc(l)}</span><b class="kv">${v}</b><span class="ks">${esc(s)}</span></div>`).join('');
  $('#dgList').innerHTML = ev.map((r) => `<details class="sct ${r.admin && r.heads === 1 ? 'ok' : 'warn'}"><summary><span class="dot"></span><b>${esc(r.department)}</b><span class="when">${r.admin ? esc(nameOf(r.admin.userPrincipalName)) : 'no clear head'}</span><span class="pill mode">preview</span><span class="grow"></span><span class="res">${r.scope.length} ${esc(T('people'))}</span></summary>
      <table><thead><tr><th>Can see and edit</th><th>Title</th><th>Department</th></tr></thead><tbody>${r.scope.slice(0, 30).map((x) => { const u = users.find((y) => lc(y.userPrincipalName) === x) || {}; return `<tr><td>${esc(nameOf(x))}</td><td>${esc(u.jobTitle || '')}</td><td>${esc(u.department || '')}</td></tr>`; }).join('')}</tbody></table></details>`).join('');
  const sel = $('#dgAs'); if (!sel.dataset.ready) { sel.innerHTML = ev.filter((r) => r.admin).map((r) => `<option value="${esc(r.department)}">${esc(nameOf(r.admin.userPrincipalName))} (${esc(r.department)})</option>`).join(''); sel.dataset.ready = 1; sel.addEventListener('change', dgScope); }
  dgScope();
}
function dgScope() { const r = (P.dg || []).find((x) => x.department === $('#dgAs').value); if (!r) { $('#dgScope').innerHTML = ''; return; }
  const total = (S.dir?.users || S.users || []).filter((u) => u.accountEnabled !== false).length;
  $('#dgScope').innerHTML = `<div class="gbres"><b>${r.scope.length}</b> / ${total} · ${esc(T('visible'))} · ${total - r.scope.length} ${esc(T('hidden'))}${r.outside ? ` · ${r.outside} ${esc(T('reports in other departments'))}` : ''}</div><div class="gbppl">${r.scope.slice(0, 16).map((x) => `<span class="av">${esc(nameOf(x))}</span>`).join('')}</div><p class="muted">Allowed: reset password, update phone and title, add to this department's groups. Not allowed: other departments, admin roles, deleting accounts.</p>`; }


// ---------- employee self-service (requests go through normal approval) ----------
function ssUser() { const q = lc($('#ssWho').value.trim()); const us = S.dir?.users || S.users || []; return us.find((u) => lc(u.userPrincipalName) === q || lc(u.displayName) === q) || null; }
function renderSS() {
  const us = (S.dir?.users || S.users || []).filter((u) => u.accountEnabled !== false); if (!us.length) { $('#ssMe').innerHTML = '<p class="muted">Loading…</p>'; return; }
  if (!$('#ssList').dataset.ready) { $('#ssList').innerHTML = us.map((u) => `<option value="${esc(u.userPrincipalName)}">${esc(u.displayName)}</option>`).join(''); $('#ssList').dataset.ready = 1; if (!$('#ssWho').value) $('#ssWho').value = us.find((u) => u.department === 'Nursing')?.userPrincipalName || us[0].userPrincipalName; }
  const u = ssUser(); if (!u) { $('#ssMe').innerHTML = `<p class="muted">${esc(T('Choose a person'))}</p>`; return; }
  const mine = groupsOf(u.userPrincipalName); const all = (S.dir?.groups || S.groups || []).filter((g) => !mine.some((m) => m.displayName === g.displayName));
  $('#ssMe').innerHTML = `<h3>${esc(u.displayName)}</h3><table><tbody>${[['Job title', u.jobTitle], ['Department', u.department], ['Mobile phone', u.mobilePhone], ['Manager', nameOf(u.manager)], ['Sign-in name', u.userPrincipalName]].map(([k, v]) => `<tr><th>${esc(T(k))}</th><td>${esc(v || '-')}</td></tr>`).join('')}</tbody></table>
    <h3>${esc(T('Groups'))} (${mine.length})</h3><div class="gbppl">${mine.map((g) => `<span class="av">${esc(g.displayName)}</span>`).join('') || '-'}</div>
    <p class="muted">${esc(T('Department, title and manager are changed by HR or an admin, not by the employee.'))}</p>`;
  $('#ssPhone').value = u.mobilePhone || '';
  $('#ssGroup').innerHTML = all.map((g) => `<option>${esc(g.displayName)}</option>`).join(''); ssPrev();
}
function ssPrev() { const u = ssUser(); const g = $('#ssGroup').value; $('#ssPrev').textContent = u && g ? `${T('Request')}: ${nameOf(u.userPrincipalName)} → ${g}` : ''; }
if ($('#self')) {
  $('#ssWho').addEventListener('change', renderSS); $('#ssGroup').addEventListener('change', ssPrev);
  $('#ssSend').addEventListener('click', () => { const u = ssUser(); const g = $('#ssGroup').value; const why = $('#ssWhy').value.trim(); if (!u || !g) return;
    if (why.length < 3) { banner(T('Write a short reason (at least 3 characters).')); return; }
    submit({ action: 'addToGroup', userPrincipalName: u.userPrincipalName, group: g, reason: `Self-service: ${why}` }); });
  $('#ssPhoneSend').addEventListener('click', () => { const u = ssUser(); const ph = $('#ssPhone').value.trim(); if (!u) return;
    if (!/^\+?[0-9][0-9 ()-]{6,19}$/.test(ph)) { banner(T('Phone must be digits, spaces, dashes or a leading +.')); return; }
    if (ph === (u.mobilePhone || '')) { banner(T('That is already the phone on file.')); return; }
    submit({ action: 'updateUser', userPrincipalName: u.userPrincipalName, mobilePhone: ph, reason: 'Self-service: phone update' }); });
}

// ---------- wiring ----------
const baseShow = show;
show = function (view) { baseShow(view); if (view === 'dashboard') renderDash(); if (view === 'audit') renderAudit(); if (view === 'scheduled') renderSched(); if (view === 'grules') renderGR(); if (view === 'deleg') renderDG(); if (view === 'self') renderSS(); if (view === 'lifecycle' && !P.lc) lcTab('joiner'); };
document.addEventListener('click', (e) => { const b = e.target.closest('[data-lc]'); if (b) lcTab(b.dataset.lc); });

// ---------- Ops / GitHub (live workflow runs) ----------
const WF_HE = {
  'esther-scom-phase4': 'SCOM שלב 4: אתחול אסתר, סיום SSRS, ניקוי דיסק, התקנת IIS וחילוץ קבצי ההתקנה של SCOM',
  'esther-scom-phase5': 'SCOM שלב 5: התקנת SCOM 2025 על אסתר וצילום של Operations Console',
  'esther-scom-phase3': 'SCOM שלב 3: התקנת SQL Server 2022 עם Full-Text ו-SSRS',
  'esther-scom-phase2': 'SCOM שלב 2: יצירת אסתר וצירוף לדומיין esther.lab',
  'esther-scom-phase1-dc': 'SCOM שלב 1: הקמת ה-DC והדומיין esther.lab',
  'esther-media-stage': 'העלאת קבצי התקנה ל-Storage באותו אזור, כדי שאסתר (בלי אינטרנט) תוכל למשוך אותם',
  'esther-lab-power': 'הדלקה/כיבוי של שרתי המעבדה. כל לילה ב-23:00 מכבה, אלא אם התקנה רצה',
  'esther-swa-deploy': 'בנייה ופריסה של פורטל Estherdaxes ל-Azure Static Web Apps',
  'esther-apply': 'החלת שינויים מאושרים ב-Entra דרך Graph',
  'esther-scheduled': 'משימות מתוזמנות לילה (dry-run): מציגות מה היו משנות',
  'esther-costs-read': 'קריאת עלויות Azure לדשבורד',
  'jfrog-oss-record': 'Artifactory OSS זמני על ה-Runner + הקלטת מסך אוטומטית לשיעורי JFrog',
};
const STREAMS = [
  ['SCOM lab', /^esther-(scom|media|dc|lab-power|sql)/, '#38bdf8'], ['Portal deploy', /swa-/, '#60a5fa'],
  ['Entra changes', /esther-(apply|scheduled|request|costs|plan|inventory|password|graph|portal-role|azure-read)/, '#3b82f6'], ['JFrog lessons', /jfrog/, '#34d399'], ['Other', /./, '#94a3b8']];
const streamOf = (n) => STREAMS.find(([, re]) => re.test(n || '')) || STREAMS[STREAMS.length - 1];
const runState = (r) => r.status !== 'completed' ? (r.status === 'in_progress' ? 'running' : 'queued') : (r.conclusion || 'unknown');
const dur = (s) => { s = Math.max(0, Math.round(s)); const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60; return h ? `${h}h ${m}m` : m ? `${m}m ${String(x).padStart(2, '0')}s` : `${x}s`; };
const runDur = (r) => { const a = Date.parse(r.startedAt || r.createdAt); const b = r.status === 'completed' ? Date.parse(r.updatedAt) : Date.now(); return (b - a) / 1000; };
const ST_ICON = { running: '●', queued: '◌', success: '✓', failure: '✕', cancelled: '⊘', skipped: '–', unknown: '?' };
let opsTimer = null, opsTick = null;
async function renderOps() {
  try { S.ops = await api('admin/ops'); } catch { if (!S.ops) { $('#opsRuns').innerHTML = '<p class="muted">Ops is visible to admins and approvers.</p>'; return; } }
  drawOps(); clearInterval(opsTimer); clearInterval(opsTick);
  opsTimer = setInterval(async () => { if ($('#ops').hidden) { clearInterval(opsTimer); clearInterval(opsTick); return; } try { S.ops = await api('admin/ops'); drawOps(); } catch {} }, 15000);
  opsTick = setInterval(() => document.querySelectorAll('[data-live-start]').forEach((e) => { e.textContent = dur((Date.now() - Number(e.dataset.liveStart)) / 1000); }), 1000);
}
function nowDetail(r) {
  const L = r.live, J = r.steps; const d = WF_HE[r.name];
  let step = '', pct = 0, cmd = '', ex = '';
  if (L) { step = `שלב ${L.step} מתוך ${L.total}: ${L.label}`; pct = Math.round((L.step - 1) / L.total * 100 + 100 / L.total / 2); cmd = L.command; ex = L.explain; }
  else if (J && J.total) { step = `שלב ${J.done + 1} מתוך ${J.total}: ${J.current || 'מתחיל'}`; pct = Math.round(J.done / J.total * 100); }
  if (!d && !step) return '';
  return `<div class="nowdet" dir="rtl">${d ? `<p class="wfhe">${esc(d)}</p>` : ''}${step ? `<div class="opstep"><b>${esc(step)}</b><span class="muted small">${pct}%</span></div><div class="opbar"><i style="width:${pct}%"></i></div>` : ''}
    ${cmd ? `<div class="cmdl"><span class="muted small">הפקודה שרצה עכשיו:</span><code dir="ltr">${esc(cmd)}</code>${ex ? `<span class="cmdex">${esc(ex)}</span>` : ''}</div>` : ''}${L && L.at ? `<span class="muted small">עודכן ${ago(L.at)}</span>` : ''}</div>`;
}
function drawOps() {
  const d = S.ops; const runs = d.runs || []; const day = Date.now() - 864e5;
  $('#opsLive').className = 'pill ' + (d.live ? 'livepill' : 'mode'); $('#opsLive').textContent = d.live ? 'LIVE' : 'snapshot';
  $('#opsAt').textContent = d.fetchedAt ? `updated ${new Date(d.fetchedAt).toLocaleTimeString()}` : '';
  const st = runs.map(runState); const d24 = runs.filter((r) => Date.parse(r.createdAt) > day);
  const ok = d24.filter((r) => runState(r) === 'success').length, bad = d24.filter((r) => runState(r) === 'failure').length;
  $('#opsKpi').innerHTML = [['Running now', st.filter((s) => s === 'running').length, 'in progress'], ['Queued', st.filter((s) => s === 'queued').length, 'waiting for a runner'],
    ['Succeeded', ok, 'last 24 hours'], ['Failed', bad, 'last 24 hours'], ['Success rate', d24.length ? Math.round(ok / Math.max(1, ok + bad) * 100) + '%' : '–', `${d24.length} runs in 24h`]]
    .map(([l, v, s], i) => `<div class="kpi ${i === 3 && v ? 'kbad' : i === 0 && v ? 'klive' : ''}"><span class="kl">${l}</span><b class="kv">${esc(String(v))}</b><span class="ks">${esc(s)}</span></div>`).join('');
  const hb = d.heartbeat; const hbEl = $('#opsHb');
  if (hbEl) hbEl.innerHTML = !hb ? '<div class="card calm">Esther heartbeat: no signal (server is off or the heartbeat is not installed).</div>'
    : `<div class="card hb ${hb.ageSec > 180 ? 'stale' : 'fresh'}"><h3><span class="pulse"></span>Esther heartbeat <span class="muted small">${esc(hb.host || '')} · ${hb.ageSec > 180 ? 'last seen ' : ''}${dur(hb.ageSec)} ago</span></h3>
      <div class="hbgrid"><span>CPU <b>${esc(String(hb.cpuPct))}%</b></span><span>Free disk <b>${esc(String(hb.freeGB))} GB</b></span><span>Free RAM <b>${esc(String(hb.memFreeMB))} MB</b></span>
      <span>Setup <b>${(hb.setupProcs || []).length ? esc(hb.setupProcs.map((p) => p.Name).join(', ')) : 'not running'}</b></span></div>
      <div class="hbsvc">${(hb.services || []).map((o) => Object.entries(o)[0]).map(([n, v]) => `<span class="pill ${v === 'Running' ? 'success' : 'failure'}">${esc(n)} ${esc(v)}</span>`).join(' ')}</div>
      ${hb.log ? `<div class="muted small">${esc(hb.log)}</div><pre class="hblog">${esc((hb.logTail || []).join('\n'))}</pre>` : ''}</div>`;
  const live = runs.filter((r) => r.status !== 'completed');
  $('#opsNow').innerHTML = live.length ? `<h3>Running now</h3>${live.map((r) => { const [sn, , c] = streamOf(r.name); const s = runState(r);
    return `<a class="nowcard ${s}" href="${esc(r.url)}" target="_blank" rel="noopener" style="--sc:${c}"><span class="pulse"></span><div><b>${esc(r.name)}</b><span class="muted">${esc(sn)} · ${esc(r.event || '')}${r.sha ? ' · ' + esc(r.sha) : ''}</span></div><span class="grow"></span><span class="el" data-live-start="${Date.parse(r.startedAt || r.createdAt)}">${dur(runDur(r))}</span><span class="pill ${s}">${s}</span></a>${nowDetail(r)}`; }).join('')}`
    : '<div class="card calm">Nothing running right now. All quiet.</div>';
  $('#opsStreams').innerHTML = STREAMS.map(([n, , c]) => { const rs = runs.filter((r) => streamOf(r.name)[0] === n); if (!rs.length) return '';
    const last = rs[0]; const s = runState(last); const f = rs.filter((r) => runState(r) === 'failure').length;
    return `<div class="stream" style="--sc:${c}"><div class="sh"><span class="sdot"></span><b>${esc(n)}</b></div><div class="sl"><span class="pill ${s}">${ST_ICON[s] || ''} ${s}</span> <span class="muted">${esc(last.name)}</span></div><div class="ss muted">${rs.length} runs · ${f} failed · last ${ago(last.startedAt || last.createdAt)}</div>
      <div class="spark">${rs.slice(0, 20).reverse().map((r) => `<i class="${runState(r)}" title="${esc(r.name)} · ${runState(r)}"></i>`).join('')}</div></div>`; }).join('');
  const fSel = $('#opsF'); if (fSel.options.length === 1) { STREAMS.forEach(([n]) => fSel.add(new Option(n, n))); fSel.onchange = drawOps; $('#opsS').onchange = drawOps; }
  const fv = fSel.value, sv = $('#opsS').value;
  const rows = runs.filter((r) => (!fv || streamOf(r.name)[0] === fv) && (!sv || runState(r) === sv)).slice(0, 40);
  $('#opsRuns').innerHTML = `<table class="opst"><thead><tr><th></th><th>Workflow</th><th>Stream</th><th>Trigger</th><th>Started</th><th>Duration</th><th>Commit</th></tr></thead><tbody>${rows.map((r) => { const s = runState(r); const [sn, , c] = streamOf(r.name);
    return `<tr class="${s}" onclick="window.open('${esc(r.url)}','_blank')"><td><span class="stic ${s}">${ST_ICON[s] || '?'}</span></td><td><b>${esc(r.name)}</b><div class="muted small">${esc((r.title || '').slice(0, 70))}</div></td><td><span class="tag" style="--sc:${c}">${esc(sn)}</span></td><td>${esc(r.event || '')}</td><td>${ago(r.startedAt || r.createdAt)}</td><td>${r.status === 'completed' ? dur(runDur(r)) : `<span data-live-start="${Date.parse(r.startedAt || r.createdAt)}">${dur(runDur(r))}</span>`}</td><td><code>${esc(r.sha || '')}</code></td></tr>`; }).join('')}</tbody></table>`;
  $('#opsCommits').innerHTML = (d.commits || []).map((c) => `<a class="cmt" href="${esc(c.url)}" target="_blank" rel="noopener"><code>${esc(c.sha)}</code><span>${esc(c.msg)}</span><span class="muted small">${ago(c.at)}</span></a>`).join('') || '<p class="muted">No commits.</p>';
}
{ const prevShow = show; show = function (view) { prevShow(view); if (view === 'ops') renderOps(); }; }
