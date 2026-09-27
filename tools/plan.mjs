// Desired-state planner. Read-only: compares desired-state/ with current Entra (Graph or fixture) and writes plan.json.
// Never deletes users. Disabling is explicit (accountEnabled:false). Group removals only for exclusive groups.
// Usage: node tools/plan.mjs --desired desired-state/state.json [--fixture tests/fixtures/current.json] [--out plan.json]
import fs from 'node:fs';
const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, all) => (v.startsWith('--') ? [...a, [v.slice(2), all[i + 1]]] : a), []));
const FIELDS = ['displayName', 'department', 'jobTitle', 'accountEnabled', 'usageLocation', 'mobilePhone'];
const lc = (s) => (s || '').toLowerCase();

export async function graphGetAll(token, path) {
  let url = 'https://graph.microsoft.com/v1.0' + path; const out = [];
  while (url) {
    const r = await fetch(url, { headers: { authorization: `Bearer ${token}` } });
    if (!r.ok) throw new Error(`GET ${path} -> ${r.status}`);
    const j = await r.json(); out.push(...(j.value || [])); url = j['@odata.nextLink'];
  }
  return out;
}
export async function readCurrent(token, suffix) {
  const users = (await graphGetAll(token, '/users?$select=id,userPrincipalName,displayName,department,jobTitle,accountEnabled,usageLocation,mobilePhone&$expand=manager($select=userPrincipalName)&$top=999'))
    .filter((u) => lc(u.userPrincipalName).endsWith(lc(suffix)))
    .map((u) => ({ ...u, manager: u.manager ? u.manager.userPrincipalName : null }));
  const groups = [];
  for (const g of await graphGetAll(token, "/groups?$select=id,displayName&$filter=startswith(displayName,'Esther Hospital')&$top=999")) {
    const m = await graphGetAll(token, `/groups/${g.id}/members/microsoft.graph.user?$select=userPrincipalName&$top=999`);
    groups.push({ id: g.id, displayName: g.displayName, members: m.map((x) => x.userPrincipalName) });
  }
  return { users, groups };
}
export function plan(desired, current) {
  const errors = []; const ops = [];
  // Identity: desired entries may carry the Entra object id, so a UPN or group rename is an update, never a create.
  const byId = new Map(current.users.map((u) => [u.id, u]));
  const cu = new Map(current.users.map((u) => [lc(u.userPrincipalName), u]));
  const du = new Map(desired.users.map((u) => [lc(u.userPrincipalName), u]));
  const match = (u) => (u.id ? byId.get(u.id) : cu.get(lc(u.userPrincipalName)));
  // Translate current UPNs to their desired UPN (via id) so managers/members compare correctly across renames.
  const curToDesired = new Map();
  for (const u of desired.users) { const c = match(u); if (c) curToDesired.set(lc(c.userPrincipalName), lc(u.userPrincipalName)); }
  const tr = (upn) => (upn ? curToDesired.get(lc(upn)) || lc(upn) : null);
  const seenIds = new Set();
  for (const u of desired.users) {
    if (!lc(u.userPrincipalName).endsWith(lc(desired.upnSuffix))) errors.push(`${u.userPrincipalName}: outside ${desired.upnSuffix}`);
    if (u.manager && !du.has(lc(u.manager)) && !cu.has(lc(u.manager))) errors.push(`${u.userPrincipalName}: manager ${u.manager} unknown`);
    if (u.manager && lc(u.manager) === lc(u.userPrincipalName)) errors.push(`${u.userPrincipalName}: self-manager`);
    if (u.id && seenIds.has(u.id)) errors.push(`${u.userPrincipalName}: duplicate id ${u.id}`); if (u.id) seenIds.add(u.id);
    const c = match(u);
    if (u.id && !c) { errors.push(`${u.userPrincipalName}: id ${u.id} not found in Entra`); continue; }
    if (!c) { ops.push({ op: 'createUser', upn: u.userPrincipalName, set: Object.fromEntries(FIELDS.filter((f) => u[f] !== undefined).map((f) => [f, u[f]])) }); }
    else {
      if (lc(c.userPrincipalName) !== lc(u.userPrincipalName)) {
        const clash = cu.get(lc(u.userPrincipalName)); if (clash && clash.id !== c.id) errors.push(`${u.userPrincipalName}: UPN already used by ${clash.id}`);
        ops.push({ op: 'renameUser', id: c.id, upn: u.userPrincipalName, before: c.userPrincipalName });
      }
      const set = {};
      for (const f of FIELDS) if (u[f] !== undefined && (c[f] ?? null) !== u[f]) set[f] = u[f];
      if (Object.keys(set).length) ops.push({ op: 'updateUser', upn: u.userPrincipalName, id: c.id, set, before: Object.fromEntries(Object.keys(set).map((k) => [k, c[k] ?? null])) });
    }
    if (u.manager !== undefined && (tr(c?.manager) || '') !== lc(u.manager)) ops.push({ op: u.manager ? 'setManager' : 'removeManager', upn: u.userPrincipalName, manager: u.manager, before: c?.manager ?? null });
  }
  const gById = new Map(current.groups.map((g) => [g.id, g]));
  const cg = new Map(current.groups.map((g) => [lc(g.displayName), g]));
  for (const g of desired.groups) {
    const c = g.id ? gById.get(g.id) : cg.get(lc(g.displayName));
    if (!c) { errors.push(`group ${g.displayName} does not exist (portal does not create groups in v0.1)`); continue; }
    if (c.displayName !== g.displayName) {
      const clash = cg.get(lc(g.displayName)); if (clash && clash.id !== c.id) errors.push(`group ${g.displayName}: name already used by ${clash.id}`);
      ops.push({ op: 'renameGroup', groupId: c.id, group: g.displayName, before: c.displayName });
    }
    const have = new Set(c.members.map(tr)); const want = new Set(g.members.map(lc));
    for (const m of g.members) { if (!du.has(lc(m)) && !cu.has(lc(m))) errors.push(`group ${g.displayName}: member ${m} unknown`); if (!have.has(lc(m))) ops.push({ op: 'addMember', group: g.displayName, groupId: c.id, upn: m }); }
    if (g.exclusive) for (const m of c.members) if (!want.has(tr(m))) ops.push({ op: 'removeMember', group: g.displayName, groupId: c.id, upn: tr(m) });
  }
  // Order: renames first so later ops can address users by their new UPN; managers after profile updates.
  const rank = { renameGroup: 0, renameUser: 1, createUser: 2, updateUser: 3, setManager: 4, removeManager: 4, removeMember: 5, addMember: 6 };
  ops.sort((a, b) => rank[a.op] - rank[b.op]);
  const matched = new Set(desired.users.map((u) => match(u)?.id).filter(Boolean));
  const unmanaged = current.users.filter((u) => !matched.has(u.id) && !du.has(lc(u.userPrincipalName))).map((u) => u.userPrincipalName);
  const summary = ops.reduce((a, o) => ((a[o.op] = (a[o.op] || 0) + 1), a), {});
  return { generatedAt: new Date().toISOString(), errors, summary, opCount: ops.length, ops, unmanagedUsers: unmanaged };
}
if (import.meta.url === `file://${process.argv[1]}`) {
  const desired = JSON.parse(fs.readFileSync(args.desired || 'desired-state/state.json', 'utf8'));
  const current = args.fixture ? JSON.parse(fs.readFileSync(args.fixture, 'utf8')) : await readCurrent(process.env.GRAPH_TOKEN, desired.upnSuffix);
  const p = plan(desired, current);
  fs.writeFileSync(args.out || 'plan.json', JSON.stringify(p, null, 2));
  console.log(JSON.stringify({ errors: p.errors, summary: p.summary, opCount: p.opCount, unmanagedUsers: p.unmanagedUsers.length }, null, 2));
  process.exit(p.errors.length ? 2 : 0);
}
