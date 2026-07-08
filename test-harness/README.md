# Generic Agentforce Multi-Turn Test Harness

`run_agent_tests.mjs` drives **any activated Agentforce agent** through CSV-defined
multi-turn conversations and writes the agent's **actual responses/outcomes back into
the same CSV**. It uses the Salesforce CLI's bundled `@salesforce/agents` runtime
(the same engine as `sf agent preview`), so one Agent API session is opened per case
and turns are sent in order.

## Usage

```bash
node test-harness/run_agent_tests.mjs \
  --csv test-harness/agent_test_cases_sample.csv \
  --agent <AgentApiNameOrId> \
  --org <orgAlias>
```

| Flag | Required | Default | Meaning |
|------|----------|---------|---------|
| `--csv <path>` | yes | — | Test-case CSV (read **and** rewritten in place). |
| `--agent <name\|id>` | yes | — | Agent API name or BotDefinition Id. |
| `--org <alias>` | no | CLI default org | Target org. |
| `--delay <ms>` | no | `1000` | Pause between turns. |
| `--match <mode>` | no | `contains` | `contains` \| `exact` \| `regex` \| `none` — how `expected_response` is compared to the reply. |
| `--dry-run` | no | — | Parse/validate the CSV and print the plan; no org calls. |

Exit code `0` if every evaluated turn PASSes (or there are no expectations), else `1`.

## CSV column contract

Header row, **case-insensitive**, order-independent.

**Required input**
- `case_id` — groups turns into one conversation/session.
- `turn` — 1-based turn order within the case (sorted numerically).
- `utterance` — the user message to send on this turn.

**Optional input**
- `expected_response` — substring/exact/regex expected in the agent reply (per `--match`).
- `expected_outcome` — free-text expected outcome (for human/diff review; not auto-compared).

**Written by the harness** (columns auto-appended if absent)
- `actual_response` — the agent's reply text for the turn.
- `actual_outcome` — blank by default (reserved for outcome derivation).
- `latency_ms` — round-trip time for the turn.
- `match` — `PASS` / `FAIL` / empty (vs `expected_response`).
- `session_id` — Agent API session id used for the case.
- `error` — any error encountered on the turn.

### Minimal example

```csv
case_id,turn,utterance,expected_response,expected_outcome
share,1,How do I share a sheet with my team?,share,resolved
share,2,Thanks that worked,,resolved
```

After a run, the same file gains `actual_response,actual_outcome,latency_ms,match,session_id,error`
populated for each row.

## Files

- `run_agent_tests.mjs` — the generic harness (agent-agnostic).
- `run_preview_tests.mjs` — CLI live-preview sibling (see below).
- `run_runtime_tests.mjs` — runtime Agent API harness (see below).
- `agent_test_cases_sample.csv` — a small placeholder conversation set (password
  reset / billing / escalation). Use as a starting template or replace with your own.

## Prerequisites

- Salesforce CLI installed and the target org authorized (`sf org login`).
- The agent must be **published and activated** in the target org.
- The **running user must be authorized for the Agentforce Agent API**. If you see
  *"Unable to access the Salesforce Agent APIs…"*, grant that user Agent API access in
  the org — the harness records the error per turn and continues rather than crashing.

---

## run_preview_tests.mjs — live CLI preview harness

`run_preview_tests.mjs` is the CLI-driven sibling of `run_agent_tests.mjs`. Instead of the
`@salesforce/agents` SDK runtime API, it drives **live preview sessions** via the Salesforce CLI
`sf agent preview start | send | end` subcommands (the `/einstein/ai-agent/v1.1/preview/`
endpoint). Use it when the preview endpoint is reachable but the runtime Agent API isn't.

It opens one preview session per `case_id`, sends each turn's `utterance` in order, and writes
the agent's actual replies back into the **same CSV**. It also captures the per-turn `plan_id`
(for trace analysis under `.sfdx/agents/<id>/sessions/<sid>/traces/<planId>.json`).

### Usage

