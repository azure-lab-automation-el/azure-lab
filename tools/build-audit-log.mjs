// Builds api/audit-log.json for the Admin console: workflow runs, change requests and commits, newest first.
// Runs in esther-swa-deploy with the job's read-only GITHUB_TOKEN. No Entra access, no secrets written.
import fs from 'node:fs';
const REPO = process.env.GITHUB_REPOSITORY || 'azure-lab-automation-el/azure-lab-automation';
const H = { authorization: `Bearer ${process.env.GH_TOKEN}`, accept: 'application/vnd.github+json', 'user-agent': 'esther-audit' };
const get = async (p) => { const r = await fetch(`https://api.github.com/repos/${REPO}${p}`, { headers: H }); if (!r.ok) { console.error(p, r.status); return null; } return r.json(); };
const MARK = /<!-- esther-request (.+?) -->/s;
const events = [];
const runs = (await get('/actions/runs?per_page=100'))?.workflow_runs || [];
for (const r of runs) events.push({ ts: r.run_started_at || r.created_at, source: 'workflow', actor: r.triggering_actor?.login || r.actor?.login || '', action: r.name, target: r.event, status: r.status === 'completed' ? (r.conclusion || 'unknown') : r.status, url: r.html_url, detail: (r.display_title || '').slice(0, 140), durationSec: r.updated_at && r.run_started_at ? Math.round((Date.parse(r.updated_at) - Date.parse(r.run_started_at)) / 1000) : null });
const prs = (await get('/pulls?state=all&per_page=100&sort=created&direction=desc')) || [];
for (const p of prs.filter((x) => x.head.ref.startsWith('request/'))) {
  let c = {}; const m = (p.body || '').match(MARK); if (m) { try { c = JSON.parse(Buffer.from(m[1], 'base64').toString('utf8')); } catch {} }
  events.push({ ts: p.created_at, source: 'request', actor: c.requestedBy || p.user?.login || '', action: c.action || p.title, target: c.userPrincipalName || '', status: p.merged_at ? 'applied' : p.state === 'open' ? 'pending' : 'rejected', url: p.html_url, detail: `${c.kind || ''} ${c.reason ? '· ' + c.reason : ''}`.trim().slice(0, 160) });
}
const commits = (await get('/commits?sha=main&per_page=60')) || [];
for (const c of commits) events.push({ ts: c.commit.author.date, source: 'commit', actor: c.commit.author.name, action: 'commit', target: c.sha.slice(0, 7), status: 'recorded', url: c.html_url, detail: c.commit.message.split('\n')[0].slice(0, 160) });
events.sort((a, b) => (a.ts < b.ts ? 1 : -1));
const since = Date.now() - 7 * 864e5; const workflows = {};
for (const r of runs) {
  const w = (workflows[r.name] ||= { name: r.name, last: null, lastAt: null, url: null, ok7: 0, fail7: 0 });
  if (!w.lastAt) { w.last = r.status === 'completed' ? r.conclusion : r.status; w.lastAt = r.run_started_at || r.created_at; w.url = r.html_url; }
  if (Date.parse(r.created_at) > since && r.status === 'completed') { if (r.conclusion === 'success') w.ok7++; else if (r.conclusion === 'failure') w.fail7++; }
}
fs.writeFileSync(process.argv[2] || 'api/audit-log.json', JSON.stringify({ generatedAt: new Date().toISOString(), events: events.slice(0, 400), workflows: Object.values(workflows) }));
console.log(`audit-log: ${events.length} events, ${Object.keys(workflows).length} workflows`);
