#!/usr/bin/env node
/**
 * Generic multi-turn Agentforce test harness.
 *
 * Drives any activated Agentforce agent through CSV-defined multi-turn
 * conversations and writes the agent's actual responses/outcomes back into the
 * SAME CSV (in place). One Agent API session per case; turns sent in order.
 *
 * Usage:
 *   node run_agent_tests.mjs --csv <file.csv> --agent <ApiNameOrId> --org <alias> [options]
 *
 * Options:
 *   --csv <path>        (required) CSV of test cases (see column contract below).
 *   --agent <name|id>   (required) Agent API name or BotDefinition Id.
 *   --org <alias>       Target org alias/username. Defaults to the CLI default org.
 *   --delay <ms>        Pause between turns (default 1000).
 *   --match <mode>      Expected-vs-actual comparison: 'contains' (default),
 *                       'exact', 'regex', or 'none'.
 *   --dry-run           Parse/validate the CSV and print the plan; do not call the org.
 *
 * CSV column contract (header row, case-insensitive; order-independent):
 *   Required input:
 *     case_id            Groups turns into one conversation/session.
 *     turn               1-based turn order within the case (integer).
 *     utterance          The user message to send on this turn.
 *   Optional input:
 *     expected_response  Substring/exact/regex expected in the agent reply.
 *     expected_outcome   Free-text expected outcome (for human/diff review).
 *   Written by the harness (created if absent):
 *     actual_response    The agent's reply text for this turn.
 *     actual_outcome     Blank by default (reserved for outcome derivation).
 *     latency_ms         Round-trip time for the turn.
 *     match              PASS / FAIL / '' (vs expected_response, per --match).
 *     session_id         Agent API session id used for the case.
 *     error              Any error encountered on this turn.
 *
 * Exit code: 0 if all evaluated turns PASS (or no expectations), 1 otherwise.
 */
import { readFileSync, writeFileSync } from 'node:fs';

// ---------------------------------------------------------------- arg parsing
function parseArgs(argv) {
  const a = { delay: 1000, match: 'contains', dryRun: false };
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    if (k === '--csv') a.csv = argv[++i];
    else if (k === '--agent') a.agent = argv[++i];
    else if (k === '--org') a.org = argv[++i];
    else if (k === '--delay') a.delay = Number(argv[++i]);
    else if (k === '--match') a.match = argv[++i];
    else if (k === '--dry-run') a.dryRun = true;
  }
  return a;
}

// ---------------------------------------------------------------- CSV (RFC-4180-ish)
function parseCsv(text) {
  const rows = [];
  let row = [], field = '', inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; }
        else inQuotes = false;
      } else field += c;
    } else if (c === '"') inQuotes = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\r') { /* ignore */ }
    else if (c === '\n') { row.push(field); rows.push(row); row = []; field = ''; }
    else field += c;
  }
  // trailing field/row (no final newline)
  if (field.length > 0 || row.length > 0) { row.push(field); rows.push(row); }
  // drop fully-empty trailing rows
  return rows.filter((r) => !(r.length === 1 && r[0].trim() === ''));
}

