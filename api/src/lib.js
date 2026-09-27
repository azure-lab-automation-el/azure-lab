'use strict';
// No Graph credentials in the portal. Reads come from inventory.json (read-only snapshot exported by esther-apply
// right after each readback, bundled at deploy). Writes are change-request PRs; merge to main = apply via OIDC.
const fs = require('fs'); const path = require('path');
const read = (f, d) => { try { return JSON.parse(fs.readFileSync(path.join(__dirname, '..', f), 'utf8')); } catch { return d; } };
const inventory = () => read('inventory.json', { users: [], groups: [], generatedAt: null });
const roles = () => read('config/portal-roles.json', { approvers: [], admins: [], helpdesk: [] });
const policy = () => read('config/approval-policy.json', { standard: [], special: [] });
const templates = () => read('config/templates.json', { departments: {} });
const lc = (s) => (s || '').toLowerCase();
function principal(request) {
  const h = request.headers.get('x-ms-client-principal'); if (!h) return null;
  try { return JSON.parse(Buffer.from(h, 'base64').toString('utf8')); } catch { return null; }
}
// Two ways in, both behind the SWA sign-in:
// 1. Preferred: an ID token from the "Esther Cloud Admin" app (single tenant, assignment required). Its roles claim
//    (Esther.Admin / Esther.Approver / Esther.HelpDesk, granted through the Esther Portal groups) decides access.
//    The token must be for the same person as the SWA session.
// 2. Fallback: config/portal-roles.json allowlist on the SWA identity.
const crypto = require('crypto');
const TENANT = 'f80b4063-5bc4-47e4-9ea6-a2a19ed79fa3';
const PORTAL_APP = process.env.ESTHER_PORTAL_CLIENT_ID || read('config/portal-app.json', {}).clientId || '';
let jwks = { at: 0, keys: [] };
async function signingKey(kid) {
  if (Date.now() - jwks.at > 6 * 3600e3 || !jwks.keys.some((k) => k.kid === kid)) {
    const r = await fetch(`https://login.microsoftonline.com/${TENANT}/discovery/v2.0/keys`); jwks = { at: Date.now(), keys: (await r.json()).keys || [] };
  }
  const k = jwks.keys.find((x) => x.kid === kid); return k ? crypto.createPublicKey({ key: k, format: 'jwk' }) : null;
}
const b64 = (s) => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
async function verifyAppToken(tok) {
  if (!PORTAL_APP || !tok || tok.length > 8000) return null;
  const parts = tok.split('.'); if (parts.length !== 3) return null;
  let h; let c; try { h = JSON.parse(b64(parts[0])); c = JSON.parse(b64(parts[1])); } catch { return null; }
  if (h.alg !== 'RS256' || !h.kid) return null;
  const key = await signingKey(h.kid).catch(() => null); if (!key) return null;
  if (!crypto.verify('RSA-SHA256', Buffer.from(`${parts[0]}.${parts[1]}`), key, b64(parts[2]))) return null;
  const now = Date.now() / 1000;
  if (c.aud !== PORTAL_APP || c.iss !== `https://login.microsoftonline.com/${TENANT}/v2.0` || c.tid !== TENANT || !(c.exp > now - 60) || !(c.nbf === undefined || c.nbf < now + 60)) return null;
  return c;
}
async function whoami(request) {
  const p = principal(request); if (!p || p.identityProvider !== 'aad') return null;
  const u = lc(p.userDetails);
  const c = await verifyAppToken(request.headers.get('x-esther-token'));
  if (c && [c.preferred_username, c.email, c.upn].map(lc).includes(u)) {
    const r = c.roles || []; const approver = r.includes('Esther.Approver'); const admin = approver || r.includes('Esther.Admin'); const helpdesk = r.includes('Esther.HelpDesk');
    return admin || helpdesk ? { user: p.userDetails, approver, admin: admin || helpdesk, helpdesk: helpdesk && !admin, via: 'app-roles', roles: r } : null;
  }
  const r = roles(); const approver = r.approvers.map(lc).includes(u); const admin = approver || r.admins.map(lc).includes(u);
  if (admin) return { user: p.userDetails, approver, admin, via: 'allowlist' };
  return (r.helpdesk || []).map(lc).includes(u) ? { user: p.userDetails, approver: false, admin: true, helpdesk: true, via: 'allowlist' } : null;
}
async function requireAdmin(request) {
  const me = await whoami(request);
  return me ? { me } : { deny: { status: 403, jsonBody: { error: 'Not allowed in the Esther portal (no Esther role and not on the allowlist)' } } };
}
function requestToken() {
  if (process.env.GH_REQUEST_TOKEN) return process.env.GH_REQUEST_TOKEN;
  try { return fs.readFileSync(path.join(__dirname, '..', '.request-token'), 'utf8').trim(); } catch { return ''; }
}
module.exports = { inventory, roles, policy, templates, principal, whoami, requireAdmin, requestToken, lc };
