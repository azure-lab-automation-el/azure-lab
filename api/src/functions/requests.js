'use strict';
// Change requests = pull requests on the repo. Standard actions (or any action by an approver) are merged at once;
// special actions by other admins wait for an approver who is not the requester. Merge to main = esther-apply.
// The request token is repo-scoped (contents + pull requests). It cannot touch Entra.
const { app } = require('@azure/functions');
const { requireAdmin, requestToken, inventory, policy, lc } = require('../lib');
const { validateRequest, clean } = require('../validate');
const REPO = process.env.GH_REPO || 'azure-lab-automation-el/azure-lab-automation';
const MARK = /<!-- esther-request (.+?) -->/s;
const HELPDESK = ['resetPassword', 'enableUser'];

async function gh(p, method = 'GET', body) {
  const r = await fetch(`https://api.github.com/repos/${REPO}${p}`, { method,
    headers: { authorization: `Bearer ${requestToken()}`, accept: 'application/vnd.github+json', 'user-agent': 'esther-cloud-admin', 'x-github-api-version': '2022-11-28' },
    body: body ? JSON.stringify(body) : undefined });
  const t = await r.text(); const j = t ? JSON.parse(t) : {};
  if (!r.ok) throw new Error(`github ${r.status} ${j.message || ''}`.trim()); return j;
}
const parse = (pr) => { const m = (pr.body || '').match(MARK); if (!m) return null;
  try { const c = JSON.parse(Buffer.from(m[1], 'base64').toString('utf8'));
    return { ...c, number: pr.number, url: pr.html_url, state: pr.merged_at ? 'applied' : pr.state === 'open' ? 'pending' : 'rejected', updatedAt: pr.updated_at }; } catch { return null; } };
async function merge(n, who) {
  await gh(`/pulls/${n}/merge`, 'PUT', { merge_method: 'squash', commit_title: `Esther request #${n} (approved by ${who})` });
}

app.http('requests', { methods: ['GET', 'POST'], authLevel: 'anonymous', handler: async (request) => {
  const { me, deny } = await requireAdmin(request); if (deny) return deny;
  const configured = !!requestToken();
  if (request.method === 'GET') {
    if (!configured) return { jsonBody: { configured, requests: [] } };
    const prs = await gh('/pulls?state=all&per_page=50&sort=created&direction=desc');
    return { jsonBody: { configured, requests: prs.filter((p) => p.head.ref.startsWith('request/')).map(parse).filter(Boolean) } };
  }
  const raw = await request.json().catch(() => ({}));
  const lifecycle = ['joiner', 'mover', 'leaver'].includes(raw.lifecycle) ? raw.lifecycle : null;
  const items = (Array.isArray(raw.batch) ? raw.batch : [raw]).map(clean);
  if (!items.length || items.length > 200) return { status: 400, jsonBody: { error: 'between 1 and 200 changes per request' } };
  const inv = inventory(); const errs = [];
  items.forEach((d, i) => { const e = validateRequest(d, inv); if (e.length) errs.push(items.length > 1 ? `row ${i + 1}: ${e.join(', ')}` : e.join('; ')); });
  if (items.length > 1 && items.some((d) => d.action === 'resetPassword')) errs.push('password reset is one user at a time');
  if (errs.length) return { status: 400, jsonBody: { error: errs.slice(0, 20).join(' | ') } };
  // Help desk role: one user at a time, password reset and re-enable only (still needs an approver).
  if (me.helpdesk && (items.length > 1 || items.some((d) => !HELPDESK.includes(d.action)))) return { status: 403, jsonBody: { error: 'The help desk role can only reset a password or re-enable an account, one user at a time' } };
  const pol = policy(); const special = items.some((d) => pol.special.includes(d.action));
  const autoApply = (!special && !me.helpdesk) || me.approver;
  const id = `${new Date().toISOString().replace(/[:.]/g, '-')}-${Math.random().toString(36).slice(2, 8)}`;
  const now = new Date().toISOString(); const kind = special ? 'special' : 'standard';
  const changes = items.map((d, i) => ({ id: items.length > 1 ? `${id}-${String(i + 1).padStart(3, '0')}` : id, requestedBy: me.user, requestedAt: now, kind, ...(lifecycle ? { lifecycle } : {}), ...d }));
  const head = changes[0]; const title = lifecycle ? `${lifecycle} ${head.userPrincipalName}${items.length > 1 ? ` (${items.length} steps)` : ''}` : items.length > 1 ? `bulk (${items.length})` : `${head.action} ${head.userPrincipalName}`;
  const { publicKey: _pk, ...headPublic } = head;
  const summary = { ...headPublic, action: lifecycle || (items.length > 1 ? 'bulk' : head.action), count: items.length, userPrincipalName: lifecycle || items.length === 1 ? head.userPrincipalName : `${items.length} changes` };
  if (!configured) return { status: 202, jsonBody: { change: summary, note: 'Preview only: the request token is not set up yet, nothing was filed.' } };
  const main = await gh('/git/ref/heads/main'); const branch = `request/${id}`;
  await gh('/git/refs', 'POST', { ref: `refs/heads/${branch}`, sha: main.object.sha });
  for (const c of changes) await gh(`/contents/requests/${c.id}.json`, 'PUT', { message: `Request ${c.id}: ${c.action} ${c.userPrincipalName}`, branch, content: Buffer.from(JSON.stringify(c, null, 2) + '\n').toString('base64') });
  const lines = changes.slice(0, 50).map((c) => `- ${c.action} ${c.userPrincipalName}${c.group ? ' -> ' + c.group : ''}${c.manager ? ' -> ' + c.manager : ''}`).join('\n');
  const body = `Requested by ${me.user} (${kind})\nReason: ${head.reason}\n\n${lines}\n\n${autoApply ? 'Applied on filing.' : 'Waiting for an approver in the portal.'}\n<!-- esther-request ${Buffer.from(JSON.stringify(summary)).toString('base64')} -->`;
  const pr = await gh('/pulls', 'POST', { title: `[${kind}] ${title}`, head: branch, base: 'main', body });
  if (autoApply) await merge(pr.number, me.approver ? me.user : 'policy: standard');
  return { status: 201, jsonBody: { change: summary, number: pr.number, url: pr.html_url, state: autoApply ? 'applying' : 'pending' } };
} });

