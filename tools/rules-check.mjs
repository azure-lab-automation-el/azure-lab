// Checks config/rules.json against a directory snapshot (current.json from export-current, or inventory.json).
// Usage: node tools/rules-check.mjs [--snapshot current.json] [--plan plan.json]. Writes rules-report.json; exit 0 always (report, not gate).
import fs from 'node:fs';
const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const snap = JSON.parse(fs.readFileSync(arg('--snapshot', 'current.json'), 'utf8'));
const rules = JSON.parse(fs.readFileSync('config/rules.json', 'utf8')).rules;
const tpl = JSON.parse(fs.readFileSync('config/templates.json', 'utf8')).departments || {};
const planFile = arg('--plan'); const plan = planFile && fs.existsSync(planFile) ? JSON.parse(fs.readFileSync(planFile, 'utf8')) : null;
const lc = (x) => (x || '').toLowerCase();
const users = snap.users.filter((u) => u.department); const by = new Map(users.map((u) => [lc(u.userPrincipalName), u]));
const deptGroups = snap.groups.filter((g) => g.displayName.startsWith('Esther Hospital - '));
const groupsOf = (upn) => snap.groups.filter((g) => g.members.some((m) => lc(m) === lc(upn)));
const out = [];
for (const r of rules) {
  const hits = [];
  if (r.id === 'manager-required') for (const u of users) if (!u.manager && !(r.exempt || []).map(lc).includes(lc(u.userPrincipalName))) hits.push(u.userPrincipalName);
  if (r.id === 'manager-exists') for (const u of users) if (u.manager) { const m = by.get(lc(u.manager)); if (!m || m.accountEnabled === false) hits.push(`${u.userPrincipalName} -> ${u.manager}`); }
  if (r.id === 'department-group') for (const u of users) { const g = deptGroups.find((x) => x.displayName === `Esther Hospital - ${u.department}`); if (!g || !g.members.some((m) => lc(m) === lc(u.userPrincipalName))) hits.push(`${u.userPrincipalName} (${u.department})`); }
  if (r.id === 'single-department-group') for (const u of users) { const n = deptGroups.filter((g) => g.members.some((m) => lc(m) === lc(u.userPrincipalName))); if (n.length > 1) hits.push(`${u.userPrincipalName}: ${n.map((g) => g.displayName.slice(18)).join(', ')}`); }
  if (r.id === 'disabled-no-groups') for (const u of users) if (u.accountEnabled === false && groupsOf(u.userPrincipalName).length) hits.push(u.userPrincipalName);
  if (r.id === 'title-in-template') for (const u of users) { const t = tpl[u.department]?.titles; if (t && u.jobTitle && !t.includes(u.jobTitle)) hits.push(`${u.userPrincipalName}: ${u.jobTitle}`); }
  if (r.id === 'no-drift') { if (!plan) continue; if (plan.opCount) hits.push(...plan.ops.slice(0, 50).map((o) => `${o.op} ${o.upn || o.group || ''}`)); }
  out.push({ id: r.id, severity: r.severity, text: r.text, count: hits.length, hits });
}
const report = { generatedAt: new Date().toISOString(), snapshotAt: snap.generatedAt, users: users.length, results: out };
fs.writeFileSync('rules-report.json', JSON.stringify(report, null, 2) + '\n');
const md = [`## Esther rules check (${users.length} users)`, '', '| Rule | Severity | Findings |', '|---|---|---|', ...out.map((r) => `| ${r.text} | ${r.severity} | ${r.count ? `**${r.count}**` : 'OK'} |`), '', ...out.filter((r) => r.count).map((r) => `<details><summary>${r.text} (${r.count})</summary>\n\n${r.hits.slice(0, 100).map((h) => '- ' + h).join('\n')}\n</details>`)].join('\n');
if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, md + '\n');
console.log(out.map((r) => `${r.count ? 'FIND' : 'ok  '} ${r.id}: ${r.count}`).join('\n'));
