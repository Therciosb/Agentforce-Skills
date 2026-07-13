# Progressive Disclosure + Generic Subagent — Design

**Date:** 2026-07-13
**Branch:** `feature/progressive-disclosure-generic-subagent`
**Status:** Approved design, pending implementation plan

---

## 1. Problem & Goal

Today each Agentforce subagent in `customer_support_skill_demo` hardcodes its own
`instructionNames` in a `before_reasoning` block, and the agent is partitioned into
several specialized subagents (`troubleshooting_support`, `case_management`, etc.).
Adding or reshaping capabilities means editing agent script and republishing.

We want to invert and collapse this:

1. **Progressive disclosure at the router.** `start_agent` (the router) loads only the
   lightweight *headers* of a specified set of candidate skills into its reasoning
   context, decides which skills the user's request actually needs, and writes that
   decision to a variable — **before** routing to a subagent.
2. **One generic subagent.** A single purpose-agnostic subagent loads the skills the
   router selected, injects their composed instructions into its reasoning, and exposes
   the full catalog of business actions as tools. Its behavior for any given turn is
   determined entirely by which skills were loaded.

This keeps the existing CRM-backed load/compose logic (`Agent_Skills_Repo__c` →
`Agent_Skill_Loader` → `Agent_Skill_PromptComposer` → `Agent_Skill_LoadAndCompose`)
untouched, adding only a thin header-retrieval action alongside it.

## 2. Non-Goals

- No change to `Agent_Skill_Loader`, `Agent_Skill_PromptComposer`, or
  `Agent_Skill_LoadAndCompose` logic.
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

```
start_agent (agent_router)
  ├─ load_skills_init      apex://Agent_Skill_LoadAndCompose   role + core skills (flat) → instruction_bundle_json
  ├─ load_user_memory      apex://LoadAgentMemory              OPTIONAL LTM (guarded)
  ├─ get_skill_headers     apex://Agent_Skill_HeaderProvider   NEW: headers for candidate_skills → skill_headers
  └─ reasoning
        • sees user message + skill_headers
        • set skills_to_load = "<chosen no-spaces CSV>"
        • transition to @subagent.generic_handler

subagent generic_handler
  ├─ before_reasoning: load_skills   apex://Agent_Skill_LoadAndCompose
  │       instructionNames=skills_to_load, existingInstructionBundle=instruction_bundle_json
  │       → instruction_bundle_json (merged), composed_instructions
  │       (each selected skill cascades to its workflows via References__c)
  └─ reasoning
        • inject composed_instructions (+ optional agent_memory)
        • expose ALL business action tools; use those the instructions call for
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

### 6.4 Generic subagent (`generic_handler`)

- Top-level `actions:` declares `load_skills` (LoadAndCompose) plus the business-action
  tools reusing existing targets (final list enumerated in the implementation plan; e.g.
  `CreateCase`, `CreateEscalationTicket`, `Route_to_ESA`, `Render_Data`, order/support
  lookups, and the `save_context` LTM action).
- `before_reasoning`: LoadAndCompose with `instructionNames=@variables.skills_to_load`
  and `existingInstructionBundle=@variables.instruction_bundle_json`.
- `reasoning`: inject `composed_instructions` (+ optional `agent_memory`); reference every
  declared action so it is exposed as a tool; instruct to use only tools the loaded
  instructions call for.
- Loader's existing topic-scoped pruning (keeps `role-*`/`core-skill-*`, swaps
  `skill-*`/`workflow-*`) means re-entering the subagent for a new intent cleanly replaces
  the skill set — supporting multi-intent conversations through one subagent.

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
available tool MUST name that tool explicitly, e.g. "…get explicit customer approval, then
call **`CreateCase`**." Instruction-record references (e.g. "see `workflow-...`") remain for
composition/cascade, but are additive to — not a substitute for — the tool name.

### 7.2 Tool inventory (confirmed present, 10 of 55 flows)

`CreateCase`, `CreateEscalationTicket`, `Route_to_ESA`, `GetOrderStatus`,
`FetchSupportHistory`, `TrackShipment`, `FetchAccountData`, `GetProductInfo`,
`SendVerificationEmail`, `Render_Data`. These are the tools the generic subagent declares.

### 7.3 Per-record review (all 17 active seeded records)

Legend: **Header OK** = `WhenToUse__c` present & routing-useful (D2). **Tool binding** = the
tool(s) named in-step — as a **plain name** in `InstructionBody__c` (Layer 2) and as a
literal `{!@actions.<Name>}` pointer in the generic subagent's reasoning block (Layer 1);
see §7.4. **Data fix** = `References__c`/field corrections.

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

### 7.4 Tool-pointer syntax — the two-layer rule (CRITICAL)

Agent Script resolves `{!@actions.X}` pointers during **deterministic preprocessing of the
`.agent` script text** (Manual §3 steps 3–4: "LLM receives only the resolved prompt after
deterministic preprocessing"). Preprocessing runs **before** variable values are
interpolated, and nested/second-pass interpolation is not supported. Therefore a pointer
string stored in `InstructionBody__c` (CRM data, injected via
`{!@variables.composed_instructions}`) would reach the model as **unresolved literal text**,
not a tool binding. Pointers must live where they are processed. This yields two layers:

**Layer 1 — `.agent` `reasoning.instructions` of the generic subagent → literal pointer
syntax.** Each declared tool is named with `{!@actions.<Name>}`, in an imperative,
optionally condition-gated line (Manual §11.5: "Reference tools directly in text… improves
tool selection reliability"). Example pattern:
```
reasoning:
    instructions: ->
        | Follow the instructions loaded for this request:
        | {!@variables.composed_instructions}
        | Use ONLY the tool the loaded instructions call for at each step:
        | - To create a support case, call {!@actions.CreateCase}.
        | - To escalate to a human, call {!@actions.Route_to_ESA}.
        | - To create an escalation ticket, call {!@actions.CreateEscalationTicket}.
        | - To verify identity, call {!@actions.SendVerificationEmail}.
        | - To display structured data, call {!@actions.Render_Data}.
        | - To look up support history, call {!@actions.FetchSupportHistory}.
        | ... (one line per declared tool in §7.2)
