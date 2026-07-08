#!/usr/bin/env node
/**
 * Generic multi-turn Agentforce test harness — RUNTIME Agent API.
 *
 * Drives a PUBLISHED + ACTIVATED Agentforce agent through CSV-defined multi-turn
 * conversations using the real runtime Agent API gateway
 * (https://api.salesforce.com/einstein/ai-agent/v1), and writes the agent's actual
 * responses/outcomes back into the SAME CSV. One runtime session per case_id; turns
 * sent in order.
 *
 * Unlike run_preview_tests.mjs (which drives `sf agent preview`, an ephemeral path
 * invisible to org analytics) and run_agent_tests.mjs (which uses the @salesforce/agents
 * SDK and the CLI user's auth), this harness authenticates via the OAuth
 * **client_credentials** flow against a Connected App / External Client App. The
 * resulting sessions are REAL runtime sessions and appear in the SIA / Agentforce
 * analytics console. This is also why it works where the CLI-user Agent API path is
 * blocked by a permission-set-license gap (a permission-set-license gap on the running user).
 *
 * ---------------------------------------------------------------------------------
 * PREREQUISITES (one-time org setup) — see README.md "run_runtime_tests.mjs" section:
 *   1. Agent must be PUBLISHED + ACTIVATED.
 *   2. A Connected App / External Client App with:
 *        - OAuth client_credentials flow enabled (OAuth settings + Policies tab),
 *        - scopes: sfap_api, chatbot_api, api,
 *        - "Issue JWT-based access tokens for named users" enabled,
 *        - a Run-As integration user (API-only access is enough).
 *   3. The agent's BotDefinition Id (0Xx...) — see --agent-id below.
 * ---------------------------------------------------------------------------------
 *
 * Usage:
 *   node run_runtime_tests.mjs \
 *     --csv test-harness/agent_test_cases_gaps50.csv \
 *     --agent-id 0XxXXXXXXXXXXXXXXX \
 *     --my-domain https://MyDomainName.my.salesforce.com \
 *     --client-id   <consumer key>     # or env SF_CLIENT_ID
 *     --client-secret <consumer secret> # or env SF_CLIENT_SECRET
 *
 * Credentials resolve from flags first, then env (SF_CLIENT_ID / SF_CLIENT_SECRET).
 * Put secrets in env, not on the command line, to keep them out of shell history.
 *
 * Options:
 *   --csv <path>          (required) CSV of test cases (read AND rewritten in place).
 *   --agent-id <0Xx...>   (required) The agent's BotDefinition Id.
 *   --my-domain <url>     (required) Org My Domain base, e.g. https://acme.my.salesforce.com.
 *   --client-id <key>     OAuth consumer key      (or env SF_CLIENT_ID).
 *   --client-secret <s>   OAuth consumer secret   (or env SF_CLIENT_SECRET).
 *   --api-base <url>      Agent API gateway base. Default https://api.salesforce.com/einstein/ai-agent/v1.
 *                         For sandboxes that 404, try https://test.api.salesforce.com/einstein/ai-agent/v1.
 *   --delay <ms>          Pause between turns (default 1000).
 *   --match <mode>        expected_response comparison: contains (default) | exact | regex | none.
 *   --dry-run             Parse/validate the CSV and print the plan; no token, no API calls.
 *
 * CSV contract (case-insensitive headers; same family as the other harnesses):
 *   in:  case_id, turn, utterance, [expected_response], [expected_outcome]
 *   out: actual_response, actual_outcome, latency_ms, match, session_id, error, sequence_id
 *
 * Exit code: 0 if all evaluated turns PASS (or no expectations), 1 otherwise.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';

// ---------------------------------------------------------------- args
function parseArgs(argv) {
  const a = { delay: 1000, match: 'contains', dryRun: false, vars: [],
              apiBase: 'https://api.salesforce.com/einstein/ai-agent/v1' };
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    if (k === '--csv') a.csv = argv[++i];
    else if (k === '--agent-id') a.agentId = argv[++i];
    else if (k === '--my-domain') a.myDomain = argv[++i];
    else if (k === '--client-id') a.clientId = argv[++i];
    else if (k === '--client-secret') a.clientSecret = argv[++i];
    else if (k === '--api-base') a.apiBase = argv[++i];
    else if (k === '--scope') a.scope = argv[++i];
    else if (k === '--delay') a.delay = Number(argv[++i]);
    else if (k === '--match') a.match = argv[++i];
    // --var name=value : injected into the session-start variables[] array.
    // The literal "{sessionId}" in a value is substituted with the runtime sessionId
    // (useful for binding a framework session_key to the real session).
    else if (k === '--var') a.vars.push(argv[++i]);
    else if (k === '--dry-run') a.dryRun = true;
  }
  a.clientId = a.clientId || process.env.SF_CLIENT_ID;
  a.clientSecret = a.clientSecret || process.env.SF_CLIENT_SECRET;
  // normalize: strip trailing slashes
  if (a.myDomain) a.myDomain = a.myDomain.replace(/\/+$/, '');
  if (a.apiBase) a.apiBase = a.apiBase.replace(/\/+$/, '');
  return a;
}

// ---------------------------------------------------------------- CSV (RFC-4180-ish)
function parseCsv(text) {
  const rows = []; let row = [], field = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else q = false; }
      else field += c;
    } else if (c === '"') q = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\r') { /* skip */ }
    else if (c === '\n') { row.push(field); rows.push(row); row = []; field = ''; }
    else field += c;
  }
  if (field.length || row.length) { row.push(field); rows.push(row); }
  return rows.filter((r) => !(r.length === 1 && r[0].trim() === ''));
}
function csvEscape(v) {
  const s = v == null ? '' : String(v);
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}
function toCsv(headers, records) {
  const lines = [headers.map(csvEscape).join(',')];
  for (const rec of records) lines.push(headers.map((h) => csvEscape(rec[h.toLowerCase()])).join(','));
  return lines.join('\n') + '\n';
}

