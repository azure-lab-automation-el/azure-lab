'use strict';
// Metrics feed for SquaredUp (Web API data source). Read-only JSON bundled at deploy by tools/build-metrics.mjs.
// Anonymous route in staticwebapp.config.json, gated by the x-esther-metrics-key header (key bundled at deploy from a GitHub secret).
const { app } = require('@azure/functions');
const fs = require('fs'); const path = require('path'); const crypto = require('crypto');
const f = (n) => path.join(__dirname, '..', '..', n);
const key = () => { try { return fs.readFileSync(f('.metrics-key'), 'utf8').trim(); } catch { return ''; } };
app.http('metrics', { route: 'metrics/{part?}', methods: ['GET'], authLevel: 'anonymous', handler: async (request) => {
  const k = key(); const got = request.headers.get('x-esther-metrics-key') || '';
  if (!k || got.length !== k.length || !crypto.timingSafeEqual(Buffer.from(got), Buffer.from(k))) return { status: 401, jsonBody: { error: 'metrics key required' } };
  let m; try { m = JSON.parse(fs.readFileSync(f('metrics.json'), 'utf8')); } catch { return { status: 503, jsonBody: { error: 'no metrics yet' } }; }
  const part = request.params.part;
  if (part && Object.prototype.hasOwnProperty.call(m, part)) return { jsonBody: m[part] };
  return { jsonBody: m };
} });