```bash
# Against a published + activated agent (recommended):
node test-harness/run_preview_tests.mjs \
  --csv test-harness/agent_test_cases_sample.csv \
  --agent <AgentApiName> \
  --org <orgAlias>

# Against a local authoring bundle (no publish needed), pick a mode:
node test-harness/run_preview_tests.mjs \
  --csv ... --authoring-bundle <AuthoringBundleName> \
  --mode simulate   # or: --mode live   (live executes real Flows/Apex)
```

| Flag | Required | Default | Meaning |
|------|----------|---------|---------|
| `--csv <path>` | yes | — | Test-case CSV (read **and** rewritten in place). |
| `--agent <apiName>` | one of | — | Published + activated agent API name (`--api-name`). |
| `--authoring-bundle <name>` | one of | — | Local authoring bundle (`--authoring-bundle`). |
| `--mode simulate\|live` | no | `simulate` | Only with `--authoring-bundle`: simulate vs. execute real actions. |
| `--org <alias>` | no | CLI default | Target org. |
| `--delay <ms>` | no | `1000` | Pause between turns. |
| `--match contains\|exact\|regex\|none` | no | `contains` | How `expected_response` is compared. |
| `--dry-run` | no | — | Validate the CSV and print the plan; no CLI calls. |

### CSV contract

Same as `run_agent_tests.mjs`, plus one extra output column `plan_id`:
- in:  `case_id, turn, utterance, [expected_response], [expected_outcome]`
- out: `actual_response, actual_outcome, latency_ms, match, session_id, error, plan_id`

### Notes

- Each preview turn takes ~15–25s (real LLM round-trip). A 50-case run is long — consider
  running in the background or splitting the CSV.
- `--api-name` requires the agent to be published **and activated** in the org.
- This path uses the **preview** endpoint, which (in this org) is reachable even though the
  runtime Agent API used by `run_agent_tests.mjs` is blocked by a permission-set-license gap.
- This harness exercises the agent's real planner/topic-routing/actions — including the
  self-learning Flows when run with `--use-live-actions` against the published agent.
- **For trace/variable verification, run with `--authoring-bundle`, not `--api-name`.** Published-agent
  (`--api-name`) preview writes empty `{}` trace files and returns reply text only — no actions or
  variable transitions. `--authoring-bundle` compiles the local `.agent` (byte-identical to the
  activated version after a fresh publish) and writes full traces to
  `.sfdx/agents/<name>/sessions/<sid>/traces/<planId>.json`. Use `--mode live` to also fire real Flows;
  then confirm any record side effects against org data.
- CLI quirk (≤ 2.133.x): the action-mode flag (`--use-live-actions`/`--simulate-actions`) is accepted on
  `sf agent preview start` **only** — passing it to `send` errors with "Nonexistent flag".

### Diagnostic Pattern: Detect Skipped Actions from Traces (Field-Verified, 2026-06-22)

**Full traces expose control-flow defects:** Extract `FunctionStep` invocations from traces to see which actions the planner actually invoked. Compare against `EnabledToolsStep` to find actions that were available but the LLM chose NOT to call.

**Example: Self-Learning Loop Gap**
```bash
# Turn 1: Load_Improvement_Context fires, but set_knowledge_outcome doesn't
jq '.plan[] | select(.type == "FunctionStep") | .function.name' trace.json
# Output: Load_Improvement_Context, AQWK_KnowledgeCollection
# Missing: set_knowledge_outcome (was available in EnabledToolsStep but not invoked)

# Root cause check in .agent file:
# WRONG (skippable): |After answering, set {!@actions.set_knowledge_outcome}: ...
# RIGHT (guaranteed): run @actions.set_knowledge_outcome with ...
```

When a critical action doesn't fire but was available to invoke, check if it's wired as optional prose (`|Call {!@actions.X}`) instead of deterministic (`run @actions.X`). Prose directives are suggestions the LLM can skip; deterministic calls always execute.

This is faster than Apex-harness testing for **diagnosis** (tell you *what* and *why*), but Apex harness still needed to **verify** the underlying Flows work once you fix the wiring.

---

## run_runtime_tests.mjs — real runtime Agent API harness (console-visible sessions)

`run_runtime_tests.mjs` is the one that produces **real runtime sessions visible in the
SIA / Agentforce analytics console**. The other two harnesses do not:

