# Agent Skills Framework for FDE Engineers

A developer guide for building Agentforce agents using the Agent Skills framework. This document is intended for FDE (Full-Stack Developer Engineer) engineers implementing agents in source control with Agent Script.

---

## 1. Problem Statement

### The Challenge

Building production-ready AI agents for enterprise use cases presents several interconnected problems:

1. **Hardcoded Instructions**: Agent prompts are typically embedded directly in the agent definition. Any change to policies, procedures, or domain knowledge requires redeploying the agent bundle. Business stakeholders cannot update instructions without developer involvement.

2. **Fragmented Knowledge Management**: Domain expertise—product information, troubleshooting steps, compliance rules, escalation workflows—lives in documents, wikis, and tribal knowledge. There is no single source of truth that agents can consume at runtime.

3. **Inconsistent Agent Behavior**: Without a structured approach, similar agents (e.g., support for different product lines) duplicate logic and diverge over time. Updates to shared procedures must be propagated manually across multiple agents.

4. **Limited Reusability**: Skills and workflows that apply across topics or agents (e.g., identity verification, escalation, response guidelines) cannot be composed. Each topic reinvents the wheel or copies blocks of instructions.

5. **No Versioning or Governance**: Instruction changes are not tracked, versioned, or governed. Deprecating outdated procedures or A/B testing instruction variants is difficult.

6. **Context Window Waste**: Loading all possible instructions into every topic bloats the prompt and wastes tokens. Agents need topic-specific instruction subsets composed dynamically.

### What the Framework Solves

The Agent Skills framework addresses these problems by:

- **Separating instructions from agent logic**: Instructions live in a CRM-backed repository (`Agent_Skills_Repo__c`), editable by business users without redeploying agents.
- **Providing a structured taxonomy**: Roles, core skills, skills, and workflows with clear naming conventions and reference relationships.
- **Enabling dynamic composition**: Agents load only the instructions needed for the current topic and merge them with role/core context. Reference expansion pulls in dependent workflows automatically.
- **Supporting versioning and lifecycle**: Records have `Status__c` (active/deprecated), `Version__c`, and `Locale__c` for governance and localization.
- **Integrating with Long-Term Memory**: Composed instructions work alongside persistent context (`Agent_Context__c`) for personalized, session-aware behavior.

---

## 2. Value to Enterprises

### Business Agility

- **Non-developer updates**: Product managers, support leads, and compliance officers can update instructions via the Agent Skills Admin app. No code changes or deployments required for policy or procedural updates.
- **Rapid iteration**: Test new instruction variants by activating records; roll back by deprecating. No agent republish needed for instruction-only changes.

### Consistency and Compliance

- **Single source of truth**: All agents consuming the same role/skill/workflow records behave consistently. Compliance updates propagate automatically.
- **Auditability**: Instruction changes are tracked in Salesforce. Who changed what and when is visible in standard audit fields.

### Scalability and Maintainability

- **Reusable building blocks**: One escalation workflow, one authentication skill, one response guideline—used across many topics and agents.
- **Reduced duplication**: Reference expansion ensures dependent workflows are included without manual copying. Change the workflow once; all referencing skills inherit the update.

### Cost Efficiency

- **Token optimization**: Only topic-relevant instructions are composed into the prompt. Role and core skills provide baseline; topic skills add domain-specific context. No loading of irrelevant workflows.
- **Lower development cost**: New agents or topics reuse existing skills. Engineers focus on routing and flow logic; instruction content is managed in the repository.

### Enterprise Integration

- **CRM-native**: Skills live in Salesforce. Integrates with permission sets, approval processes, and existing data governance.
- **LTM alignment**: Framework is designed to work with Long-Term Memory (Agent_Context__c). Composed instructions plus persisted context enable personalized, context-aware conversations.

---

## 3. Implementation

### 3.1 Overview of Assets

