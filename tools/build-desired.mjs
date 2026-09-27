// Builds the desired Esther org from a read-only export + config/entra-expected.json.
// Stage 1 (desired-state/state.json): group renames, department allocation, varied titles, 99 manager links. UPNs unchanged.
// Stage 2 (proposals/stage2-upn-state.json): same org, UPNs renamed to first.last@ (separate line item / separate PR).
// Usage: node tools/build-desired.mjs --current tests/fixtures/live-2026-09-23.json
import fs from 'node:fs';
const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, all) => (v.startsWith('--') ? [...a, [v.slice(2), all[i + 1]]] : a), []));
const cur = JSON.parse(fs.readFileSync(args.current, 'utf8'));
const cfg = JSON.parse(fs.readFileSync('config/entra-expected.json', 'utf8'));
const SUFFIX = '@estherh.v6.rocks'; const PREFIX = 'Esther Hospital - ';
const TITLES = {
  Administration: ['Chief Executive Officer', 'Chief Operating Officer', 'Human Resources Manager', 'Executive Assistant', 'Office Manager', 'Quality Assurance Coordinator', 'Patient Relations Officer'],
  Emergency: ['Head of Emergency Medicine', 'Senior Emergency Physician', 'Emergency Physician', 'Emergency Nurse', 'Triage Nurse', 'Paramedic', 'Emergency Resident', 'Emergency Department Clerk'],
  Cardiology: ['Head of Cardiology', 'Senior Cardiologist', 'Cardiologist', 'Cardiac Nurse', 'Echocardiography Technician', 'Cardiology Resident', 'Cath Lab Technician'],
  Neurology: ['Head of Neurology', 'Senior Neurologist', 'Neurologist', 'Neurology Nurse', 'EEG Technician', 'Neurology Resident'],
  Oncology: ['Head of Oncology', 'Senior Oncologist', 'Oncologist', 'Oncology Nurse', 'Radiation Therapist', 'Oncology Social Worker'],
  Nursing: ['Director of Nursing', 'Head Nurse', 'Charge Nurse', 'Registered Nurse', 'Registered Nurse', 'Practical Nurse', 'Nursing Assistant', 'Nurse Educator', 'Clinical Nurse Specialist'],
  Laboratory: ['Laboratory Manager', 'Senior Lab Scientist', 'Medical Lab Scientist', 'Lab Technician', 'Phlebotomist', 'Pathology Assistant'],
  Imaging: ['Head of Imaging', 'Senior Radiologist', 'Radiologist', 'Radiographer', 'MRI Technologist', 'CT Technologist', 'Ultrasound Technician'],
  Admissions: ['Admissions Manager', 'Admissions Supervisor', 'Admissions Clerk', 'Patient Registration Clerk', 'Bed Management Coordinator', 'Front Desk Representative'],
  Finance: ['Finance Manager', 'Senior Accountant', 'Accountant', 'Billing Specialist', 'Payroll Specialist', 'Procurement Officer'],
  IT: ['IT Manager', 'Systems Administrator', 'Network Engineer', 'Help Desk Technician', 'Clinical Applications Analyst', 'Security Analyst'],
  Facilities: ['Facilities Manager', 'Maintenance Supervisor', 'Electrician', 'HVAC Technician', 'Maintenance Technician', 'Housekeeping Supervisor'],
};
const users = cur.users.filter((u) => /^esther-[a-z]+-\d{3}@/i.test(u.userPrincipalName)).sort((a, b) => a.userPrincipalName.localeCompare(b.userPrincipalName));
const num = (u) => +u.userPrincipalName.match(/-(\d{3})@/)[1];
const mapDept = (d) => cfg.rename[d] || d;
const depts = Object.keys(cfg.allocation);
const by = Object.fromEntries(depts.map((d) => [d, []])); const pool = [];
for (const d of depts) {
  const inDept = users.filter((u) => mapDept(u.department) === d).sort((a, b) => num(a) - num(b));
  by[d].push(...inDept.slice(0, cfg.allocation[d])); pool.push(...inDept.slice(cfg.allocation[d]));
}
pool.sort((a, b) => num(a) - num(b));
for (const d of depts) while (by[d].length < cfg.allocation[d] && pool.length) by[d].push(pool.shift());
const total = depts.reduce((n, d) => n + by[d].length, 0);
if (pool.length || total !== users.length) throw new Error(`allocation mismatch: ${total} placed, ${pool.length} left, ${users.length} users`);
const ceo = by.Administration[0];
const out = []; const newUpn = new Map(); const taken = new Set();
for (const u of users) {
  const [f, ...rest] = u.displayName.trim().toLowerCase().split(/\s+/); let base = `${f}.${rest.join('')}`.replace(/[^a-z.]/g, ''); let cand = base; let i = 2;
  while (taken.has(cand)) cand = `${base}${i++}`; taken.add(cand); newUpn.set(u.id, cand + SUFFIX);
}
for (const d of depts) by[d].forEach((u, i) => {
  const head = by[d][0]; const t = TITLES[d];
  out.push({ id: u.id, userPrincipalName: u.userPrincipalName, displayName: u.displayName, department: d,
    jobTitle: i === 0 ? t[0] : t[1 + ((i - 1) % (t.length - 1))],
    manager: u.id === ceo.id ? null : i === 0 ? ceo.userPrincipalName : head.userPrincipalName });
});
const groups = depts.map((d) => {
  const old = Object.entries(cfg.rename).find(([, v]) => v === d)?.[0] || d;
  const g = cur.groups.find((x) => x.displayName === PREFIX + old); if (!g) throw new Error('missing group ' + old);
  return { id: g.id, displayName: PREFIX + d, exclusive: true, members: by[d].map((u) => u.userPrincipalName) };
});
const stage1 = { upnSuffix: SUFFIX, users: out, groups };
const re = (upn) => { const u = users.find((x) => x.userPrincipalName === upn); return u ? newUpn.get(u.id) : upn; };
const stage2 = { upnSuffix: SUFFIX, users: out.map((u) => ({ ...u, userPrincipalName: re(u.userPrincipalName), manager: u.manager && re(u.manager) })), groups: groups.map((g) => ({ ...g, members: g.members.map(re) })) };
fs.writeFileSync('desired-state/state.json', JSON.stringify(stage1, null, 2) + '\n');
fs.mkdirSync('proposals', { recursive: true }); fs.writeFileSync('proposals/stage2-upn-state.json', JSON.stringify(stage2, null, 2) + '\n');
console.log(JSON.stringify({ users: out.length, managerLinks: out.filter((u) => u.manager).length, perDept: Object.fromEntries(depts.map((d) => [d, by[d].length])), distinctTitles: new Set(out.map((u) => u.jobTitle)).size, moved: out.filter((u) => mapDept(users.find((x) => x.id === u.id).department) !== u.department).length }));
