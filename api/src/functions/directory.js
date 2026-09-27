'use strict';
const { app } = require('@azure/functions');
const { inventory, requireAdmin, policy, templates } = require('../lib');
app.http('me', { methods: ['GET'], authLevel: 'anonymous', handler: async (request) => {
  const { me, deny } = await requireAdmin(request); if (deny) return deny;
  return { jsonBody: { ...me, policy: policy(), templates: templates() } };
} });
app.http('directory', { methods: ['GET'], authLevel: 'anonymous', handler: async (request) => {
  const { deny } = await requireAdmin(request); if (deny) return deny;
  const inv = inventory();
  return { jsonBody: { generatedAt: inv.generatedAt, users: inv.users, groups: inv.groups } };
} });