| Asset Type | Purpose |
|------------|---------|
| **Agent_Skills_Repo__c** | Custom object storing roles, core skills, skills, and workflows. Fields: `Name`, `Type__c`, `InstructionBody__c`, `References__c`, `Status__c`, `Version__c`, `Locale__c`, etc. |
| **Agent_Skill_Loader** | Invocable Apex action. Loads active records by name (CSV), optionally merges with existing bundle, expands references. Outputs JSON bundle. |
| **Agent_Skill_PromptComposer** | Invocable Apex action. Takes bundle JSON, assembles prompt-ready text with deterministic ordering (role → core-skill → skill → workflow), expands references recursively. |
| **Agent_Skill_LoadAndCompose** | Invocable Apex action. Aggregates Loader + Composer. Primary entry point for agents. |
| **Agent_Skill_LoadAndCompose** | Invocable Apex. Primary target for agent action `load_and_compose_skills`. Flow `Load_And_Compose_Agent_Skills` is an optional wrapper. |
| **Agent_Skills_Admin** | Custom app with tabs and permission sets for Authors, Reviewers, Consumers. |
| **Agent_Context__c** (LTM) | Persistent memory object. Read via `apex://LoadAgentMemory` (returns `agentMemory` formatted string), saved via `apex://SaveAgentContext` (contactId, newSummary, newGoal, hasIssue, newStyle). Required for LTM-enabled agents. |

#### Admin App Authoring Aids

The `Agent_Skills_Admin` app ships two Lightning Web Components that help authors create and understand skills:

- **`skillBuilder`** (app Home page) — A guided form (skill type radio + intent textarea + optional reference-document upload). On submit it calls `Agent_Skill_Builder.generateSkill`, which invokes the `Generate_Agent_Skill` prompt template to draft the instruction body and metadata. The builder **always inserts the record as Draft** (`Status__c='Draft'`) so an author reviews it before activation; it never activates. On success it navigates to the new record.
- **`skillDependencyTree`** (record page) — A `lightning-tree` that renders the downstream skills/workflows a record composes by expanding `References__c` (via the `Agent_Skill_DependencyProvider.getTree` cacheable wire). It flags missing/inactive references and marks repeat nodes as already-shown to keep cycles safe.

The `Generate_Agent_Skill` `GenAiPromptTemplate` is the generation seam behind the builder; it returns strict JSON that the Apex layer parses, guardrails, and persists as a Draft `Agent_Skills_Repo__c` record.

### 3.2 Instruction Taxonomy

| Type | Naming Convention | Purpose |
|------|-------------------|---------|
| **Role** | `role-*` | Agent identity, tone, authority, primary goals. Loaded once at `start_agent`. |
| **Core Skill** | `core-skill-*` | Cross-cutting capabilities: authentication, response guidelines, LTM management. Shared across topics. |
| **Skill** | `skill-*` | Domain-specific capabilities: product Q&A, troubleshooting, case management. Loaded per topic. |
| **Workflow** | `workflow-*` | Step-by-step procedures. Referenced by skills or other workflows. Composer expands references automatically. |

### 3.3 Logic: Load, Merge, Compose

**Load Phase (Agent_Skill_Loader)**

1. Accept `instructionNames` (CSV) and optional `existingInstructionBundle` (JSON).
2. Query `Agent_Skills_Repo__c` for active records matching names.
3. If `includeReferences=true`, expand `References__c` to include dependent instructions.
4. Merge newly loaded items with `existingInstructionBundle` (deduplication by name).
5. Output `loadedInstructionBundle` (JSON) and `skillsLoadedCount`.

**Compose Phase (Agent_Skill_PromptComposer)**

1. Parse `instructionBundle` JSON.
2. Always include all `role-*` and `core-skill-*` entries in the bundle.
3. Add `requiredNames` (topic-specific skills/workflows).
4. If `includeReferenceExpansion=true`, recursively expand references up to `maxReferenceDepth` (default 4).
5. Order deterministically: role → core-skill → skill → workflow, then lexical within each group.
6. Format each block as `[Instruction: name]\n{instructions}`.
7. Output `composedInstructions` (prompt-ready string).

**Merge Pattern**

- `start_agent` loads role + core skills → stores `loadedInstructionBundle` in `@variables.instruction_bundle_json`.
- Each topic calls Load_And_Compose with:
  - `instructionNames` = topic-specific skills/workflows (CSV)
  - `existingInstructionBundle` = `@variables.instruction_bundle_json`
