// Folds change-request files (requests/*.json) into desired-state/state.json in file-name order.
// Prints the set of UPNs the requests touch (used by apply's guard). Unknown actions fail loudly.
import fs from 'node:fs'; import path from 'node:path';
const file = 'desired-state/state.json'; const s = JSON.parse(fs.readFileSync(file, 'utf8'));
const lc = (x) => (x || '').toLowerCase();
const dir = 'requests'; const files = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith('.json')).sort() : [];
const touched = new Set();
for (const f of files) {
  const r = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
  if (r.action === 'resetPassword') continue; // handled by esther-password, no desired-state change
  const upn = r.userPrincipalName; touched.add(lc(upn));
  let u = s.users.find((x) => lc(x.userPrincipalName) === lc(upn));
  const g = r.group && s.groups.find((x) => lc(x.displayName) === lc(r.group));
  const need = (c, m) => { if (!c) throw new Error(`${f}: ${m}`); };
  switch (r.action) {
    case 'createUser':
      if (u) throw new Error(`${f}: user already exists`);
      u = { userPrincipalName: upn, displayName: r.displayName, accountEnabled: true }; s.users.push(u);
      for (const k of ['department', 'jobTitle']) if (r[k]) u[k] = r[k];
      if (r.manager) u.manager = r.manager;
      if (r.department) { const dg = s.groups.find((x) => x.displayName === `Esther Hospital - ${r.department}`); if (dg && !dg.members.some((m) => lc(m) === lc(upn))) dg.members.push(upn); }
      break;
    case 'updateUser': need(u, 'unknown user'); for (const k of ['displayName', 'department', 'jobTitle', 'mobilePhone']) if (r[k]) u[k] = r[k]; break;
    case 'upsertUser': if (!u) { u = { userPrincipalName: upn, displayName: r.displayName }; s.users.push(u); } for (const k of ['displayName', 'department', 'jobTitle']) if (r[k]) u[k] = r[k]; if (r.manager) u.manager = r.manager; break;
    case 'disableUser': need(u, 'unknown user'); u.accountEnabled = false; break;
    case 'enableUser': need(u, 'unknown user'); u.accountEnabled = true; break;
    case 'setManager': need(u, 'unknown user'); u.manager = r.manager || null; if (r.manager) touched.add(lc(r.manager)); break;
    case 'addToGroup': need(g, 'unknown group'); if (!g.members.some((m) => lc(m) === lc(upn))) g.members.push(upn); break;
    case 'removeFromGroup': need(g, 'unknown group'); g.members = g.members.filter((m) => lc(m) !== lc(upn)); g.exclusive = true; break;
    default: throw new Error(`${f}: action ${r.action} not supported by apply`);
  }
}
fs.writeFileSync(file, JSON.stringify(s, null, 2) + '\n');
fs.writeFileSync('request-scope.json', JSON.stringify({ files, upns: [...touched] }, null, 2));
console.log(`merged ${files.length} request(s)`);