function csvEscape(v) {
  const s = v == null ? '' : String(v);
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function toCsv(headers, records) {
  const lines = [headers.map(csvEscape).join(',')];
  for (const rec of records) lines.push(headers.map((h) => csvEscape(rec[h])).join(','));
  return lines.join('\n') + '\n';
}

// ---------------------------------------------------------------- matching
function evaluateMatch(mode, expected, actual) {
  if (mode === 'none' || !expected || !String(expected).trim()) return '';
  const exp = String(expected);
  const act = String(actual || '');
  try {
    if (mode === 'exact') return act.trim() === exp.trim() ? 'PASS' : 'FAIL';
    if (mode === 'regex') return new RegExp(exp, 'i').test(act) ? 'PASS' : 'FAIL';
    // default: contains (case-insensitive)
    return act.toLowerCase().includes(exp.toLowerCase()) ? 'PASS' : 'FAIL';
  } catch {
    return 'FAIL';
  }
}

// ---------------------------------------------------------------- main
const OUTPUT_COLS = ['actual_response', 'actual_outcome', 'latency_ms', 'match', 'session_id', 'error'];
const REQUIRED = ['case_id', 'turn', 'utterance'];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.csv || !args.agent) {
    console.error('ERROR: --csv and --agent are required. See header docs in run_agent_tests.mjs.');
    process.exit(2);
  }

  const raw = parseCsv(readFileSync(args.csv, 'utf8'));
  if (raw.length < 2) { console.error('ERROR: CSV has no data rows.'); process.exit(2); }

  // header map (case-insensitive); preserve original header text for rewrite
  const headerOrig = raw[0].map((h) => h.trim());
  const headerLc = headerOrig.map((h) => h.toLowerCase());
  const idx = (name) => headerLc.indexOf(name);
  for (const col of REQUIRED) {
    if (idx(col) < 0) { console.error(`ERROR: required column "${col}" missing from CSV header.`); process.exit(2); }
  }

  // Build the rewrite header: original columns + any missing output columns appended.
  const finalHeaders = [...headerOrig];
  for (const oc of OUTPUT_COLS) if (!headerLc.includes(oc)) finalHeaders.push(oc);

  // Parse rows into record objects keyed by lowercased header.
  const records = raw.slice(1).map((cols) => {
    const rec = {};
    finalHeaders.forEach((h) => { rec[h.toLowerCase()] = ''; });
    headerOrig.forEach((h, i) => { rec[h.toLowerCase()] = cols[i] ?? ''; });
    return rec;
  });

  // Group into cases, preserving first-seen case order; sort turns numerically.
  const caseOrder = [];
  const cases = new Map();
  for (const rec of records) {
    const cid = rec['case_id'].trim();
    if (!cid) continue;
    if (!cases.has(cid)) { cases.set(cid, []); caseOrder.push(cid); }
    cases.get(cid).push(rec);
  }
  for (const cid of caseOrder) {
    cases.get(cid).sort((a, b) => (Number(a.turn) || 0) - (Number(b.turn) || 0));
  }

  console.error(`Loaded ${records.length} turns across ${caseOrder.length} cases from ${args.csv}`);
  console.error(`Agent: ${args.agent} | org: ${args.org || '(default)'} | match: ${args.match} | delay: ${args.delay}ms`);

  if (args.dryRun) {
    for (const cid of caseOrder) {
      console.error(`  [${cid}] ${cases.get(cid).length} turn(s)`);
    }
    console.error('Dry run — no org calls made.');
    return;
  }

  // -------- connect using the CLI's own bundled libraries (same path as sf agent preview)
  const CLI = process.env.SF_LIB_BASE
    || `${process.env.HOME}/.local/share/sf/client/current/node_modules`;
  const { Org } = await import(`${CLI}/@salesforce/core/lib/index.js`);
  const { ProductionAgent } = await import(`${CLI}/@salesforce/agents/lib/index.js`);

  const org = await Org.create(args.org ? { aliasOrUsername: args.org } : {});
  const connection = org.getConnection();

  let totalEvaluated = 0, totalPass = 0, totalErrors = 0;

  for (const cid of caseOrder) {
    const turns = cases.get(cid);
    console.error(`\n=== CASE ${cid} (${turns.length} turns) ===`);
    let sessionId = '';
    let agent;
    try {
      agent = new ProductionAgent({ connection, apiNameOrId: args.agent });
      const start = await agent.startPreview(false);
      sessionId = start?.sessionId || '';
    } catch (e) {
      // Whole case fails to start — mark every turn.
      for (const rec of turns) { rec.error = `session start failed: ${e.message}`; totalErrors++; }
      console.error(`  ! session start failed: ${e.message}`);
      continue;
    }

    for (const rec of turns) {
      rec.session_id = sessionId;
      const utterance = rec.utterance ?? '';
      const t0 = Date.now();
      try {
        const resp = await agent.sendMessage(utterance);
        const text = (resp?.messages || []).map((m) => m.message).filter(Boolean).join('\n');
        rec.actual_response = text;
        rec.latency_ms = String(Date.now() - t0);
        rec.match = evaluateMatch(args.match, rec.expected_response, text);
        if (rec.match === 'PASS') totalPass++;
        if (rec.match === 'PASS' || rec.match === 'FAIL') totalEvaluated++;
        console.error(`  turn ${rec.turn}: ${rec.match || '—'} (${rec.latency_ms}ms)`);
      } catch (e) {
        rec.error = e.message;
        rec.latency_ms = String(Date.now() - t0);
        rec.match = rec.expected_response ? 'FAIL' : '';
        if (rec.expected_response) totalEvaluated++;
        totalErrors++;
        console.error(`  turn ${rec.turn}: ERROR ${e.message}`);
      }
      if (args.delay) await new Promise((r) => setTimeout(r, args.delay));
    }

    try { await agent.endSession('UserRequest'); } catch { /* best effort */ }
  }

  // -------- write results back into the SAME csv
  writeFileSync(args.csv, toCsv(finalHeaders, records));
  console.error(`\nWrote results back to ${args.csv}`);
  console.error(`Summary: ${totalPass}/${totalEvaluated} expectations PASSED, ${totalErrors} error(s).`);
  process.exit(totalErrors === 0 && totalPass === totalEvaluated ? 0 : 1);
}

main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