- Apex merges new skills into existing bundle, composes, returns `instructionsBundle` and updated `loadedInstructionBundle`.
- Topic stores updated bundle back to `instruction_bundle_json` for downstream topics.

### 3.4 Reference Expansion

- Each `Agent_Skills_Repo__c` record can have `References__c` (CSV of instruction names).
- When a skill references workflows (e.g., `skill-troubleshooting-support` → `workflow-troubleshooting-wifi-modem`, `workflow-escalate-to-human`), the Composer includes them automatically.
- Workflows can reference other workflows (e.g., product workflow → `workflow-escalate-to-human`).
- Expansion is recursive with `maxReferenceDepth` to prevent infinite loops.
- Override `maxReferenceDepth` per call (e.g., use 2 for finalization to limit escalation scope).

---

## 4. Agent Script Structure When Applying the Framework

### 4.1 Required Variables

```yaml
variables:
    # LTM (if using persistent memory)
    ContactId: linked string
    context_loaded: mutable boolean = False
    agent_memory: mutable string = ""

    # Instruction bundle state
    instruction_bundle_json: mutable object   # Raw JSON for merge
    composed_instructions: mutable string = "" # Prompt-ready text for reasoning
```

### 4.2 Required Action: load_and_compose_skills

Every topic that needs composed instructions must define this action:

```yaml
actions:
    load_and_compose_skills:
        description: "Load topic-specific skills, merge with existing bundle, compose prompt-ready instructions."
        inputs:
            instructionNames: string
                description: "CSV list of topic-specific skill/workflow names."
            existingInstructionBundle: string
                description: "Existing bundle JSON (role + core from start_agent)."
        outputs:
            instructionsBundle: string
                description: "Formatted prompt-ready instruction text."
            loadedInstructionBundle: string
                description: "Raw instruction bundle JSON for merge."
        target: "apex://Agent_Skill_LoadAndCompose"
```

### 4.3 start_agent Pattern

**Responsibilities**: Load LTM (if used), load role + core skills, store bundle, transition to first topic.

```yaml
start_agent topic_selector:
    label: "Entry Point"
    description: "Initial bootstrap: memory + role/core skills; topics add topic-specific skills."

    actions:
        load_user_memory:
            description: "Load persistent memory (formatted string) for this contact."
            inputs:
                contactId: string
            outputs:
                agentMemory: string
            target: "apex://LoadAgentMemory"
        load_and_compose_skills:
            description: "Load role and core skills into instruction bundle."
            inputs:
                instructionNames: string
            outputs:
                loadedInstructionBundle: string
            target: "apex://Agent_Skill_LoadAndCompose"

    reasoning:
        instructions: ->
            # 1. Load LTM (guarded by context_loaded)
            if @variables.context_loaded == False and @variables.ContactId and @variables.ContactId != "":
                run @actions.load_user_memory
                    with contactId=@variables.ContactId
                    set @variables.agent_memory=@outputs.agentMemory
                    set @variables.context_loaded=True

            # 2. Load role + core skills
            run @actions.load_and_compose_skills
                with instructionNames="role-customer-support-agent,core-skill-ltmManagement-service-agent,core-skill-txt-response-guidelines"
                set @variables.instruction_bundle_json=@outputs.loadedInstructionBundle

            # 3. Transition to first topic
            transition to @topic.general_support
```

**Critical rule**: Map outputs inside the same `run` block (`set @variables.x=@outputs.y`).

### 4.4 Topic Pattern

**Responsibilities**: Load topic-specific skills, merge with bundle, compose, inject into reasoning, route to next topic.

