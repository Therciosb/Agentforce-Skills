# Progressive Disclosure + Generic Subagent — Design

**Date:** 2026-07-13
**Branch:** `feature/progressive-disclosure-generic-subagent`
**Status:** Approved design, pending implementation plan

---

## 1. Problem & Goal

Today each Agentforce `topic` in `customer_support_skill_demo` hardcodes its own
`instructionNames` in the first `run` of its `reasoning.instructions`, and the agent is
partitioned into several specialized topics (`troubleshooting_support`, `case_management`,
etc.). Adding or reshaping capabilities means editing agent script and republishing.

We want to invert and collapse this:

1. **Progressive disclosure at the router.** `start_agent` (the router) loads only the
   lightweight *headers* of a specified set of candidate skills into its reasoning
   context, decides which skills the user's request actually needs, and writes that
   decision to a variable — **before** routing to a subagent.
2. **One generic subagent.** A single purpose-agnostic subagent loads the skills the
   router selected, injects their composed instructions into its reasoning, and exposes
   the full catalog of business actions as tools. Its behavior for any given turn is
   determined entirely by which skills were loaded.

This keeps the existing CRM-backed load logic (`Agent_Skills_Repo__c` →
`Agent_Skill_Loader` → `Agent_Skill_PromptComposer` → `Agent_Skill_LoadAndCompose`)
intact, adding a thin header-retrieval action alongside it and one narrow, additive
tool-cue rewrite step in the composer (§7.4).

## 2. Non-Goals

- No change to `Agent_Skill_Loader` load logic or `Agent_Skill_LoadAndCompose`
  orchestration. The only composer change is an **additive** tool-cue rewrite/validation
  pass over the already-composed text (§7.4); composition, ordering, and reference
  expansion are unchanged.
- No new fields on `Agent_Skills_Repo__c` (`WhenToUse__c` already exists).
- The existing `customer_support_skill_demo` bundle is left untouched; the modified
  agent ships as a **new** bundle.

## 3. Key Design Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Header = `Name` + `WhenToUse__c` | `WhenToUse__c` is authored for routing ("Use when…"); leanest useful signal. |
| D2 | **No fallback.** `WhenToUse__c` MUST exist. | A candidate skill with blank `WhenToUse__c` is excluded and reported in `missingNames`/`warnings` — never silently substituted with `Description__c`. Headers are a contract. |
| D3 | Candidate list is a **static CSV in a custom variable** | Matches requirement "a list inside a custom variable"; explicit, reviewable. |
| D4 | Generic subagent declares existing support-demo flows + `Render_Data` as tools | Real, testable targets; no throwaway placeholders. |
| D5 | New bundle; LTM two-pass memory kept **optional** | Preserves the committed demo; LTM guarded so a non-LTM org still runs. |
| D6 | **Router loads skills; cascade lives under each skill** | Router selects domain skills from headers and loads only those. Each selected `skill-*` cascades to its `workflow-*` via existing `References__c` (skill→workflow). Role/core load flat — **no** role→skill reference — so selective loading (progressive disclosure) is preserved. |
| D7 | Seed-data corrections are **in scope** | The cascade and header contract require correct `References__c` and populated `WhenToUse__c` in the org. |

## 4. Header Sufficiency Audit (evidence for D1/D2)

All 17 seed records have non-empty, non-trivial `WhenToUse__c` (0 empty, 0 under 30 chars).
The three domain skills partition intent cleanly with no overlap:

| Skill | `WhenToUse__c` |
|-------|----------------|
| `skill-product-information-qa` | Use when user asks about product features, plans, model differences, compatibility, or upgrade paths. |
| `skill-troubleshooting-support` | Use when user has any product troubleshooting need (modem, phone, device). |
| `skill-support-case-management` | Use when user needs a new case, case status check, case update, or case closure. |
| `workflow-escalate-to-human` | Use when troubleshooting does not resolve issue, user requests human, or policy requires escalation. |

