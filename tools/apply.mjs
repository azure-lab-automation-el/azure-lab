// Applies plan.json via Graph, then re-reads Entra and re-plans. Exit 0 only if readback shows zero remaining ops.
// Usage: GRAPH_TOKEN=... node tools/apply.mjs --plan plan.json --desired desired-state/state.json [--dry-run]
import fs from 'node:fs'; import crypto from 'node:crypto';
import { readCurrent, plan } from './plan.mjs';
const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, all) => (v.startsWith('--') ? [...a, [v.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true]] : a), []));
const G = 'https://graph.microsoft.com/v1.0'; const token = process.env.GRAPH_TOKEN;
async function call(method, path, body) {
  if (args['dry-run']) { console.log('DRY', method, path, body ? JSON.stringify(body).replace(/"password":"[^"]*"/, '"password":"***"') : ''); return {}; }
  let r;
  for (let i = 0; i < 6; i++) { // a just-created user can 404 for a few seconds (replication)
    r = await fetch(G + path, { method, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
    if (!(r.status === 404 && (method === 'GET' || method === 'PUT' || method === 'POST'))) break;
    await new Promise((res) => setTimeout(res, 4000));
  }
  if (!r.ok) throw new Error(`${method} ${path} -> ${r.status} ${(await r.text()).slice(0, 300)}`);
  return r.status === 204 ? {} : r.json();
}
const enc = encodeURIComponent;
const p = JSON.parse(fs.readFileSync(args.plan, 'utf8'));
if (p.errors.length) { console.error('plan has errors; refusing'); process.exit(2); }
// Guard. Two kinds of approved change:
//  1. a reviewed stage plan (desired-state/reviewed-plan.json, applied=false): live plan must match it exactly;
//  2. portal requests (requests/*.json): every live op must touch only users named in those requests.
// Anything else (drift, unexpected ops) makes apply refuse.
if (args.reviewed && p.opCount > 0) {
  const r = JSON.parse(fs.readFileSync(args.reviewed, 'utf8'));
  const scope = fs.existsSync('request-scope.json') ? JSON.parse(fs.readFileSync('request-scope.json', 'utf8')) : { files: [], upns: [] };
  if (!r.applied) {
    const same = JSON.stringify(Object.entries(r.summary).sort()) === JSON.stringify(Object.entries(p.summary).sort()) && r.opCount === p.opCount;
    if (!same || scope.files.length) { console.error('live plan differs from reviewed plan (or requests mixed in); refusing', JSON.stringify({ reviewed: r.summary, live: p.summary, requests: scope.files.length })); process.exit(4); }
  } else {
    const allowed = new Set(scope.upns.map((x) => x.toLowerCase()));
    const stray = p.ops.filter((o) => !o.upn || !allowed.has(o.upn.toLowerCase()));
    if (!scope.files.length || stray.length) { console.error('ops outside approved requests; refusing', JSON.stringify(stray.slice(0, 10))); process.exit(4); }
  }
}
const log = [];
for (const o of p.ops) {
  if (o.op === 'createUser') {
    // Random initial password is never logged or stored; admin resets it through the separate password workflow.
    const pw = crypto.randomBytes(18).toString('base64url') + 'Aa1!';
    await call('POST', '/users', { accountEnabled: true, ...o.set, userPrincipalName: o.upn, mailNickname: o.upn.split('@')[0].replace(/[^A-Za-z0-9]/g, ''), passwordProfile: { forceChangePasswordNextSignIn: true, password: pw } });
  } else if (o.op === 'renameUser') await call('PATCH', `/users/${o.id}`, { userPrincipalName: o.upn });
  else if (o.op === 'renameGroup') await call('PATCH', `/groups/${o.groupId}`, { displayName: o.group });
  else if (o.op === 'updateUser') await call('PATCH', `/users/${o.id || enc(o.upn)}`, o.set);
  else if (o.op === 'setManager') {
    const m = args['dry-run'] ? { id: 'DRY' } : await call('GET', `/users/${enc(o.manager)}?$select=id`);
    await call('PUT', `/users/${enc(o.upn)}/manager/$ref`, { '@odata.id': `${G}/users/${m.id}` });
  } else if (o.op === 'removeManager') await call('DELETE', `/users/${enc(o.upn)}/manager/$ref`);
  else if (o.op === 'addMember') {
    const u = args['dry-run'] ? { id: 'DRY' } : await call('GET', `/users/${enc(o.upn)}?$select=id`);
    await call('POST', `/groups/${o.groupId}/members/$ref`, { '@odata.id': `${G}/directoryObjects/${u.id}` });
  } else if (o.op === 'removeMember') {
    const u = args['dry-run'] ? { id: 'DRY' } : await call('GET', `/users/${enc(o.upn)}?$select=id`);
    await call('DELETE', `/groups/${o.groupId}/members/${u.id}/$ref`);
  } else throw new Error('unknown op ' + o.op);
  log.push({ at: new Date().toISOString(), ...o }); console.log('OK', o.op, o.upn || '', o.group || '');
}
fs.writeFileSync('apply-log.json', JSON.stringify(log, null, 2));
if (args['dry-run']) process.exit(0);
const desired = JSON.parse(fs.readFileSync(args.desired, 'utf8'));
// Entra is eventually consistent: re-read a few times before calling the readback a failure.
let after;
for (let i = 0; i < 6; i++) {
  after = plan(desired, await readCurrent(token, desired.upnSuffix));
  console.log(`READBACK attempt ${i + 1}: remaining ops ${after.opCount}`);
  if (after.opCount === 0) break;
  await new Promise((r) => setTimeout(r, 20000));
}
fs.writeFileSync('readback-plan.json', JSON.stringify(after, null, 2));
console.log('READBACK remaining ops:', after.opCount);
process.exit(after.opCount === 0 ? 0 : 3);