```yaml
topic general_support:
    label: "General Support Intake"
    description: "Primary customer support intake."

    actions:
        load_and_compose_skills:
            # ... (same definition as above)
            target: "apex://Agent_Skill_LoadAndCompose"

    reasoning:
        instructions: ->
            # 1. Load topic skills, merge, compose
            run @actions.load_and_compose_skills
                with instructionNames="skill-product-information-qa,skill-support-case-management"
                with existingInstructionBundle=@variables.instruction_bundle_json
                set @variables.instruction_bundle_json=@outputs.loadedInstructionBundle
                set @variables.composed_instructions=@outputs.instructionsBundle

            # 2. Optional: inject LTM profile for personalization (agent_memory is formatted string from LoadAgentMemory Apex)
            | Here is your past context. Use it for personalization:
            | {!@variables.agent_memory}
            | If unresolved issue is indicated, acknowledge prior issues and ask whether they were resolved. If pending goal is set, ask if the user wants to continue it. Start with a personalized greeting. Then follow the instructions below.

            # 3. Inject composed instructions
            | {!@variables.composed_instructions}

            # 4. Topic-specific routing
            | Assess intent and route:
            | - For troubleshooting, use {!@actions.go_to_troubleshooting}.
            | - For case requests, use {!@actions.go_to_case_management}.
            | - For session end, use {!@actions.go_to_finalization}.

        actions:
            go_to_troubleshooting: @utils.transition to @topic.troubleshooting_support
            go_to_case_management: @utils.transition to @topic.case_management
            go_to_finalization: @utils.transition to @topic.finalization
```

### 4.5 Finalization Topic (LTM Persistence)

```yaml
topic finalization:
    label: "Finalization and Escalation"
    description: "Escalation summary and memory checkpoint."

    actions:
        load_and_compose_skills:
            # ... with instructionNames="workflow-escalate-to-human"
            # Optional: with maxReferenceDepth=2
            target: "apex://Agent_Skill_LoadAndCompose"
        save_context_tool:
            description: "Persist long-term memory (scalar inputs only)."
            inputs:
                contactId: string
                newSummary: string
                newGoal: string
                hasIssue: boolean
                newStyle: string
            outputs:
                success: boolean
            target: "apex://SaveAgentContext"

    reasoning:
        instructions: ->
            run @actions.load_and_compose_skills
                with instructionNames="workflow-escalate-to-human"
                with existingInstructionBundle=@variables.instruction_bundle_json
                set @variables.composed_instructions=@outputs.instructionsBundle

            | Follow these instructions: {!@variables.composed_instructions}
            | Before saying goodbye, call {!@actions.persist_memory} exactly once with extracted newSummary, newGoal, hasIssue, newStyle.

        actions:
            persist_memory: @actions.save_context_tool
                with contactId=@variables.ContactId
                with newSummary=...
                with newGoal=...
                with hasIssue=...
                with newStyle=...
```

### 4.6 Structural Summary

| Block | Role + Core Skills | Topic Skills | LTM Load | LTM Save |
|-------|-------------------|--------------|----------|----------|
| `start_agent` | ✓ Load | — | ✓ | — |
| Domain topics | Merge | ✓ Load | — | — |
| `finalization` | Merge | ✓ (e.g., escalation) | — | ✓ |

### 4.7 Key Rules for FDE Engineers

1. **Output mapping**: Always `set @variables.x=@outputs.y` inside the same `run` block. Mapping outside the block can cause errors.
2. **LTM memory access**: For `agent_memory` (formatted string from LoadAgentMemory Apex), inject directly in prompts: `{!@variables.agent_memory}`.
3. **System instructions**: Keep `system.instructions` static. Do not interpolate dynamic content there. Use topic reasoning for dynamic instruction text.
4. **Bundle continuity**: Pass `instruction_bundle_json` through every topic. Each topic merges its skills and updates the variable for the next.
5. **Naming**: Use consistent CSV for `instructionNames` (e.g., `"role-customer-support-agent,core-skill-txt-response-guidelines"`). No spaces after commas.

---

## 5. Progressive Disclosure & Generic Handler Topic

The patterns in Section 4 partition an agent into several specialized topics, each hardcoding its own `instructionNames`. An alternative pattern inverts and collapses this: the router performs **progressive disclosure** (loading only lightweight skill *headers*, then deciding which skills the turn needs) and hands off to a **single generic handler topic** that loads the selected skills and exposes the full tool catalog. The reference implementation is the **`customer_support_progressive_pd2`** bundle. See `docs/superpowers/specs/2026-07-13-progressive-disclosure-generic-subagent-design.md` for the design rationale and `docs/superpowers/plans/2026-07-13-progressive-disclosure-generic-subagent.md` for the implementation plan.