| Harness | Path it drives | Auth | Console-visible sessions? | Full trace logs (actions/variables)? |
|---------|----------------|------|---------------------------|----------------------------------------|
| `run_agent_tests.mjs` | `@salesforce/agents` SDK | CLI user | needs runtime Agent API access on the running user | **No** — reply text only (`result: []`) |
| `run_preview_tests.mjs` `--api-name` | `sf agent preview` (`/preview/`) | CLI user | **No** — ephemeral | **No** — published-agent traces are empty `{}` (~2 bytes) |
| `run_preview_tests.mjs` `--authoring-bundle` | `sf agent preview` (local compile) | CLI user | **No** — ephemeral | **YES** — 141–634 KB/turn: topic routing, enabled tools, per-variable before→after |
| **`run_runtime_tests.mjs`** | **Runtime Agent API** (`api.salesforce.com/einstein/ai-agent/v1`) | **Connected App (client_credentials)** | **Yes** | No (reply text only) |

> **Trace-visibility rule (field-verified, 2026-06-22, G05 on v8):** the **only** path that emits a
> populated execution trace is `run_preview_tests.mjs --authoring-bundle` (i.e. `sf agent preview
> --authoring-bundle`). Every other path — `--api-name`, the `@salesforce/agents` SDK harness, and the
> runtime Agent API — returns the **reply text only** (`result: []`, `metrics: {}`, empty `{}` trace
> files). To verify *responses + actions + variables* for a test, use `--authoring-bundle` against the
> same local `.agent` that was published (byte-identical to the activated version). To also write org
> side effects (e.g. self-learning lessons), add `--mode live` / `--use-live-actions` on session start,
> and confirm the records in the org (`AgentLessonLearned__c` etc.) since trace-visible variable moves
> alone don't prove a Flow wrote a row.

It opens one runtime session per `case_id` via the Agent API gateway, sends each turn,
and writes replies back into the **same CSV**. Because it authenticates with a Connected
App's client-credentials grant (an integration user, not the CLI user), it sidesteps the
permission-set-license gap that can block the SDK path in some orgs.

### One-time org setup (prerequisites)

1. **Publish + activate** the agent.
2. Create a **Connected App / External Client App** (Setup → External Client Apps Manager → New):
   - Enable OAuth; add scopes **`sfap_api`**, **`chatbot_api`**, **`api`** (+ `refresh_token, offline_access`).
   - Enable the **Client Credentials Flow** (OAuth settings *and* the Policies tab).
   - Enable **"Issue JSON Web Token (JWT)-based access tokens for named users."**
   - Deselect "Require secret for Web Server Flow", "…Refresh Token Flow", and "Require PKCE".
   - On **Policies**, set **Run As** to an integration user with API access.
3. Note the **consumer key/secret** and the agent's **BotDefinition Id** (`0Xx…`):
   `sf data query --json -q "SELECT Id, DeveloperName FROM BotDefinition WHERE DeveloperName = '<AgentApiName>'"`

### Usage

```bash
export SF_CLIENT_ID='<consumer key>'
export SF_CLIENT_SECRET='<consumer secret>'

node test-harness/run_runtime_tests.mjs \
  --csv test-harness/agent_test_cases_sample.csv \
  --agent-id 0XxXXXXXXXXXXXXXXX \
  --my-domain https://MyDomainName.my.salesforce.com
```

| Flag | Required | Default | Meaning |
|------|----------|---------|---------|
| `--csv <path>` | yes | — | Test-case CSV (read **and** rewritten in place). |
| `--agent-id <0Xx…>` | yes | — | Agent's BotDefinition Id. |
| `--my-domain <url>` | yes | — | Org My Domain base (`https://<domain>.my.salesforce.com`). |
| `--client-id <key>` | yes | env `SF_CLIENT_ID` | OAuth consumer key. |
| `--client-secret <s>` | yes | env `SF_CLIENT_SECRET` | OAuth consumer secret. |
| `--api-base <url>` | no | `https://api.salesforce.com/einstein/ai-agent/v1` | Gateway base. Sandboxes that 404 may need `https://test.api.salesforce.com/einstein/ai-agent/v1`. |
| `--delay <ms>` | no | `1000` | Pause between turns. |
| `--match <mode>` | no | `contains` | `contains` \| `exact` \| `regex` \| `none`. |
| `--dry-run` | no | — | Validate CSV and print the plan; no token, no API calls. |

