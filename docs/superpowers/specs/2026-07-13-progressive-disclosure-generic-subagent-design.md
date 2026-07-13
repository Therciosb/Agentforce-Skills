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

## 7. Deliverables

1. `Agent_Skill_HeaderProvider.cls` (+ `-meta.xml`) — new invocable.
2. `Agent_Skill_HeaderProvider_Test.cls` (+ `-meta.xml`) — coverage incl. the no-fallback
   exclusion path and missing-name reporting.
3. New agent bundle (`.agent` + `.bundle-meta.xml`), e.g. `customer_support_progressive`.
4. Seed-data corrections: fix malformed `References__c` in `data/agent-skills/*.csv`;
   confirm skill→workflow links; document reseed.
5. Doc updates: note the header contract (D2) and the router/generic-subagent pattern in
   `docs/Agent-Skills-Framework-for-FDE.md` (or a focused new doc).

## 8. Testing Strategy

- **Apex:** `Agent_Skill_HeaderProvider_Test` — happy path (headers returned in order),
  missing/inactive name reporting, blank-`WhenToUse__c` exclusion (no fallback), empty
  input, locale filter. Run alongside the existing core suite.
- **Data:** a parse assertion that every `References__c` token resolves to an existing
  active record name (guards against reintroducing prose/spaces).
- **Agent:** `sf agent validate authoring-bundle` on the new bundle; targeted
  conversation tests (`testing-agentforce`) that a product-info utterance loads only
  `skill-product-information-qa`, and a troubleshooting utterance cascades the
  troubleshooting workflows.

## 9. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Org `WhenToUse__c` drifts from seed CSVs → weak router headers | D2 contract excludes+warns; reseed step in scope; authoring-governance note in docs. |
| Large tool list on one subagent hits platform limits | Scope tools to the support-demo set (D4), not all ~50 repo flows; revisit if limits hit. |
| Router picks wrong/too-many skills | Headers audited as disjoint (§4); router prompt constrains to the candidate list; conversation tests validate. |
| Reintroducing malformed `References__c` | Data parse test (§8). |