> **Runtime requirements (learned in testing — see §5.4 and §5.5):** this pattern only works if (a) the router's reasoning loop is bounded by deterministic guards so it does not re-load init data or spin on `select_skills`, and (b) the **agent runtime user has object + field permissions for every object the exposed tools touch** (Case CRUD, `ASR_Product__c` read/FLS, etc.). Missing either produces silent loops or generic `UNKNOWN_EXCEPTION` flow errors, not obvious failures.

### 5.1 Header Contract (No Fallback)

`Agent_Skill_HeaderProvider` (invocable label **"Get Skill Headers"**) returns lean routing headers for a candidate skill list — `Name` plus `WhenToUse__c` only, with no instruction body and no reference expansion. Each returned line is formatted as `- <Name>: <WhenToUse__c>`.

The contract has **no fallback**:

- A candidate skill whose `WhenToUse__c` is blank is **excluded** from `skillHeaders` — it is never silently substituted with `Description__c`.
- The excluded name (along with inactive or not-found names) is reported in the `missingNames` CSV and surfaced in `warnings`.

Because headers are the router's only signal for a candidate skill, authoring a meaningful `WhenToUse__c` ("Use when…") is **mandatory** for any skill you intend to expose as a router candidate. Header quality is an authoring responsibility that grows with the catalog, the same governance point the framework makes for instruction bodies.

### 5.2 The `[[tool:Name]]` Indicator

In the generic-handler pattern every action tool is present at once, so an instruction body must name the exact tool the agent should call. Authors write a stable indicator inline in `InstructionBody__c` at the point of action:

```
Once the customer approves the summary, create the case with [[tool:CreateCase]].
If troubleshooting fails, escalate with [[tool:Route_to_ESA]].
```

`Agent_Skill_PromptComposer` runs one **additive** post-composition pass over the already-composed text:

1. **Rewrite** — each `[[tool:<Name>]]` becomes a clean, uniform plain-text cue, e.g. `the "CreateCase" tool`.
2. **Validate** — each `<Name>` is checked against the tool allowlist (`KNOWN_TOOL_NAMES`). Unknown or miscased names are left visibly marked as `[[unknown tool: <Name>]]` and surfaced in the composer `warnings` output, so authoring errors are caught rather than hidden.

**Important — the indicator is a PLAIN-TEXT CUE, not a resolvable pointer.** It is deliberately *not* a `{!@actions.X}` binding. Agent Script resolves `{!@actions.X}` pointers during deterministic preprocessing of the `.agent` script text, which runs **before** variable values are interpolated; nested/second-pass interpolation is not supported. Skill bodies reach the model as the interpolated *value* of `{!@variables.composed_instructions}` — after preprocessing — so no string coming from CRM data can ever become a resolvable `{!@actions.X}` binding. Compliance comes from the action `description:` (which the platform already exposes to the model) plus the validated textual cue, not from pointer resolution.

Record references in `References__c` are a **separate mechanism**: they name other instruction records (`workflow-*`, `core-skill-*`), remain in prose and in `References__c`, and drive the composition **cascade**. Tool indicators drive tool cues; record references drive cascade. The two are additive — a tool indicator never replaces a record reference.

### 5.3 Router + Generic Handler Topic Pattern

> **Convention note:** this repo uses `topic` blocks and `@topic` transitions — there is no `subagent`/`@subagent.` syntax. The single generic handler is a **topic**, not a subagent. Skill loading is done as the first `run` inside `reasoning.instructions` (the repo does not use `before_reasoning`), and an action becomes an LLM-callable tool only when it is re-exposed under `reasoning.actions:` with slot-fill.

**Router (`start_agent`):** loads role + core skills flat (no cascade) **once**, optionally loads LTM, fetches lean headers for the candidate skills via `Agent_Skill_HeaderProvider`, and instructs the LLM to set `skills_to_load` (a no-spaces CSV) through a `select_skills` tool. It transitions to the one handler topic in `after_reasoning`. Three deterministic guards keep the router's reasoning loop bounded (all three were required to stop real looping failures — see §5.4):