```

**Layer 2 — CRM `InstructionBody__c` → plain tool name, exact casing.** The skill body names
the same tool in-step as plain text (e.g. "…get explicit customer approval, then call the
`CreateCase` tool."). No `{!@...}` in CRM data. Casing MUST match the Layer-1 action name
verbatim so the two layers reinforce (the body says which tool; the literal pointer binds
it).

**Revision principles applied to every body in §7.3:**

1. **Name the tool at the point of action** — inline in the imperative step (plain name in
   CRM per Layer 2), not in a separate "tools" list the model may skip.
2. **Preserve record references for cascade** — `workflow-*`/`core-skill-*` names stay in
   prose and in `References__c` so composition still expands them.
3. **Exact casing, single source of truth** — every tool name in a body (Layer 2) and every
   `{!@actions.X}` pointer (Layer 1) must match a declared action name verbatim
   (`Render_Data`, not `render_data`).
4. **No new capabilities** — binding only maps existing steps to existing tools; it does not
   add tasks the skill did not already describe.

## 8. Deliverables

1. `Agent_Skill_HeaderProvider.cls` (+ `-meta.xml`) — new invocable.
2. `Agent_Skill_HeaderProvider_Test.cls` (+ `-meta.xml`) — coverage incl. the no-fallback
   exclusion path and missing-name reporting.
3. New agent bundle (`.agent` + `.bundle-meta.xml`), e.g. `customer_support_progressive`,
   declaring the §7.2 tool inventory on the single generic subagent.
4. **Revised seed data** (`data/agent-skills/*.csv`): tool-name binding per §7.3 in every
   `InstructionBody__c`; fix malformed `References__c` (`core-skill-ltmManagement-service-agent`,
   `workflow-support-case-lifecycle`); confirm skill→workflow links. Document reseed.
5. Doc updates: header contract (D2), tool-binding rule (§7.1), and the
   router/generic-subagent pattern in `docs/Agent-Skills-Framework-for-FDE.md`.

## 9. Testing Strategy

- **Apex:** `Agent_Skill_HeaderProvider_Test` — happy path (headers returned in order),
  missing/inactive name reporting, blank-`WhenToUse__c` exclusion (no fallback), empty
  input, locale filter. Run alongside the existing core suite.
- **Data:** a parse assertion that every `References__c` token resolves to an existing
  active record name (guards against reintroducing prose/spaces); and that every tool name
  cited in a revised `InstructionBody__c` matches a declared action (guards §7.4 casing).
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
| Tool name in body drifts from declared action name (casing/rename) | §7.4 exact-casing rule + data test asserting cited tool names resolve to declared actions. |
| Generic subagent calls a tool the loaded skill didn't sanction | Reasoning prompt constrains to tools the composed instructions name; §7.1 binds tools inline so only relevant tools are cited. |
