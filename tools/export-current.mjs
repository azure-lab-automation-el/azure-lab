// Read-only export of current Entra users/groups (managed suffix) to current.json.
import fs from 'node:fs'; import { readCurrent } from './plan.mjs';
const suffix = JSON.parse(fs.readFileSync('desired-state/state.json', 'utf8')).upnSuffix;
const cur = await readCurrent(process.env.GRAPH_TOKEN, suffix);
fs.writeFileSync('current.json', JSON.stringify({ generatedAt: new Date().toISOString(), ...cur }, null, 2));
console.log(JSON.stringify({ users: cur.users.length, groups: cur.groups.length, managerLinks: cur.users.filter((u) => u.manager).length }));