```
    variables:
        # ...
        context_loaded: mutable boolean = False
        router_initialized: mutable boolean = False   # guards one-time init
        skills_to_load: mutable string = ""

    reasoning:
        instructions: ->
            # GUARD 1 — loop exit: once skills are chosen, transition immediately so the
            # reasoning loop terminates instead of re-invoking select_skills forever.
            if @variables.skills_to_load != "":
                transition to @subagent.generic_handler

            if @variables.context_loaded == False and @variables.ContactId and @variables.ContactId != "":
                run @actions.load_user_memory
                    with contactId=@variables.ContactId
                    set @variables.agent_memory=@outputs.agentMemory
                    # ... other memory outputs ...
                    set @variables.context_loaded=True

            # GUARD 2 — one-time init: load role/core + headers only on the first pass,
            # so later reasoning iterations do NOT re-run these deterministic actions.
            if @variables.router_initialized == False:
                run @actions.load_skills_init
                    with instructionNames="role-customer-support-agent,core-skill-ltmManagement-service-agent,core-skill-txt-response-guidelines"
                    set @variables.instruction_bundle_json=@outputs.loadedInstructionBundle
                run @actions.get_skill_headers
                    with skillNames=@variables.candidate_skills
                    set @variables.skill_headers=@outputs.skillHeaders
                set @variables.router_initialized=True

            | You are the router. Select which skills are needed for the user's request.
            | Available skills (choose from these names only):
            | {!@variables.skill_headers}
            |
            | You MUST call {!@actions.select_skills} exactly once this turn with a comma-separated list of the matching skill names (exact names, no spaces after commas). This is your only job — do not answer the user directly.
            | GUARD 3 — no-match fallback: If one or more skills clearly match, select them. If the request is a greeting, small talk, thanks, or unclear, still call select_skills with the single best-guess skill ("skill-product-information-qa"). Never respond without calling select_skills, and never call it with an empty value.

        actions:
            select_skills: @utils.setVariables
                description: "Record the chosen skill names to load for this request."
                with skills_to_load=...

    after_reasoning:
        transition to @subagent.generic_handler
```

**Generic handler (`topic generic_handler`):** loads the router-selected skills as the **first `run`** in `reasoning.instructions` (each selected `skill-*` cascades to its `workflow-*` via `References__c`), injects the composed instructions, and re-exposes the full support-demo tool catalog under `reasoning.actions`. The reasoning prose stays **topic-agnostic** — it does not enumerate individual tools; each tool's purpose lives in its action `description:`, and the loaded skills decide which tools apply:

```
    reasoning:
        instructions: ->
            run @actions.load_skills
                with instructionNames=@variables.skills_to_load
                with existingInstructionBundle=@variables.instruction_bundle_json
                set @variables.instruction_bundle_json=@outputs.loadedInstructionBundle
                set @variables.composed_instructions=@outputs.instructionsBundle

            | Here is your past context. Use it for personalization if present:
            | {!@variables.agent_memory}
            |
            | Follow these instructions. They determine what to do and which tools to use:
            | {!@variables.composed_instructions}
            |
            | Use the tools available to you as directed by the instructions above.
            |
            | ESCALATION GUARDRAIL (overrides the instructions above): Do NOT escalate to a human or route to a specialist unless EITHER the user explicitly asks for a human/agent/escalation, OR troubleshooting has genuinely been exhausted this session AND the user agrees to escalate. If the user says they want to continue troubleshooting, keep troubleshooting — never escalate. Only call the "CreateEscalationTicket" tool with a concrete customer_id, a one-sentence issue_description, and an issue_type (technical, billing, or general); never with empty or guessed values.

        actions:
            create_case: @actions.create_case
                description: "Create a new support case from a concise, user-approved subject."
                with subject=...
            route_to_esa: @utils.escalate
                description: "Route the conversation to a human (Enhanced Service Agent) via Omni-Channel."
            # ... remaining business tools (create_escalation_ticket, get_product_info,
            #     fetch_support_history, render_data, save_context, ...) re-exposed here
            #     as slot-filled wrappers
```