**Conclusion:** headers are sufficient for correct routing today. Header quality is an
authoring responsibility as the catalog grows (same governance point the framework
already makes for instruction bodies).

## 5. Reference Cascade — Current State & Required Fixes

The loader (`Agent_Skill_Loader.expandReferencesFromLoaded`) already performs breadth-first
transitive reference expansion (depth ≤ 6) and `LoadAndCompose` runs it by default. **The
mechanism exists; the data has gaps.**

### 5.1 Cascade that works today (skill → workflow)
- `skill-support-case-management` → `workflow-support-case-lifecycle`
- `skill-troubleshooting-support` → 7 `workflow-troubleshooting-*` + `workflow-escalate-to-human`

So when the router selects `skill-troubleshooting-support`, the generic subagent
transitively loads all troubleshooting workflows — no extra wiring needed. This is the
cascade layer the feature relies on, and it is confirmed functional.

### 5.2 Data defects to fix (in scope, D7)

1. **Malformed `References__c` (prose + spaces).** Two records embed sentences in the
   CSV reference field, which the loader splits on commas and treats as (missing) record
   names, polluting `missingNames`:
   - `core-skill-ltmManagement-service-agent`
   - `workflow-support-case-lifecycle` (also has a space after a comma)

   Fix: `References__c` must contain **only** no-spaces record names (repo rule).
   Move any explanatory prose to `Description__c`.

2. **`WhenToUse__c` presence (D2 contract).** All candidate skills already comply; the fix
   is to add a validation/authoring note, not to change data. Any future candidate with a
   blank `WhenToUse__c` is excluded by `HeaderProvider` and surfaced as a warning.

### 5.3 Deliberately NOT added
- **No `role-* → skill-*` reference.** Adding it would make loading the role pull every
  domain skill body, defeating the router's selective loading. Roles load flat.

## 6. Architecture

**Note on Agent Script conventions in THIS repo** (verified against the on-disk bundles
`customer_support_skill_demo.agent` and `render_data_test.agent`): the framework uses
`topic` blocks and `@topic.X` transitions (not `subagent`/`@subagent.`); skill loading is
the **first `run` inside `reasoning.instructions`** (the repo does not use `before_reasoning`);
and an action becomes an LLM-callable **tool only when it is re-exposed under
`reasoning.actions:`** with slot-fill inputs — a bare `topic.actions:` declaration is only
callable deterministically via `run @actions.X`.

```
start_agent agent_router
  ├─ load_skills_init      apex://Agent_Skill_LoadAndCompose   role + core skills (flat) → instruction_bundle_json
  ├─ load_user_memory      apex://LoadAgentMemory              OPTIONAL LTM (guarded)
  ├─ get_skill_headers     apex://Agent_Skill_HeaderProvider   NEW: headers for candidate_skills → skill_headers
  ├─ reasoning
  │     • sees user message + skill_headers
  │     • LLM calls select_skills (@utils.setVariables) → skills_to_load = "<chosen no-spaces CSV>"
  └─ after_reasoning
        • transition to @topic.generic_handler   (runs after the LLM turn, so selection happens first)

topic generic_handler
  ├─ reasoning.instructions (first run): load_skills   apex://Agent_Skill_LoadAndCompose
  │       instructionNames=skills_to_load, existingInstructionBundle=instruction_bundle_json
  │       → instruction_bundle_json (merged), composed_instructions
  │       (each selected skill cascades to its workflows via References__c)
  │     • inject composed_instructions (+ optional agent_memory); prose stays topic-agnostic
  └─ reasoning.actions
        • re-expose ALL business actions as slot-filled tools; the loaded instructions decide which apply
```

### 6.1 New Apex — `Agent_Skill_HeaderProvider`

`@InvocableMethod` label **"Get Skill Headers"**. Reuses the same `Agent_Skills_Repo__c`
query pattern as `Agent_Skill_Loader.loadFromRepo` (filter `Status__c='active'`, same
locale handling), selecting **only** `Name, WhenToUse__c` — no body, no reference expansion.

