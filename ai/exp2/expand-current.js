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
