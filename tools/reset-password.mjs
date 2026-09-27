// Runs in esther-password (OIDC, main only). For each new resetPassword request file: sets a random temporary
// password (change required at next sign-in), encrypts it to the requester's one-time browser key (RSA-OAEP SHA-256)
// and posts only the ciphertext on the request PR. The password is never printed or written to disk.
import fs from 'node:fs'; import crypto from 'node:crypto';
const files = process.argv.slice(2); const G = 'https://graph.microsoft.com/v1.0';
const repo = process.env.GITHUB_REPOSITORY; const gh = (p, m = 'GET', b) => fetch(`https://api.github.com/repos/${repo}${p}`, { method: m, headers: { authorization: `Bearer ${process.env.GH_TOKEN}`, accept: 'application/vnd.github+json' }, body: b && JSON.stringify(b) }).then((r) => r.json());
const graph = (p, m, b) => fetch(G + p, { method: m, headers: { authorization: `Bearer ${process.env.GRAPH_TOKEN}`, 'content-type': 'application/json' }, body: b && JSON.stringify(b) });
function tempPassword() {
  const sets = ['ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!@#$%*-+?'];
  const pick = (s) => s[crypto.randomInt(s.length)]; const all = sets.join('');
  const chars = [...sets.map(pick), ...Array.from({ length: 12 }, () => pick(all))];
  for (let i = chars.length - 1; i > 0; i--) { const j = crypto.randomInt(i + 1); [chars[i], chars[j]] = [chars[j], chars[i]]; }
  return chars.join('');
}
let bad = 0;
for (const f of files) {
  const r = JSON.parse(fs.readFileSync(f, 'utf8')); if (r.action !== 'resetPassword') continue;
  const branch = `request/${r.id}`; const prs = await gh(`/pulls?state=closed&head=${repo.split('/')[0]}:${encodeURIComponent(branch)}`);
  const pr = Array.isArray(prs) && prs.find((p) => p.merged_at); if (!pr) { console.log(`${r.id}: no merged PR, skipped`); bad++; continue; }
  try {
    const key = crypto.createPublicKey({ key: { kty: 'RSA', n: r.publicKey.n, e: r.publicKey.e }, format: 'jwk' });
    let pw = tempPassword();
    const res = await graph(`/users/${encodeURIComponent(r.userPrincipalName)}`, 'PATCH', { passwordProfile: { forceChangePasswordNextSignIn: true, password: pw } });
    if (res.status !== 204) throw new Error(`Graph ${res.status} ${(await res.text()).slice(0, 200)}`);
    const ct = crypto.publicEncrypt({ key, padding: crypto.constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' }, Buffer.from(pw)).toString('base64'); pw = null;
    await gh(`/issues/${pr.number}/comments`, 'POST', { body: `Temporary password set for ${r.userPrincipalName} (change required at next sign-in). It is encrypted to the requester's browser and can only be opened there.\n<!-- esther-secret ${ct} -->` });
    console.log(`${r.id}: reset done, ciphertext posted on #${pr.number}`);
  } catch (e) { bad++; console.log(`${r.id}: failed: ${e.message}`); await gh(`/issues/${pr.number}/comments`, 'POST', { body: `Password reset failed: ${e.message.replace(/[<>]/g, '')}\n<!-- esther-secret-failed -->` }); }
}
console.log(`${bad} problem(s)`); // exit 0: failures are reported on the PR (no failure emails)
