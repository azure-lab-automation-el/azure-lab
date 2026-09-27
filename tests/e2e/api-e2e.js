// Exercises the real API code against GitHub with the real request token. Entra-neutral:
// 1) approver files setManager to the user's CURRENT manager -> auto-merged -> apply sees 0 ops.
// 2) non-approver files a special disableUser -> stays pending -> approver rejects -> PR closed. Nothing applied.
const fs = require('fs'); const path = require('path');
const fn = path.join(__dirname, '../../api/node_modules/@azure/functions'); fs.mkdirSync(fn, { recursive: true });
fs.writeFileSync(path.join(fn, 'index.js'), 'const reg={};module.exports={app:{http:(n,o)=>{reg[n]=o}},_reg:reg};');
require('../../api/src/functions/directory.js'); require('../../api/src/functions/requests.js');
const { _reg } = require(fn);
const P = (u) => Buffer.from(JSON.stringify({ identityProvider: 'aad', userDetails: u, userRoles: ['authenticated'] })).toString('base64');
const req = (u, method, body, params = {}) => ({ method, params, headers: { get: (h) => (h === 'x-ms-client-principal' ? P(u) : null) }, json: async () => body });
(async () => {
  const inv = JSON.parse(fs.readFileSync(path.join(__dirname, '../../api/inventory.json')));
  const u = inv.users.find((x) => x.manager && x.userPrincipalName.startsWith('yael.gefen'));
  const op = 'azure-lab-operator@estherh.v6.rocks';
  const a = await _reg.requests.handler(req(op, 'POST', { action: 'setManager', userPrincipalName: u.userPrincipalName, manager: u.manager, reason: 'E2E test (no-op: same manager)' }));
  console.log('standard/approver:', a.status, JSON.stringify({ n: a.jsonBody.number, state: a.jsonBody.state, url: a.jsonBody.url, err: a.jsonBody.error }));
  // temporary non-approver admin for the test only
  const rolesFile = path.join(__dirname, '../../api/config/portal-roles.json'); const roles = JSON.parse(fs.readFileSync(rolesFile)); roles.admins.push('e2e.tester@estherh.v6.rocks'); fs.writeFileSync(rolesFile, JSON.stringify(roles));
  const b = await _reg.requests.handler(req('e2e.tester@estherh.v6.rocks', 'POST', { action: 'disableUser', userPrincipalName: u.userPrincipalName, reason: 'E2E test - will be rejected' }));
  console.log('special/admin:', b.status, JSON.stringify({ n: b.jsonBody.number, state: b.jsonBody.state, err: b.jsonBody.error }));
  const self = await _reg.decide.handler(req('e2e.tester@estherh.v6.rocks', 'POST', null, { number: String(b.jsonBody.number), decision: 'approve' }));
  console.log('self-approve blocked:', self.status, self.jsonBody.error);
  const list = await _reg.requests.handler(req(op, 'GET'));
  console.log('pending listed:', list.jsonBody.requests.filter((r) => r.state === 'pending').map((r) => r.number));
  const rej = await _reg.decide.handler(req(op, 'POST', null, { number: String(b.jsonBody.number), decision: 'reject' }));
  console.log('reject:', rej.status, JSON.stringify(rej.jsonBody));
})().catch((e) => { console.error(e); process.exit(1); });