| Dir | Field | Type | Notes |
|-----|-------|------|-------|
| in  | `skillNames` | String (CSV) | candidate names; no expansion |
| in  | `locale` | String (opt) | default `en-US`, mirrors Loader |
| out | `skillHeaders` | String | one line per skill: `- <Name>: <WhenToUse__c>` |
| out | `headersFound` | Integer | count returned |
| out | `missingNames` | String (CSV) | requested names that were inactive, not found, **or missing `WhenToUse__c`** (D2) |
| out | `warnings` | String | present when any name is missing/excluded |

**No fallback:** a record with blank `WhenToUse__c` is treated as missing.

### 6.2 New / changed variables (new bundle)

```
candidate_skills: mutable string = "skill-product-information-qa,skill-troubleshooting-support,skill-support-case-management"
skill_headers:    mutable string = ""     # set by get_skill_headers
skills_to_load:   mutable string = ""     # set by router reasoning, consumed by generic_handler
# reused unchanged: instruction_bundle_json, composed_instructions, agent_memory + LTM vars
```

### 6.3 Router (`start_agent agent_router`)

- Declares `load_skills_init`, optional `load_user_memory`, and `get_skill_headers`.
- `reasoning.instructions`: run header retrieval (mappings inside the same `run` block,
  per repo rule), present `{!@variables.skill_headers}`, instruct the model to set
  `skills_to_load` (no-spaces CSV) and transition.
- `system.instructions` stays static.

### 6.4 Generic handler topic (`generic_handler`)

- `topic.actions:` declares `load_skills` (LoadAndCompose) plus every business-action
  contract with its `target:` (final list in the implementation plan; e.g. `CreateCase`,
  `CreateEscalationTicket`, `Route_to_ESA`, `Render_Data`, order/support lookups, and the
  `save_context` LTM action). This is the deterministic contract layer.
- Skill loading runs as the **first `run` block inside `reasoning.instructions`** (the repo
  does not use `before_reasoning`): LoadAndCompose with
  `instructionNames=@variables.skills_to_load` and
  `existingInstructionBundle=@variables.instruction_bundle_json`.
- `reasoning.instructions` prose: **minimal and topic-agnostic** — inject
  `composed_instructions` (+ optional `agent_memory`) and a single generic line, e.g. "Use
  the tools available to you as directed by the instructions above." **Do NOT enumerate or
  explain individual tools in the reasoning prose** — each tool's purpose lives in its action
  `description:`, and the loaded skill dictates which tool applies.
- `reasoning.actions:` re-exposes each business action as a slot-filled tool wrapper
  (`create_case: @actions.create_case with subject=...`, etc.). **This re-exposure is what
  makes an action LLM-callable** — a bare `topic.actions:` declaration is deterministic-only
  (callable via `run @actions.X`). This is declaration/plumbing, not topic coupling: the
  prose stays generic. Pattern verified in `render_data_test.agent` and the demo's
  `persist_memory` wrapper.
- Loader's existing topic-scoped pruning (keeps `role-*`/`core-skill-*`, swaps
  `skill-*`/`workflow-*`) means re-entering the topic for a new intent cleanly replaces
  the skill set — supporting multi-intent conversations through one handler.

## 7. Full Review of Seeded Skills + Tool-Name Binding

### 7.1 Why this matters for the generic subagent

Today's instruction bodies reference **other instruction records** ("invoke
`workflow-escalate-to-human`", "Send OTP") but never name the **action tool** the agent
must actually call (`Route_to_ESA`, `SendVerificationEmail`, `CreateCase`). In the current
multi-subagent design that was tolerable because each subagent declared only its own small
tool set. In the **generic subagent**, every action tool is present at once, so the model
must be told — in the instruction text — the exact tool name to invoke. Binding tasks to
concrete tool names is the primary compliance lever of this feature.