Re-exposing each action under `reasoning.actions:` is required plumbing (a bare `topic.actions:` declaration is only deterministically callable via `run @actions.X`), not topic coupling: the prose stays generic while the loaded skills' `[[tool:Name]]` cues tell the model which tool to invoke.

> **`route_to_esa` uses `@utils.escalate`, not a flow.** `Route_to_ESA` is a `RoutingFlow`, which cannot be invoked as a `flow://` agent action (deploy rejects it even though `sf agent validate` accepts it). The platform-native human handoff is the `@utils.escalate` utility. The `[[tool:Route_to_ESA]]` cue in skill bodies maps to this `route_to_esa` tool.

### 5.4 Bounding the Router Reasoning Loop (required)

The router runs its `reasoning.instructions` on **every** reasoning iteration, and `after_reasoning` fires only when the loop **exits**. Without deterministic guards this produces two distinct, hard-to-spot failures observed in live testing — both surface as a generic *"request may be complex"* message after 20–50 wasted LLM iterations:

| Failure | Cause | Guard |
|---------|-------|-------|
| Init actions re-run every iteration (`load_skills_init`/`get_skill_headers` called dozens of times) | Deterministic `run`s sit unguarded in `reasoning.instructions` | **Guard 2** — `if router_initialized == False { … set router_initialized=True }` |
| Router never leaves `topic_selector`; `select_skills` invoked repeatedly | Nothing exits the loop after the variable is set, so `after_reasoning` never runs | **Guard 1** — `if skills_to_load != "": transition …` at the **top** of instructions |
| Loop on greeting/ambiguous input; `skills_to_load` never set | No skill matches, so the LLM never calls `select_skills` and Guard 1 never triggers | **Guard 3** — prompt instructs a default skill when nothing matches, so `skills_to_load` is always set |

Verify with a preview trace: a healthy turn shows `topic: generic_handler`, a small LLM-iteration count, and `load_skills_init`/`get_skill_headers` counts of at most 1.

### 5.5 Agent-User Permissions (required)

The exposed tools run flows/Apex **as the agent runtime user** (the `default_agent_user`, on the Einstein Agent User profile), which enforces that user's object and field permissions. A brand-new invocable class or an object a tool's flow touches is **not** accessible until granted on the runtime permission set (`Agent_Skills_Agent_Runtime`). Missing access surfaces as either `NO_USER_ACCESS` (the tool is withheld from the planner) or `UNKNOWN_EXCEPTION: An error occurred when executing a flow interview` (a 500 when the flow runs) — never an obvious "permission denied".

Grant on `Agent_Skills_Agent_Runtime` (and assign it to the agent user):

- **Apex classes** the agent invokes — including `Agent_Skill_HeaderProvider` (added for this pattern).
- **Object CRUD** for every object a tool writes — e.g. **`Case` Create/Read/Edit** for `CreateCase` and `CreateEscalationTicket`.
- **Object Read + field-level Read (FLS)** for every custom object a tool reads — e.g. **`ASR_Product__c` Read** plus FLS on `Description__c`, `Price__c`, `In_Stock__c` for `GetProductInfo`. Custom fields need explicit `fieldPermissions`; object CRUD alone is not enough.

> Any additional data tools you expose (`FetchSupportHistory`, `FetchAccountData`, `GetOrderStatus`, `TrackShipment`) will need the same object/field grants for their target objects before they will run.

---

## Related Documentation

- `docs/Agent Script Manual v4.md` — Agent Script language and execution model
- `docs/Apex Action Contracts.md` — Loader, Composer, LoadAndCompose API details
- [LTM Integration Mapping](LTM%20Integration%20Mapping.md) — Optional persistent memory: object schema and flow contracts (no LTM-Agentforce dependency)
- `docs/DMO Seeding Guide.md` — Seeding demo role/skill/workflow data
- `docs/Implementation Plan v1.md` — Framework implementation baseline
