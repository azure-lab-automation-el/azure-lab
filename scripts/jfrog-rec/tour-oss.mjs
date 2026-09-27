// Pilot scenario: log in, open repositories, browse an artifact, show its properties. Slow, visible steps.
import { chromium } from 'playwright';
const B = 'http://localhost:8082';
const browser = await chromium.launch();
// Warm-up pass (no video): login, clear onboarding, and load the deep link once so the slow OSS UI boot is not recorded.
const ctx = await browser.newContext({ viewport: { width: 1920, height: 1080 } });
let p = await ctx.newPage();
const pause = (ms = 1500) => p.waitForTimeout(ms);
const log = (m) => console.log(new Date().toISOString(), m);
try {
  // Load the login page once and let the SPA finish (reloading restarts its warm-up). Poll up to 8 min; reload only every 2 min.
  let user = null;
  await p.goto(`${B}/ui/login/`, { waitUntil: 'domcontentloaded' }).catch(()=>{});
  for (let i = 0; i < 32 && !user; i++) {
    try { await p.locator('input[type="password"]:visible').first().waitFor({ timeout: 15000 }); user = p.locator('input:visible:not([type="password"]):not([type="checkbox"]):not([type="hidden"])').first(); }
    catch {
      const txt = (await p.locator('body').innerText().catch(()=>'')).replace(/\s+/g, ' ').slice(0, 160);
      log(`login form not ready, poll ${i + 1}: ${txt}`);
      if (i % 4 === 3) await p.screenshot({ path: `out/login-wait-${i}.png` }).catch(()=>{});
      if (i % 8 === 7) await p.goto(`${B}/ui/login/`, { waitUntil: 'domcontentloaded' }).catch(()=>{});
    }
  }
  if (!user) throw new Error('login form never appeared');
  await pause(1500);
  await user.click(); await user.fill('admin'); await pause(600);
  await p.locator('input[type="password"]:visible').first().fill('password'); await pause(600);
  await p.keyboard.press('Enter'); await p.waitForLoadState('networkidle'); await pause(3000); log('STEP login');
  // The OSS first-login onboarding modal ("WELCOME TO ARTIFACTORY ... Get Started") can appear late; clear it before each step.
  const modalUp = async () => (await p.getByText(/WELCOME TO ARTIFACTORY|RESET ADMIN PASSWORD|Configure Default Proxy|Set Base URL/i).filter({ visible: true }).count()) > 0 || (await p.locator('.el-dialog__wrapper:visible, .modal.show, [role="dialog"]:visible').count()) > 0;
  const clearModal = async (tag) => {
    const o = { timeout: 3000 };
    for (let i = 0; i < 10 && await modalUp(); i++) {
      // Buttons only (never links like "Skip to main content"); exact names seen in the OSS onboarding flow.
      let clicked = '';
      // Wizard step 1 (Reset Admin Password) has Skip disabled: set a throwaway password for this disposable runner container, then Next.
      if (await p.locator('input[type="password"]:visible').count() >= 2) {
        const pw = 'Tour-' + Math.random().toString(36).slice(2, 10) + '-A1!';
        const f = p.locator('input[type="password"]:visible');
        if (await f.count() >= 2) { await f.nth(0).fill(pw).catch(()=>{}); await f.nth(1).fill(pw).catch(()=>{}); await pause(800); }
        await p.getByRole('button', { name: 'Next', exact: true }).filter({ visible: true }).first().click(o).catch(()=>{}); clicked = 'pw+Next'; await pause(3000);
      }
      // "Get Started" opens the wizard; its "Skip" button only becomes clickable after that. Only click visible buttons.
      if (!clicked) for (const t of ['Finish', 'Done', 'Get Started', 'Skip', 'Skip Onboarding', 'Close']) {
        const b = p.getByRole('button', { name: t, exact: true }).filter({ visible: true }); if (await b.count()) { await b.first().click(o).catch(()=>{}); clicked = t; await pause(2500); break; }
      }
      if (!clicked && await modalUp()) { await p.keyboard.press('Escape').catch(()=>{}); await pause(800); clicked = 'Escape'; }
      const x = p.locator('.el-dialog__headerbtn, button[aria-label="Close"], [role="dialog"] .close, .modal .close'); if (await modalUp() && await x.count()) { await x.first().click(o).catch(()=>{}); await pause(800); }
      const btns = await p.getByRole('button').allInnerTexts().catch(()=>[]);
      log(`modal ${tag} try ${i + 1} clicked=${clicked} buttons=${JSON.stringify(btns.map((t) => t.trim()).filter(Boolean).slice(0, 25))} body=${(await p.locator('body').innerText().catch(()=>'')).replace(/\s+/g, ' ').slice(0, 200)}`);
      await p.screenshot({ path: `out/modal-${tag}-${i + 1}.png` }).catch(()=>{});
    }
    log(await modalUp() ? `MODAL_STILL ${tag}` : `MODAL_CLEAR ${tag}`);
  };
  await pause(4000); await clearModal('after-login');
  // Navigate inside the SPA (a full page load restarts the slow OSS boot spinner).
  // OSS 7.x sidebar: "Artifactory" section expands to "Artifacts". Fallback: hash route to the tree.
  await p.getByText('Artifactory', { exact: true }).filter({ visible: true }).first().click({ timeout: 10000 }).catch((e) => log('nav artifactory: ' + e.message)); await pause(2500);
  await p.getByText('Artifacts', { exact: true }).filter({ visible: true }).first().click({ timeout: 10000 }).catch(async (e) => { log('nav artifacts: ' + e.message); await p.goto(`${B}/ui/repos/tree/General/demo-generic-local`, { waitUntil: 'domcontentloaded' }).catch(()=>{}); await p.getByText('demo-generic-local').first().waitFor({ timeout: 300000 }).catch(()=>{}); });
  await pause(4000); await clearModal('tree');
  // Tree nodes: click the visible node text (select), then double-click to expand. Only visible elements.
  // Tree: click a visible label if one exists (bounded waits only); otherwise deep-link to the item (the tree opens expanded on it).
  const node = async (t, tag) => {
    const el = p.getByText(t, { exact: true }).filter({ visible: true });
    const n = await el.count(); log(`${tag}: ${n} visible`);
    if (n) { await el.first().click({ timeout: 8000 }).catch((e) => log(`${tag} click: ${e.message.split('\n')[0]}`)); await pause(2500); return true; }
    return false;
  };
  await node('demo-generic-local', 'repo'); log('STEP repo tree');
  await p.goto(`${B}/ui/repos/tree/General/demo-generic-local/app/1.0.0/hello-1.0.0.txt`, { waitUntil: 'domcontentloaded' }).catch(()=>{});
  await p.getByText('hello-1.0.0.txt').filter({ visible: true }).first().waitFor({ timeout: 300000 }).catch((e) => log('deep link wait: ' + e.message.split('\n')[0]));
  await clearModal('deep'); log('WARMUP_DONE');
  const state = await ctx.storageState();
  const rctx = await browser.newContext({ viewport: { width: 1920, height: 1080 }, storageState: state, recordVideo: { dir: 'out', size: { width: 1920, height: 1080 } } });
  p = await rctx.newPage(); globalThis.__rctx = rctx;
  const ready = async (url, text) => { await p.goto(url, { waitUntil: 'domcontentloaded' }).catch(()=>{}); await p.getByText(text, { exact: true }).filter({ visible: true }).first().waitFor({ timeout: 240000 }).catch((e) => log('wait ' + text + ': ' + e.message.split('\n')[0])); };
  await ready(`${B}/ui/repos/tree/General/demo-generic-local`, 'demo-generic-local'); log('REC_START'); await clearModal('rec'); await pause(4000);
  // Expand without page reloads (a reload restarts the slow OSS boot): force-click the label, then double-click / caret / ArrowRight.
  const expand = async (label) => {
    const el = p.getByText(label, { exact: true }).filter({ visible: true }).first();
    if (!(await el.count())) { log(`expand ${label}: not visible`); return false; }
    const kids = async () => p.getByText(label === 'demo-generic-local' ? 'app' : label === 'app' ? '1.0.0' : 'hello-1.0.0.txt', { exact: true }).filter({ visible: true }).count();
    const waitKids = async (ms) => { for (let t = 0; t < ms; t += 500) { if (await kids()) return true; await pause(500); } return false; };
    await el.click({ timeout: 5000, force: true }).catch(()=>{});
    if (await waitKids(3000)) { log(`expand ${label}: already open`); return true; }
    // (label selected above)
    // Artifactory tree: role=treeitem rows with a div.expander arrow.
    await p.locator('[role="treeitem"]').filter({ has: p.getByText(label, { exact: true }) }).last().locator('.expander').first().click({ timeout: 5000, force: true }).catch((e) => log(`expand ${label} expander: ${e.message.split('\n')[0]}`)); 
    if (await waitKids(10000)) { log(`expand ${label}: expander`); return true; }
    await el.dblclick({ timeout: 5000, force: true }).catch(()=>{}); if (await waitKids(8000)) { log(`expand ${label}: dblclick`); return true; }
    const row = el.locator('xpath=ancestor::*[self::li or @role="treeitem" or contains(@class,"node")][1]');
    await row.locator('[class*="arrow"],[class*="caret"],[class*="toggle"],[class*="expand"]').first().click({ timeout: 4000, force: true }).catch(()=>{}); await pause(1500); if (await kids()) { log(`expand ${label}: caret`); return true; }
    await p.keyboard.press('ArrowRight').catch(()=>{}); await pause(1500); if (await kids()) { log(`expand ${label}: key`); return true; }
    log(`expand ${label}: failed`); return false;
  };
  // Debug: log the tree row markup once so the expand control can be targeted exactly.
  await pause(2000);
  for (const label of ['demo-generic-local', 'app', '1.0.0']) { await expand(label); await pause(2000); }
  if (!(await node('hello-1.0.0.txt', 'file'))) await ready(`${B}/ui/repos/tree/General/demo-generic-local/app/1.0.0/hello-1.0.0.txt`, 'hello-1.0.0.txt');
  await pause(5000); log('STEP artifact');
  await p.getByText('Properties', { exact: true }).filter({ visible: true }).first().click().catch(()=>{}); await pause(5000); log('STEP properties');
  await clearModal('final'); await p.screenshot({ path: 'out/final.png' });
  if (await modalUp()) throw new Error('onboarding modal still covering the UI');
  if (!(await p.getByText('hello-1.0.0.txt').filter({ visible: true }).count())) throw new Error('artifact not visible at the end (tour did not reach the repo)');
} catch (e) { console.error('SCENARIO_FAIL', e.message); await p.screenshot({ path: 'out/fail.png' }); }
if (globalThis.__rctx) await globalThis.__rctx.close(); await ctx.close(); await browser.close(); log('RECORD_DONE');
