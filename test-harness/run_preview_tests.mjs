#!/usr/bin/env node
/**
 * Generic multi-turn Agentforce test harness — LIVE PREVIEW via the sf CLI.
 *
 * Drives any agent through CSV-defined multi-turn conversations using the
 * `sf agent preview start | send | end` subcommands (the /preview/ endpoint),
 * and writes the agent's actual responses/outcomes back into the SAME CSV.
 * One preview session per case_id; turns sent in order.
 *
 * This is the CLI-driven sibling of run_agent_tests.mjs (which uses the
 * @salesforce/agents SDK runtime API). Use this one when the preview endpoint
 * is reachable but the runtime Agent API isn't.
 *
 * Usage:
 *   node run_preview_tests.mjs --csv <file.csv> --agent <ApiName> --org <alias> [options]
 *
 * Agent source (choose how the preview resolves the agent):
 *   --agent <ApiName>       Published + activated agent (uses `--api-name`).
 *   --authoring-bundle <n>  Local authoring bundle (uses `--authoring-bundle`).
 *                           Requires a mode: --simulate-actions (default) or --use-live-actions.
 *
 * Options:
 *   --org <alias>        Target org alias/username. Defaults to CLI default org.
 *   --mode <mode>        For --authoring-bundle: 'simulate' (default) or 'live'.
 *   --delay <ms>         Pause between turns (default 1000).
 *   --match <mode>       expected_response comparison: contains (default) | exact | regex | none.
 *   --dry-run            Parse/validate the CSV and print the plan; no CLI calls.
 *
 * CSV contract (case-insensitive headers; same as run_agent_tests.mjs):
 *   in:  case_id, turn, utterance, [expected_response], [expected_outcome]
 *   out: actual_response, actual_outcome, latency_ms, match, session_id, error, plan_id
 *
 * Exit code: 0 if all evaluated turns PASS (or no expectations), 1 otherwise.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { execFile } from 'node:child_process';

// ---------------------------------------------------------------- args
function parseArgs(argv) {
  const a = { delay: 1000, match: 'contains', mode: 'simulate', dryRun: false };
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    if (k === '--csv') a.csv = argv[++i];
    else if (k === '--agent') a.agent = argv[++i];
    else if (k === '--authoring-bundle') a.bundle = argv[++i];
    else if (k === '--org') a.org = argv[++i];
    else if (k === '--mode') a.mode = argv[++i];
    else if (k === '--delay') a.delay = Number(argv[++i]);
    else if (k === '--match') a.match = argv[++i];
    else if (k === '--dry-run') a.dryRun = true;
  }
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

// ---------------------------------------------------------------- sf CLI runner
function sf(args) {
  return new Promise((resolve) => {
    execFile('sf', args, { maxBuffer: 1024 * 1024 * 64 }, (err, stdout, stderr) => {
      // sf prints an update-warning to stderr/stdout; strip ANSI and isolate JSON.
      const clean = String(stdout || '').replace(/\x1b\[[0-9;]*m/g, '');
      const start = clean.indexOf('{');
      let json = null;
      if (start >= 0) { try { json = JSON.parse(clean.slice(start)); } catch { /* ignore */ } }
      resolve({ json, err, stderr: String(stderr || '') });
    });
  });
}

// Build the agent-identifying flags shared by start/send/end.
function agentFlags(args) {
  if (args.bundle) {
    const modeFlag = args.mode === 'live' ? '--use-live-actions' : '--simulate-actions';
    return { idFlags: ['--authoring-bundle', args.bundle], startExtra: [modeFlag] };
  }
  return { idFlags: ['--api-name', args.agent], startExtra: [] };
}

const OUTPUT_COLS = ['actual_response', 'actual_outcome', 'latency_ms', 'match', 'session_id', 'error', 'plan_id'];
const REQUIRED = ['case_id', 'turn', 'utterance'];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.csv || (!args.agent && !args.bundle)) {
    console.error('ERROR: --csv and one of --agent / --authoring-bundle are required.');
    process.exit(2);
  }
  const orgFlags = args.org ? ['--target-org', args.org] : [];
  const { idFlags, startExtra } = agentFlags(args);

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

  const agentLabel = args.bundle ? `authoring-bundle:${args.bundle} (${args.mode})` : `api-name:${args.agent}`;
  console.error(`Loaded ${records.length} turns / ${caseOrder.length} cases from ${args.csv}`);
  console.error(`Agent: ${agentLabel} | org: ${args.org || '(default)'} | match: ${args.match} | delay: ${args.delay}ms`);

  if (args.dryRun) {
    for (const cid of caseOrder) console.error(`  [${cid}] ${cases.get(cid).length} turn(s)`);
    console.error('Dry run — no CLI calls made.');
    return;
  }

  let evaluated = 0, passed = 0, errors = 0;

  for (const cid of caseOrder) {
    const turns = cases.get(cid);
    console.error(`\n=== CASE ${cid} (${turns.length} turns) ===`);

    // start
    const startRes = await sf(['agent', 'preview', 'start', ...idFlags, ...startExtra, ...orgFlags, '--json']);
    const sessionId = startRes.json?.result?.sessionId;
    if (!sessionId) {
      const msg = startRes.json?.message || startRes.stderr.replace(/\x1b\[[0-9;]*m/g, '').trim() || 'unknown start error';
      for (const rec of turns) { rec.error = `session start failed: ${msg}`; errors++; }
      console.error(`  ! session start failed: ${msg.slice(0, 160)}`);
      continue;
    }

    for (const rec of turns) {
      rec.session_id = sessionId;
      const t0 = Date.now();
      const sendRes = await sf(['agent', 'preview', 'send',
        '--session-id', sessionId, ...idFlags, '--utterance', rec.utterance ?? '', ...orgFlags, '--json']);
      rec.latency_ms = String(Date.now() - t0);
      const msgs = sendRes.json?.result?.messages || [];
      if (msgs.length) {
        rec.actual_response = msgs.map((m) => m.message).filter(Boolean).join('\n');
        rec.plan_id = msgs[msgs.length - 1].planId || '';
        rec.match = evaluateMatch(args.match, rec.expected_response, rec.actual_response);
        if (rec.match === 'PASS') passed++;
        if (rec.match === 'PASS' || rec.match === 'FAIL') evaluated++;
        console.error(`  turn ${rec.turn}: ${rec.match || '—'} (${rec.latency_ms}ms)`);
      } else {
        rec.error = sendRes.json?.message || 'no message returned';
        rec.match = rec.expected_response ? 'FAIL' : '';
        if (rec.expected_response) evaluated++;
        errors++;
        console.error(`  turn ${rec.turn}: ERROR ${String(rec.error).slice(0, 120)}`);
      }
      if (args.delay) await new Promise((r) => setTimeout(r, args.delay));
    }

    // end (best effort; capture trace path into the first turn's row for reference)
    const endRes = await sf(['agent', 'preview', 'end', '--session-id', sessionId, ...idFlags, ...orgFlags, '--json']);
    const tracesPath = endRes.json?.result?.tracesPath;
    if (tracesPath && turns[0]) turns[0].actual_outcome = turns[0].actual_outcome || `traces:${tracesPath}`;
  }

  writeFileSync(args.csv, toCsv(finalHeaders, records));
  console.error(`\nWrote results back to ${args.csv}`);
  console.error(`Summary: ${passed}/${evaluated} expectations PASSED, ${errors} error(s).`);
  process.exit(errors === 0 && passed === evaluated ? 0 : 1);
}

main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