**Revision rule:** every actionable step in a skill/workflow body that corresponds to an
available tool MUST reference that tool with the `[[tool:Name]]` indicator (§7.4), e.g.
"…get explicit customer approval, then create the case with `[[tool:CreateCase]]`." The
composer rewrites the indicator to a validated plain-text cue. Instruction-record references
(e.g. "see `workflow-...`") remain for composition/cascade, and are additive to — not a
substitute for — the tool indicator.

### 7.2 Tool inventory (confirmed present, 10 of 55 flows)

`CreateCase`, `CreateEscalationTicket`, `Route_to_ESA`, `GetOrderStatus`,
`FetchSupportHistory`, `TrackShipment`, `FetchAccountData`, `GetProductInfo`,
`SendVerificationEmail`, `Render_Data`. These are the tools the generic subagent declares.

### 7.3 Per-record review (all 17 active seeded records)

Legend: **Header OK** = `WhenToUse__c` present & routing-useful (D2). **Tool binding** = the
tool(s) to reference in-step in `InstructionBody__c` via the `[[tool:<Name>]]` indicator,
which the composer rewrites to a validated plain-text cue (§7.4). **Data fix** =
`References__c`/field corrections. (Tool names shown below are the `<Name>` values that go
inside `[[tool:...]]`.)

#### Roles
| Record | Header | Tool binding to add | Data fix |
|--------|--------|---------------------|----------|
| `role-customer-support-agent` | OK | In "DEPENDENCIES", name tools alongside records: OTP → `SendVerificationEmail`; case lifecycle → `CreateCase`; escalation → `Route_to_ESA` / `CreateEscalationTicket`. | none |

#### Core skills
| Record | Header | Tool binding to add | Data fix |
|--------|--------|---------------------|----------|
| `core-skill-ltmManagement-service-agent` | OK | Replace generic "invoke the save action" with the concrete save action tool name used by the bundle (`save_context`/`SaveAgentContext`). | **`References__c` malformed** — strip the prose sentence; keep only real record names (or empty). Move prose to `Description__c`. |
| `core-skill-user-otp-authentication` | OK | Bind "Send OTP" → **`SendVerificationEmail`**; state validation is agent-side. | none |
| `core-skill-txt-response-guidelines` | OK | none (formatting only, no tool) | none |
| `core-skill-HTML-formatting-guidelines` | OK | none (formatting only) | none |
| `core-skill-render-data-format` | OK | Already references `render_data`; align to the declared tool name **`Render_Data`** exactly (casing). | none |

#### Domain skills
| Record | Header | Tool binding to add | Data fix |
|--------|--------|---------------------|----------|
| `skill-product-information-qa` | OK | Bind "create a case for follow-up" → **`CreateCase`**; optional structured output → **`Render_Data`** for spec comparison tables; product lookups → **`GetProductInfo`**. | none |
| `skill-support-case-management` | OK | Bind intake/creation → **`CreateCase`**; status lookup → **`FetchSupportHistory`** / `GetOrderStatus`; identity → **`SendVerificationEmail`**; present results via **`Render_Data`**. | none |
| `skill-troubleshooting-support` | OK | Bind escalation path → **`Route_to_ESA`** / `CreateEscalationTicket`; keep product-workflow record refs for cascade. | none |

#### Workflows
| Record | Header | Tool binding to add | Data fix |
|--------|--------|---------------------|----------|
| `workflow-support-case-lifecycle` | OK | "Create/Update" → **`CreateCase`**; identity step → **`SendVerificationEmail`**. | **`References__c` has space after comma** — normalize to no-spaces CSV. |
| `workflow-escalate-to-human` | OK | Bind routing → **`Route_to_ESA`**; ticket creation → **`CreateEscalationTicket`**. | none |
| `workflow-troubleshooting-wifi-modem` | OK | Escalation → **`Route_to_ESA`**. | none |
| `workflow-troubleshooting-5g-modem` | OK | Escalation → **`Route_to_ESA`**. | none |
| `workflow-troubleshooting-iphone-16` | OK | Escalation → **`Route_to_ESA`**. | none |
| `workflow-troubleshooting-iphone-16-pro` | OK | Escalation → **`Route_to_ESA`**. | none |
| `workflow-troubleshooting-galaxy-s25` | OK | Escalation → **`Route_to_ESA`**. | none |
| `workflow-troubleshooting-galaxy-s25-ultra` | OK | Escalation → **`Route_to_ESA`**. | none |