### CSV contract

Same as the others, plus one extra output column `sequence_id`:
- in:  `case_id, turn, utterance, [expected_response], [expected_outcome]`
- out: `actual_response, actual_outcome, latency_ms, match, session_id, error, sequence_id`

### How it works (the request flow)

1. **Token** — `POST https://<my-domain>/services/oauth2/token` with
   `grant_type=client_credentials` → JWT access token.
2. **Start session** — `POST {api-base}/agents/{agent-id}/sessions` with
   `instanceConfig.endpoint = <my-domain>`, `bypassUser: true`, random `externalSessionKey`
   → `sessionId`.
3. **Per turn** — `POST {api-base}/sessions/{sessionId}/messages` with an incrementing
   `sequenceId`; the reply text is taken from `messages[]` of type `Inform`/`Inquire`/
   `Confirm`/`Failure`/`Escalate`.
4. **End** — `DELETE {api-base}/sessions/{sessionId}` with header `x-session-end-reason: UserRequest`.

### Notes

- Keep the consumer secret in `SF_CLIENT_SECRET` (env), not on the command line.
- If session start returns 404, the org likely routes through the sandbox gateway —
  retry with `--api-base https://test.api.salesforce.com/einstein/ai-agent/v1`.
- "Agentforce (Default)" agents are **not** supported by the Agent API; use the
  custom/standard Agentforce agent.
- Requires Node 18+ (uses built-in global `fetch`). No npm install needed.
- The harness also accepts `--var name=value` (repeatable) for session-start
  variables. The literal token `{uuid}` in a value is replaced with a unique
  per-case id (e.g. `--var session_key={uuid}`). Note: agent-internal `mutable`
  variables reject external mutation and will fail session start with
  `InternalVariableMutationAttemptException` — this option is for genuine
  input-bound variables only.

---

## Self-learning lesson selection (Apex-backed)

The agent's `Load_Improvement_Context` action surfaces relevant lessons via the
self-learning framework. Stage-2 selection lives in
`force-app/main/default/classes/SelectRelevantLessons.cls` (replaces the older
loop-and-prompt-template logic that previously sat inside the
`Check_Lessons_Learned` flow).

Pipeline:

1. **Stage 1 — pool.** SOQL `AgentLessonLearned__c` filtered by `agent_api_name`,
   `topic_area`, `confidence_score__c >= min_confidence`, `is_archived = false`,
   ordered DESC by confidence, capped by SOQL `LIMIT :poolSize` (from
   `AgentImprovementConfig__c.lesson_selection_pool_size__c`, default 20).
2. **Stage 2 — semantic rank.** Calls prompt template `Select_Relevant_Lessons`
   via `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate`, with
   `body.isPreview = false` (required — omitting it triggers a platform NPE on
   `getPreviewOnly()`). The PT picks the most-relevant lessons for the user
   message; the parser hard-caps the result at `max_lessons` (passed in by the
   parent `Load_Improvement_Context` flow, default 5).
3. **Fallback.** If the PT returns null, blank, or unparsable JSON, the Apex
   degrades gracefully to top-N by confidence — same cap, never a 32-lesson dump.

The `Check_Lessons_Learned` flow is now a one-step wrapper that calls
`SelectRelevantLessons` (action type `apex`). Its prior body
(`Get_Config`/`Get_Lessons`/`Loop_Lessons`/`Apply_Stage2_Results`) and the
`LessonRelevanceParser.cls` companion are now superseded — the parser file is
left in the repo dormant for now and can be deleted once everyone is on the
new flow.

Required perms on the agent runtime user (`default_agent_user`):
`EinsteinGPTPromptTemplateUser` (and ideally `EinsteinGPTPromptTemplateManager`).

Tests: `SelectRelevantLessons_Test.cls` covers empty pool, pool cap + max-lessons
fallback, default config, and min-confidence filtering. Run with:

```bash
sf apex run test --target-org <alias> --class-names SelectRelevantLessons_Test \
  --result-format human --synchronous --code-coverage
```