app.http('decide', { route: 'requests/{number}/{decision}', methods: ['POST'], authLevel: 'anonymous', handler: async (request) => {
  const { me, deny } = await requireAdmin(request); if (deny) return deny;
  if (!requestToken()) return { status: 409, jsonBody: { error: 'request token not set up' } };
  const n = Number(request.params.number); const decision = request.params.decision;
  if (!Number.isInteger(n) || !['approve', 'reject'].includes(decision)) return { status: 400, jsonBody: { error: 'bad request' } };
  const pr = await gh(`/pulls/${n}`); const c = parse(pr);
  if (!c || !pr.head.ref.startsWith('request/') || pr.state !== 'open') return { status: 404, jsonBody: { error: 'no open request with that number' } };
  const own = lc(c.requestedBy) === lc(me.user);
  if (decision === 'approve') {
    if (!me.approver) return { status: 403, jsonBody: { error: 'approver role required' } };
    if (own) return { status: 403, jsonBody: { error: 'you cannot approve your own request' } };
    await gh(`/issues/${n}/comments`, 'POST', { body: `Approved in the portal by ${me.user}.` });
    await merge(n, me.user); return { jsonBody: { number: n, state: 'applying' } };
  }
  if (!me.approver && !own) return { status: 403, jsonBody: { error: 'only an approver or the requester can reject' } };
  await gh(`/issues/${n}/comments`, 'POST', { body: `Rejected in the portal by ${me.user}.` });
  await gh(`/pulls/${n}`, 'PATCH', { state: 'closed' });
  await gh(`/git/refs/heads/${pr.head.ref}`, 'DELETE').catch(() => {});
  return { jsonBody: { number: n, state: 'rejected' } };
} });

// One-time password pickup: returns only the RSA-OAEP ciphertext posted by esther-password; only the requester's browser holds the private key.
app.http('secret', { route: 'requests/{number}/secret', methods: ['GET'], authLevel: 'anonymous', handler: async (request) => {
  const { me, deny } = await requireAdmin(request); if (deny) return deny;
  const n = Number(request.params.number); if (!Number.isInteger(n) || n < 1) return { status: 400, jsonBody: { error: 'bad number' } };
  const pr = await gh(`/pulls/${n}`); const r = parse(pr);
  if (!r || r.action !== 'resetPassword') return { status: 404, jsonBody: { error: 'not a password reset' } };
  if ((r.requestedBy || '').toLowerCase() !== me.user.toLowerCase()) return { status: 403, jsonBody: { error: 'only the requester can pick this up' } };
  const comments = await gh(`/issues/${n}/comments?per_page=50`);
  const c = comments.map((x) => /<!-- esther-secret ([A-Za-z0-9+/=]+) -->/.exec(x.body || '')).find(Boolean);
  const failed = comments.some((x) => (x.body || '').includes('esther-secret-failed'));
  return { jsonBody: { ready: !!c, failed, ciphertext: c ? c[1] : null } };
} });