### 7.4 Tool references — stored indicator + composer rewrite/validation

#### 7.4.1 Platform constraint (why a stored pointer cannot resolve)

Agent Script resolves `{!@actions.X}` pointers during **deterministic preprocessing of the
`.agent` script text** (Manual §3 steps 3–4: "LLM receives only the resolved prompt after
deterministic preprocessing"). Preprocessing runs **before** variable values are
interpolated, and nested/second-pass interpolation is not supported. Skill bodies reach the
model as the *value* of `{!@variables.composed_instructions}` — interpolated **after**
preprocessing. Therefore **no string coming from CRM data can become a resolvable
`{!@actions.X}` binding**, regardless of how Apex formats it. Storing or rewriting to a
literal pointer would only print unresolved braces to the model. Tool *binding* (the
resolvable pointer) is not required for compliance here — the platform already exposes each
declared action to the model via its `description:`; what the skill must supply is a clear,
correct, unambiguous **textual cue** of which declared tool to use.

#### 7.4.2 The mechanism: `[[tool:Name]]` indicator → validated plain cue

Authors write a **stable indicator** in `InstructionBody__c` instead of hand-formatting tool
names:

```
Once the customer approves the summary, create the case with [[tool:CreateCase]].
If troubleshooting fails, escalate with [[tool:Route_to_ESA]].
```

The composer (`Agent_Skill_PromptComposer`) gains one **additive** post-composition pass:

1. **Rewrite** — replace each `[[tool:<Name>]]` with a clean, consistent plain-text cue,
   e.g. `the "CreateCase" tool`. This is what the model reads; it is ordinary text (no
   braces), so it is unaffected by preprocessing order.
2. **Validate** — check each `<Name>` against a known tool-name allowlist. Unknown or
   miscased names are surfaced in the composer `warnings` output (and left visibly marked in
   the text, e.g. `[[unknown tool: Crete_Case]]`, so authoring errors are caught, not hidden).

This gives three properties the raw approaches lacked: authors use one syntax instead of
remembering exact casing; the cue phrasing is uniform across all skills; and every tool
reference is **validated at load time**, catching typos/renames before they confuse the
model. The allowlist source is decided in the implementation plan (options: a static list,
a custom metadata type, or a value passed from the agent) — kept minimal.

#### 7.4.3 Revision principles applied to every body in §7.3

1. **Reference the tool at the point of action** using the `[[tool:Name]]` indicator, inline
   in the imperative step — not in a separate "tools" list the model may skip.
2. **Preserve record references for cascade** — `workflow-*`/`core-skill-*` names stay in
   prose and in `References__c` so composition still expands them. (Record refs and tool
   indicators are different things: refs drive composition; indicators drive tool cues.)
3. **Exact `Name`, single source of truth** — the `<Name>` inside `[[tool:...]]` must match a
   declared action name verbatim (`CreateCase`, `Render_Data`); the validator enforces this.
4. **No new capabilities** — binding only maps existing steps to existing tools; it does not
   add tasks the skill did not already describe.
5. **Reasoning block stays generic** — no tool enumeration in the subagent (§6.4). The cue in
   the composed instructions is the only per-skill tool guidance the model receives.

## 8. Deliverables

1. `Agent_Skill_HeaderProvider.cls` (+ `-meta.xml`) — new invocable.
2. `Agent_Skill_HeaderProvider_Test.cls` (+ `-meta.xml`) — coverage incl. the no-fallback
   exclusion path and missing-name reporting.
3. **`Agent_Skill_PromptComposer` — additive `[[tool:Name]]` rewrite/validation pass**
   (§7.4): rewrites indicators to plain cues, validates names against the tool allowlist,
   appends unknown-tool warnings. Composition/ordering/expansion logic unchanged. Extend
   `Agent_Skill_PromptComposer_Test` for rewrite, unknown-name warning, and no-indicator
   passthrough.
4. New agent bundle (`.agent` + `.bundle-meta.xml`), e.g. `customer_support_progressive`,
   declaring the §7.2 tool inventory on the single generic subagent, with a **minimal,
   topic-agnostic** reasoning block (§6.4 — no tool enumeration).
5. **Revised seed data** (`data/agent-skills/*.csv`): `[[tool:Name]]` indicators per §7.3 in
   every `InstructionBody__c`; fix malformed `References__c`
   (`core-skill-ltmManagement-service-agent`, `workflow-support-case-lifecycle`); confirm
   skill→workflow links. Document reseed.
6. Doc updates: header contract (D2), the `[[tool:Name]]` indicator + composer-rewrite
   mechanism (§7.4), and the router/generic-subagent pattern in
   `docs/Agent-Skills-Framework-for-FDE.md`.

## 9. Testing Strategy

- **Apex:** `Agent_Skill_HeaderProvider_Test` — happy path (headers returned in order),
  missing/inactive name reporting, blank-`WhenToUse__c` exclusion (no fallback), empty
  input, locale filter. Run alongside the existing core suite.
- **Composer:** `Agent_Skill_PromptComposer_Test` — `[[tool:Name]]` rewritten to the plain
  cue, unknown/miscased name produces a warning + visible marker, body with no indicators is
  unchanged.
- **Data:** a parse assertion that every `References__c` token resolves to an existing
  active record name (guards against reintroducing prose/spaces); and that every
  `[[tool:Name]]` indicator in seed `InstructionBody__c` names a real declared action
  (guards §7.4).
- **Agent:** `sf agent validate authoring-bundle` on the new bundle; targeted
  conversation tests (`testing-agentforce`) that a product-info utterance loads only
  `skill-product-information-qa`, a troubleshooting utterance cascades the
  troubleshooting workflows, and that a case-creation turn actually invokes `CreateCase`.

## 10. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Org `WhenToUse__c` drifts from seed CSVs → weak router headers | D2 contract excludes+warns; reseed step in scope; authoring-governance note in docs. |
| Large tool list on one subagent hits platform limits | Scope tools to the support-demo set (D4), not all ~50 repo flows; revisit if limits hit. |
| Router picks wrong/too-many skills | Headers audited as disjoint (§4); router prompt constrains to the candidate list; conversation tests validate. |
| Reintroducing malformed `References__c` | Data parse test (§9). |
| `[[tool:Name]]` names a non-existent/miscased action | Composer validates against the tool allowlist, warns, and leaves a visible marker (§7.4.2); data test asserts every indicator resolves. |
| Author/reader expects `[[tool:X]]` to become a resolvable `{!@actions.X}` binding | §7.4.1 documents the platform constraint explicitly; the cue is plain text by design and compliance comes from action `description:` + the validated cue, not pointer resolution. |
| Generic subagent calls a tool the loaded skill didn't sanction | Skill body cites only the relevant tool via `[[tool:Name]]`; reasoning block stays generic (§6.4); action `description:` scopes each tool's purpose. |

## 11. Deployment Target

Implementation is branch-only; **nothing auto-deploys**. When the feature is deployed and
validated, the target org is **`myDevOrg`** (`00DKY00000gXHJ52AO`,
`therciosb-dx@example.com`) — the org this repo was built against (matching the bundle
`default_agent_user` and the `00DKY` LTM ContactId prefix).

The project's stored default `target-org` (`dev-test-org`) is unset/stale, so every
deploy, `sf agent validate`, `sf agent publish`, reseed, and Apex-test command in the
implementation plan MUST pass **`--target-org myDevOrg` explicitly**.
