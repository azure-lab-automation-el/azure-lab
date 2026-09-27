'use strict';
// Ops / GitHub: live workflow runs for the admin console. Read-only.
// Uses the repo-scoped request token server-side (never sent to the browser). Falls back to the deploy-time snapshot.
const { app } = require('@azure/functions');
const fs = require('fs'); const path = require('path');
const { requireAdmin, requestToken } = require('../lib');
const REPO = 'azure-lab-automation-el/azure-lab-automation';
const read = (f, d) => { try { return JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', f), 'utf8')); } catch { return d; } };
const pick = (r) => ({ id: r.id, name: r.name, title: r.display_title, status: r.status, conclusion: r.conclusion, event: r.event,
  branch: r.head_branch, sha: (r.head_sha || '').slice(0, 7), createdAt: r.created_at, startedAt: r.run_started_at, updatedAt: r.updated_at,
  attempt: r.run_attempt, url: r.html_url, actor: r.actor && r.actor.login });
// Esther heartbeat: a small JSON the server uploads every ~45s to one Table Storage row; read here with a read-only SAS (app setting HEARTBEAT_URL).
async function heartbeat() { const u = process.env.HEARTBEAT_URL; if (!u) return null;
  try { const r = await fetch(u, { headers: { Accept: 'application/json;odata=nometadata', 'x-ms-version': '2019-02-02' }, signal: AbortSignal.timeout(5000) }); if (!r.ok) return null; const e = await r.json(); const j = JSON.parse(e.data); j.ageSec = Math.round((Date.now() - Date.parse(j.at)) / 1000); return j; } catch { return null; } }
app.http('adminOps', { route: 'admin/ops', methods: ['GET'], authLevel: 'anonymous', handler: async (request) => {
  const { me, deny } = await requireAdmin(request); if (deny) return deny;
  if (me.helpdesk) return { status: 403, jsonBody: { error: 'The help desk role cannot open Ops' } };
  const t = requestToken(); const hbP = heartbeat();
  if (t) {
    try {
      const h = { Authorization: `Bearer ${t}`, Accept: 'application/vnd.github+json', 'User-Agent': 'estherdaxes-ops' };
      const [runs, commits] = await Promise.all([
        fetch(`https://api.github.com/repos/${REPO}/actions/runs?per_page=60`, { headers: h }),
        fetch(`https://api.github.com/repos/${REPO}/commits?per_page=15`, { headers: h })]);
      if (runs.ok) {
        const j = await runs.json(); const c = commits.ok ? await commits.json() : [];
        const live = j.workflow_runs.filter((r) => r.status !== 'completed').slice(0, 6);
        const status = {};
        await Promise.all(live.map(async (r) => { try { const f = await fetch(`https://api.github.com/repos/${REPO}/contents/status/${r.id}.json?ref=ops-status`, { headers: { ...h, Accept: 'application/vnd.github.raw+json' } });
          if (f.ok) status[String(r.id)] = await f.json(); } catch {} }));
        const steps = {};
        await Promise.all(live.map(async (r) => { try { const jj = await (await fetch(`https://api.github.com/repos/${REPO}/actions/runs/${r.id}/jobs`, { headers: h })).json();
          const st = (jj.jobs || []).flatMap((x) => x.steps || []); const cur = st.find((x) => x.status === 'in_progress');
          steps[r.id] = { total: st.length, done: st.filter((x) => x.status === 'completed').length, current: cur ? cur.name : null, list: st.map((x) => ({ n: x.name, s: x.status, c: x.conclusion })) }; } catch {} }));
        return { headers: { 'Cache-Control': 'no-store' }, jsonBody: { heartbeat: await hbP, live: true, fetchedAt: new Date().toISOString(), repo: REPO, total: j.total_count, runs: j.workflow_runs.map((r) => ({ ...pick(r), live: status[String(r.id)] || null, steps: steps[r.id] || null })),
          commits: c.map((x) => ({ sha: x.sha.slice(0, 7), msg: (x.commit.message || '').split('\n')[0], at: x.commit.author && x.commit.author.date, url: x.html_url })) } };
      }
    } catch { /* fall through to snapshot */ }
  }
  const log = read('audit-log.json', { generatedAt: null, workflows: [] });
  const ev = (log.events || []);
  const runs = ev.filter((e) => e.source === 'workflow').slice(0, 60).map((e, i) => ({ id: i, name: e.action, title: e.detail, status: ['success', 'failure', 'cancelled', 'skipped', 'unknown'].includes(e.status) ? 'completed' : e.status,
    conclusion: ['success', 'failure', 'cancelled', 'skipped'].includes(e.status) ? e.status : null, event: e.target, startedAt: e.ts, createdAt: e.ts,
    updatedAt: e.durationSec ? new Date(Date.parse(e.ts) + e.durationSec * 1000).toISOString() : e.ts, url: e.url, actor: e.actor }));
  const commits = ev.filter((e) => e.source === 'commit').slice(0, 15).map((e) => ({ sha: e.target, msg: e.detail, at: e.ts, url: e.url }));
  return { jsonBody: { heartbeat: await hbP, live: false, fetchedAt: log.generatedAt, repo: REPO, runs, commits } };
} });
