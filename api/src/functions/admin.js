'use strict';
// Admin console: activity log (workflow runs, change requests, commits) bundled at deploy by tools/build-audit-log.mjs.
// Read-only. Admins and approvers only; the help desk role does not see it.
const { app } = require('@azure/functions');
const fs = require('fs'); const path = require('path');
const { requireAdmin, inventory } = require('../lib');
const read = (f, d) => { try { return JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', f), 'utf8')); } catch { return d; } };
app.http('adminLog', { route: 'admin/log', methods: ['GET'], authLevel: 'anonymous', handler: async (request) => {
  const { me, deny } = await requireAdmin(request); if (deny) return deny;
  if (me.helpdesk) return { status: 403, jsonBody: { error: 'The help desk role cannot open the admin console' } };
  const log = read('audit-log.json', { generatedAt: null, events: [], workflows: [] });
  const inv = inventory();
  const m = read('metrics.json', {});
  return { jsonBody: { ...log, cost: m.cost || null, vms: m.vms || [], directory: { generatedAt: inv.generatedAt, users: inv.users.length, disabled: inv.users.filter((u) => u.accountEnabled === false).length, groups: inv.groups.length } } };
} });
app.http('adminScheduled', { route: 'admin/scheduled', methods: ['GET'], authLevel: 'anonymous', handler: async (request) => {
  const { me, deny } = await requireAdmin(request); if (deny) return deny;
  if (me.helpdesk) return { status: 403, jsonBody: { error: 'The help desk role cannot open scheduled tasks' } };
  const cfg = read('config/schedules.json', { tasks: [] }); const gr = read('config/group-rules.json', { rules: [] }); const rep = read('scheduled-report.json', { generatedAt: null, tasks: [] });
  return { jsonBody: { schedule: 'nightly 01:17 UTC (esther-scheduled)', mode: 'dry-run', tasks: cfg.tasks, groupRules: gr.rules, report: rep } };
} });