// ---------------------------------------------------------------- matching
function evaluateMatch(mode, expected, actual) {
  if (mode === 'none' || !expected || !String(expected).trim()) return '';
  const exp = String(expected), act = String(actual || '');
  try {
    if (mode === 'exact') return act.trim() === exp.trim() ? 'PASS' : 'FAIL';
    if (mode === 'regex') return new RegExp(exp, 'i').test(act) ? 'PASS' : 'FAIL';
    return act.toLowerCase().includes(exp.toLowerCase()) ? 'PASS' : 'FAIL';
  } catch { return 'FAIL'; }
}

// ---------------------------------------------------------------- Agent API client
// Mint an access token via the OAuth client_credentials flow against the org token endpoint.
async function getToken(a) {
  const params = {
    grant_type: 'client_credentials',
    client_id: a.clientId,
    client_secret: a.clientSecret,
  };
  // Narrow the requested scopes; Salesforce client_credentials rejects with
  // "too many scopes requested" when the app grants a broad set and no scope is asked for.
  if (a.scope) params.scope = a.scope;
  const body = new URLSearchParams(params);
  const res = await fetch(`${a.myDomain}/services/oauth2/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok || !json.access_token) {
    throw new Error(`token request failed (${res.status}): ${json.error || ''} ${json.error_description || JSON.stringify(json)}`.trim());
  }
  return json.access_token;
}

function authHeaders(token, extra = {}) {
  return { Authorization: `Bearer ${token}`, 'x-client-name': 'agentforce-runtime-harness', ...extra };
}

// Build the session-start variables[] array from --var name=value flags.
// "{uuid}" in a value is replaced with the supplied unique id (one per case),
// so e.g. --var session_key={uuid} binds the framework session id to this run.
function buildStartVars(a, uniqueId) {
  return (a.vars || []).map((spec) => {
    const eq = spec.indexOf('=');
    const name = eq >= 0 ? spec.slice(0, eq) : spec;
    let value = eq >= 0 ? spec.slice(eq + 1) : '';
    value = value.replace(/\{uuid\}/g, uniqueId);
    return { name, type: 'Text', value };
  });
}

// POST /agents/{agentId}/sessions  -> { sessionId, messages[] }
async function startSession(a, token, externalKey, startVars) {
  const res = await fetch(`${a.apiBase}/agents/${a.agentId}/sessions`, {
    method: 'POST',
    headers: authHeaders(token, { 'Content-Type': 'application/json' }),
    body: JSON.stringify({
      externalSessionKey: externalKey,
      instanceConfig: { endpoint: a.myDomain },
      streamingCapabilities: { chunkTypes: ['Text'] },
      bypassUser: true,
      variables: startVars || [],
    }),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok || !json.sessionId) {
    throw new Error(`session start failed (${res.status}): ${json.message || json[0]?.message || JSON.stringify(json)}`);
  }
  return json.sessionId;
}

// POST /sessions/{sessionId}/messages  -> { messages[] }
async function sendMessage(a, token, sessionId, sequenceId, text) {
  const res = await fetch(`${a.apiBase}/sessions/${sessionId}/messages`, {
    method: 'POST',
    headers: authHeaders(token, { 'Content-Type': 'application/json' }),
    body: JSON.stringify({ message: { sequenceId, type: 'Text', text }, variables: [] }),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(`send failed (${res.status}): ${json.message || json[0]?.message || JSON.stringify(json)}`);
  }
  return json.messages || [];
}

// DELETE /sessions/{sessionId}  (best effort)
async function endSession(a, token, sessionId, reason = 'UserRequest') {
  try {
    await fetch(`${a.apiBase}/sessions/${sessionId}`, {
      method: 'DELETE',
      headers: authHeaders(token, { 'x-session-end-reason': reason }),
    });
  } catch { /* best effort */ }
}

// Reduce an Agent API messages[] to the assistant's textual reply.
// 'Inform' is the normal answer; we also surface Inquire/Confirm/Failure/Escalate text.
function replyText(messages) {
  const TEXTUAL = new Set(['Inform', 'Inquire', 'Confirm', 'Failure', 'Escalate', 'TextChunk']);
  return messages.filter((m) => TEXTUAL.has(m.type) && m.message).map((m) => m.message).join('\n');
}

// ---------------------------------------------------------------- main
const OUTPUT_COLS = ['actual_response', 'actual_outcome', 'latency_ms', 'match', 'session_id', 'error', 'sequence_id'];
const REQUIRED = ['case_id', 'turn', 'utterance'];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const missing = [];
  if (!args.csv) missing.push('--csv');
  if (!args.agentId) missing.push('--agent-id');
  if (!args.myDomain) missing.push('--my-domain');
  if (!args.dryRun && !args.clientId) missing.push('--client-id (or SF_CLIENT_ID)');
  if (!args.dryRun && !args.clientSecret) missing.push('--client-secret (or SF_CLIENT_SECRET)');
  if (missing.length) {
    console.error(`ERROR: missing required: ${missing.join(', ')}. See header docs in run_runtime_tests.mjs.`);
    process.exit(2);
  }

  const raw = parseCsv(readFileSync(args.csv, 'utf8'));
  if (raw.length < 2) { console.error('ERROR: CSV has no data rows.'); process.exit(2); }
  const headerOrig = raw[0].map((h) => h.trim());
  const headerLc = headerOrig.map((h) => h.toLowerCase());
  for (const col of REQUIRED) {
    if (!headerLc.includes(col)) { console.error(`ERROR: required column "${col}" missing.`); process.exit(2); }
  }
  const finalHeaders = [...headerOrig];
  for (const oc of OUTPUT_COLS) if (!headerLc.includes(oc)) finalHeaders.push(oc);

  const records = raw.slice(1).map((cols) => {
    const rec = {};
    finalHeaders.forEach((h) => { rec[h.toLowerCase()] = ''; });
    headerOrig.forEach((h, i) => { rec[h.toLowerCase()] = cols[i] ?? ''; });
    return rec;
  });

  const caseOrder = [];
  const cases = new Map();
  for (const rec of records) {
    const cid = rec['case_id'].trim();
    if (!cid) continue;
    if (!cases.has(cid)) { cases.set(cid, []); caseOrder.push(cid); }
    cases.get(cid).push(rec);
  }
  for (const cid of caseOrder) cases.get(cid).sort((a, b) => (Number(a.turn) || 0) - (Number(b.turn) || 0));

  console.error(`Loaded ${records.length} turns / ${caseOrder.length} cases from ${args.csv}`);
  console.error(`Agent: ${args.agentId} | my-domain: ${args.myDomain} | api-base: ${args.apiBase}`);
  console.error(`match: ${args.match} | delay: ${args.delay}ms`);

  if (args.dryRun) {
    for (const cid of caseOrder) console.error(`  [${cid}] ${cases.get(cid).length} turn(s)`);
    console.error('Dry run — no token minted, no API calls made.');
    return;
  }

  let token;
  try {
    token = await getToken(args);
    console.error('Minted access token via client_credentials.');
  } catch (e) {
    console.error(`FATAL: ${e.message}`);
    process.exit(1);
  }

  let evaluated = 0, passed = 0, errors = 0;

  for (const cid of caseOrder) {
    const turns = cases.get(cid);
    console.error(`\n=== CASE ${cid} (${turns.length} turns) ===`);

    // One unique id per case — used as externalSessionKey and substituted into
    // any --var value containing {uuid} (e.g. --var session_key={uuid}).
    const caseKey = randomUUID();
    const startVars = buildStartVars(args, caseKey);
    let sessionId;
    try {
      sessionId = await startSession(args, token, caseKey, startVars);
    } catch (e) {
      for (const rec of turns) { rec.error = `session start failed: ${e.message}`; errors++; }
      console.error(`  ! ${e.message.slice(0, 180)}`);
      continue;
    }

    let seq = Date.now();
    for (const rec of turns) {
      rec.session_id = sessionId;
      rec.sequence_id = String(seq);
      const t0 = Date.now();
      try {
        const msgs = await sendMessage(args, token, sessionId, seq, rec.utterance ?? '');
        rec.latency_ms = String(Date.now() - t0);
        rec.actual_response = replyText(msgs);
        rec.match = evaluateMatch(args.match, rec.expected_response, rec.actual_response);
        if (rec.match === 'PASS') passed++;
        if (rec.match === 'PASS' || rec.match === 'FAIL') evaluated++;
        console.error(`  turn ${rec.turn}: ${rec.match || '—'} (${rec.latency_ms}ms)`);
      } catch (e) {
        rec.latency_ms = String(Date.now() - t0);
        rec.error = e.message;
        rec.match = rec.expected_response ? 'FAIL' : '';
        if (rec.expected_response) evaluated++;
        errors++;
        console.error(`  turn ${rec.turn}: ERROR ${String(e.message).slice(0, 140)}`);
      }
      seq++;
      if (args.delay) await new Promise((r) => setTimeout(r, args.delay));
    }

    await endSession(args, token, sessionId);
  }

  writeFileSync(args.csv, toCsv(finalHeaders, records));
  console.error(`\nWrote results back to ${args.csv}`);
  console.error(`Summary: ${passed}/${evaluated} expectations PASSED, ${errors} error(s).`);
  process.exit(errors === 0 && passed === evaluated ? 0 : 1);
}

main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
