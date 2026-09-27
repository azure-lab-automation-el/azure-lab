'use strict';
const { lc } = require('./lib');
const ACTIONS = ['createUser', 'updateUser', 'disableUser', 'enableUser', 'setManager', 'addToGroup', 'removeFromGroup', 'resetPassword'];
const UPN = /^[A-Za-z0-9._-]{1,64}@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
const TEXT = /^[\p{L}\p{N} .,'()&/-]{0,64}$/u;
const PHONE = /^\+?[0-9][0-9 ()-]{6,19}$/;
const REASON = /^[\p{L}\p{N}\p{P} ]{3,200}$/u;
const SUFFIX = '@estherh.v6.rocks';
// Checks shape and references against the current inventory, so obviously broken requests never become PRs.
function validateRequest(d, inv) {
  const e = [];
  const users = new Map(inv.users.map((u) => [lc(u.userPrincipalName), u]));
  const groups = new Set(inv.groups.map((g) => lc(g.displayName)));
  const depts = new Set(inv.groups.map((g) => g.displayName.replace('Esther Hospital - ', '')));
  if (!ACTIONS.includes(d.action)) return ['unknown action'];
  if (!UPN.test(d.userPrincipalName || '') || !lc(d.userPrincipalName).endsWith(SUFFIX)) e.push('UPN must be name@' + SUFFIX.slice(1));
  for (const k of ['displayName', 'department', 'jobTitle', 'group']) if (d[k] && !TEXT.test(d[k])) e.push(`bad ${k}`);
  if (!d.reason || !REASON.test(d.reason.trim())) e.push('reason required (3-200 characters)');
  const u = users.get(lc(d.userPrincipalName));
  if (d.action === 'createUser') { if (u) e.push('user already exists'); if (!d.displayName) e.push('display name required'); }
  else if (!u) e.push('unknown user');
  if (d.mobilePhone !== undefined && !PHONE.test(String(d.mobilePhone).trim())) e.push('phone must be digits, spaces, dashes or a leading +');
  if (d.action === 'updateUser' && !['displayName', 'department', 'jobTitle', 'mobilePhone'].some((k) => d[k])) e.push('nothing to change');
  if (d.department && !depts.has(d.department)) e.push('unknown department');
  if (d.manager) { if (!users.has(lc(d.manager))) e.push('unknown manager'); if (lc(d.manager) === lc(d.userPrincipalName)) e.push('user cannot manage themselves'); }
  if (d.action === 'setManager' && !d.manager) e.push('manager required');
  if (d.action === 'addToGroup' || d.action === 'removeFromGroup') { if (!groups.has(lc(d.group))) e.push('unknown group'); }
  if (d.action === 'disableUser' && u && u.accountEnabled === false) e.push('already disabled');
  if (d.action === 'enableUser' && u && u.accountEnabled !== false) e.push('already enabled');
  if (d.action === 'resetPassword') { const k = d.publicKey; if (!k || k.kty !== 'RSA' || k.e !== 'AQAB' || !/^[A-Za-z0-9_-]{340,700}$/.test(k.n || '')) e.push('a one-time browser key is required for password reset'); }
  return e;
}
const FIELDS = ['action', 'userPrincipalName', 'displayName', 'department', 'jobTitle', 'manager', 'group', 'mobilePhone', 'reason'];
const clean = (d) => { const o = Object.fromEntries(FIELDS.filter((k) => d[k] !== undefined && d[k] !== '').map((k) => [k, String(d[k]).trim()])); if (d.action === 'resetPassword' && d.publicKey && typeof d.publicKey === 'object') o.publicKey = { kty: String(d.publicKey.kty), e: String(d.publicKey.e), n: String(d.publicKey.n) }; return o; };
module.exports = { validateRequest, clean, ACTIONS };
