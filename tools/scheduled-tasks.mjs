// Runs config/schedules.json tasks against a directory snapshot. REPORT ONLY: builds a list of the changes each task
// would make; it never calls Graph and never writes. Any task not in dry-run mode is refused.
// Usage: node tools/scheduled-tasks.mjs [--snapshot current.json] [--plan plan.json] [--rules rules-report.json] [--all]
import fs from 'node:fs';
import { evaluate } from './group-rules.mjs';
const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const rd = (f, d) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return d; } };
const snap = rd(arg('--snapshot', 'current.json'), { users: [], groups: [] });
const plan = rd(arg('--plan', 'plan.json'), null); const rules = rd(arg('--rules', 'rules-report.json'), null);
const tasks = rd('config/schedules.json', { tasks: [] }).tasks;
const lc = (x) => (x || '').toLowerCase(); const all = process.argv.includes('--all');
const users = snap.users.filter((u) => u.department); const by = new Map(snap.users.map((u) => [lc(u.userPrincipalName), u]));
const dept = snap.groups.filter((g) => g.displayName.startsWith('Esther Hospital - '));
const now = new Date(); const dow = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][now.getUTCDay()];
const due = (w) => all || w === 'daily' || (w.startsWith('weekly:') && w.slice(7) === dow) || (w.startsWith('monthly:') && +w.slice(8) === now.getUTCDate());
const kinds = {
  'disabled-cleanup': () => users.filter((u) => u.accountEnabled === false).flatMap((u) => snap.groups.filter((g) => g.members.some((m) => lc(m) === lc(u.userPrincipalName))).map((g) => ({ op: 'removeFromGroup', upn: u.userPrincipalName, group: g.displayName }))),
  'orphaned-reports': () => users.filter((u) => u.accountEnabled !== false && u.manager).flatMap((u) => { const m = by.get(lc(u.manager)); if (m && m.accountEnabled !== false) return [];
    let up = m?.manager ? by.get(lc(m.manager)) : null; while (up && up.accountEnabled === false) up = up.manager ? by.get(lc(up.manager)) : null;
    return [{ op: 'setManager', upn: u.userPrincipalName, from: u.manager, to: up?.userPrincipalName || null, note: up ? "manager's manager" : 'no enabled manager above, needs a person' }]; }),
  'dept-group-sync': () => users.filter((u) => u.accountEnabled !== false).flatMap((u) => { const ops = []; const want = `Esther Hospital - ${u.department}`;
    for (const g of dept) { const inG = g.members.some((m) => lc(m) === lc(u.userPrincipalName));
      if (g.displayName === want && !inG) ops.push({ op: 'addToGroup', upn: u.userPrincipalName, group: g.displayName });
      if (g.displayName !== want && inG) ops.push({ op: 'removeFromGroup', upn: u.userPrincipalName, group: g.displayName }); }
    if (!dept.some((g) => g.displayName === want)) ops.push({ op: 'missingGroup', upn: u.userPrincipalName, group: want });
    return ops; }),
  drift: () => (plan?.ops || []).map((o) => ({ op: o.op, upn: o.upn || '', group: o.group || '' })),
  'empty-groups': () => snap.groups.filter((g) => !g.members.length).map((g) => ({ op: 'report', group: g.displayName })),
  'group-rules': () => evaluate(rd('config/group-rules.json', { rules: [] }).rules, snap).flatMap((r) => r.groups.flatMap((g) => [
    ...(g.exists ? [] : [{ op: 'createGroup', group: g.group, rule: r.name }]),
    ...g.add.map((u) => ({ op: 'addToGroup', upn: u, group: g.group, rule: r.name })), ...g.remove.map((u) => ({ op: 'removeFromGroup', upn: u, group: g.group, rule: r.name }))])),
  rules: () => (rules?.results || []).filter((r) => r.count).map((r) => ({ op: 'finding', rule: r.text, severity: r.severity, count: r.count })),
};
const out = [];
for (const t of tasks) {
  if (t.mode !== 'dry-run') { out.push({ ...t, status: 'refused', error: 'only dry-run is enabled', ops: [] }); continue; }
  if (!due(t.when)) { out.push({ ...t, status: 'not-due', ops: [] }); continue; }
  const f = kinds[t.kind]; if (!f) { out.push({ ...t, status: 'error', error: `unknown kind ${t.kind}`, ops: [] }); continue; }
  try { const ops = f(); out.push({ ...t, status: 'ran', count: ops.length, ops: ops.slice(0, 200) }); } catch (e) { out.push({ ...t, status: 'error', error: String(e.message || e), ops: [] }); }
}
const report = { generatedAt: now.toISOString(), snapshotAt: snap.generatedAt || null, mode: 'dry-run', tasks: out };
fs.writeFileSync(arg('--out', 'scheduled-report.json'), JSON.stringify(report, null, 2) + '\n');
const md = ['## Scheduled tasks (dry-run, nothing written)', '', '| Task | When | Result |', '|---|---|---|', ...out.map((t) => `| ${t.name} | ${t.when} | ${t.status === 'ran' ? (t.count ? `would change **${t.count}**` : 'nothing to do') : t.status} |`)].join('\n');
if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, md + '\n');
console.log(out.map((t) => `${t.status.padEnd(8)} ${t.id}: ${t.count ?? '-'}`).join('\n'));
