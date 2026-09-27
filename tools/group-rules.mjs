// Evaluates config/group-rules.json against a directory snapshot. Pure function, no Graph calls. Shared by scheduled-tasks.
const lc = (x) => (x || '').toLowerCase();
export function evaluate(rules, snap) {
  const users = snap.users.filter((u) => u.department && u.accountEnabled !== false);
  const reports = new Set(snap.users.filter((u) => u.manager && u.accountEnabled !== false).map((u) => lc(u.manager)));
  const groups = new Map(snap.groups.map((g) => [g.displayName, new Set(g.members.map(lc))]));
  const out = [];
  for (const r of rules) {
    const m = r.match || {}; const want = new Map();
    for (const u of users) {
      if (m.department && m.department !== '*' && !m.department.includes(u.department)) continue;
      if (m.hasReports && !reports.has(lc(u.userPrincipalName))) continue;
      if (m.titleContains && !m.titleContains.some((t) => lc(u.jobTitle).includes(lc(t)))) continue;
      const g = r.group.replace('{department}', u.department);
      if (!want.has(g)) want.set(g, new Set()); want.get(g).add(lc(u.userPrincipalName));
    }
    if (!r.group.includes('{') && !want.has(r.group)) want.set(r.group, new Set());
    const res = [];
    for (const [g, set] of want) {
      const cur = groups.get(g); const add = [...set].filter((x) => !cur || !cur.has(x));
      const remove = cur && r.removeOthers ? [...cur].filter((x) => !set.has(x)) : [];
      res.push({ group: g, exists: !!cur, members: set.size, add, remove });
    }
    out.push({ id: r.id, name: r.name, groups: res });
  }
  return out;
}
