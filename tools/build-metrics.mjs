// Builds api/metrics.json for SquaredUp (Web API data source): cost, VM state and portal workflow stats.
// Inputs: /tmp/costs (latest esther-costs-read artifact, optional) and api/audit-log.json. No secrets inside.
import fs from 'node:fs';
const rd = (f, d) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return d; } };
const cost = rd('/tmp/costs/azure-cost-30d.json', {}); const meters = rd('/tmp/costs/azure-cost-meters.json', {}); const vms = rd('/tmp/costs/azure-vm-state.json', []); const res = rd('/tmp/costs/azure-resource-inventory.json', []);
const rows = (j) => { const c = (j.properties?.columns || []).map((x) => x.name); return (j.properties?.rows || []).map((r) => Object.fromEntries(r.map((v, i) => [c[i], v]))); };
const daily = rows(cost).map((r) => ({ date: String(r.UsageDate || r.BillingMonth || '').replace(/^(\d{4})(\d{2})(\d{2}).*/, '$1-$2-$3'), cost: Number(r.Cost || r.PreTaxCost || r.CostUSD || 0), currency: r.Currency || 'USD' }));
const byMeter = rows(meters).map((r) => ({ meter: r.Meter || r.MeterCategory || r.ServiceName || '', cost: Number(r.Cost || r.PreTaxCost || r.CostUSD || 0) })).filter((x) => x.meter);
const log = rd('api/audit-log.json', { events: [], workflows: [] });
const day = Date.now() - 864e5; const wk = Date.now() - 7 * 864e5;
const req = log.events.filter((e) => e.source === 'request');
const out = {
  generatedAt: new Date().toISOString(),
  cost: { last30dTotal: +daily.reduce((a, x) => a + x.cost, 0).toFixed(4), currency: daily[0]?.currency || 'USD', daily, byMeter, readAt: fs.existsSync('/tmp/costs/azure-cost-30d.json') ? fs.statSync('/tmp/costs/azure-cost-30d.json').mtime.toISOString() : null },
  vms: vms.map((v) => ({ name: v.name, group: v.group, power: v.power, size: v.size })), vmRunning: vms.filter((v) => /running/i.test(v.power || '')).length, resources: res.length,
  workflows: log.workflows.map((w) => ({ name: w.name, last: w.last, lastAt: w.lastAt, ok7: w.ok7, fail7: w.fail7 })),
  requests: { last24h: req.filter((e) => Date.parse(e.ts) > day).length, last7d: req.filter((e) => Date.parse(e.ts) > wk).length, pending: req.filter((e) => e.status === 'pending').length, applied7d: req.filter((e) => e.status === 'applied' && Date.parse(e.ts) > wk).length },
  runs: log.events.filter((e) => e.source === 'workflow').slice(0, 100).map((e) => ({ ts: e.ts, workflow: e.action, status: e.status, durationSec: e.durationSec })),
};
fs.writeFileSync(process.argv[2] || 'api/metrics.json', JSON.stringify(out));
console.log(`metrics: cost30d=${out.cost.last30dTotal} ${out.cost.currency}, vms=${out.vms.length}, workflows=${out.workflows.length}`);
