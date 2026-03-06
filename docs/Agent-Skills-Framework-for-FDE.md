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
| **Load_And_Compose_Agent_Skills** | Flow that invokes `Agent_Skill_LoadAndCompose`. Target for agent action `load_and_compose_skills`. |
| **Agent_Skills_Admin** | Custom app with tabs and permission sets for Authors, Reviewers, Consumers. |
| **Agent_Context__c** (LTM) | Persistent memory object. Read via `Get_Agent_ContextObject` (returns `agent_memory` formatted string), saved via `Save_Agent_ContextObject` (scalar inputs only). Required for LTM-enabled agents. |

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
- Flow merges new skills into existing bundle, composes, returns `instructionsBundle` and updated `loadedInstructionBundle`.
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
        target: "flow://Load_And_Compose_Agent_Skills"
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
                contact_id: string
            outputs:
                agent_memory: string
            target: "flow://Get_Agent_ContextObject"
        load_and_compose_skills:
            description: "Load role and core skills into instruction bundle."
            inputs:
                instructionNames: string
            outputs:
                loadedInstructionBundle: string
            target: "flow://Load_And_Compose_Agent_Skills"

    reasoning:
        instructions: ->
            # 1. Load LTM (guarded by context_loaded)
            if @variables.context_loaded == False and @variables.ContactId and @variables.ContactId != "":
                run @actions.load_user_memory
                    with contact_id=@variables.ContactId
                    set @variables.agent_memory=@outputs.agent_memory
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
            target: "flow://Load_And_Compose_Agent_Skills"

    reasoning:
        instructions: ->
            # 1. Load topic skills, merge, compose
            run @actions.load_and_compose_skills
                with instructionNames="skill-product-information-qa,skill-support-case-management"
                with existingInstructionBundle=@variables.instruction_bundle_json
                set @variables.instruction_bundle_json=@outputs.loadedInstructionBundle
                set @variables.composed_instructions=@outputs.instructionsBundle

            # 2. Optional: inject LTM profile for personalization (agent_memory is formatted string from flow)
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
            target: "flow://Load_And_Compose_Agent_Skills"
        save_context_tool:
            description: "Persist long-term memory (scalar inputs only)."
            inputs:
                contact_id: string
                new_summary: string
                new_goal: string
                has_issue: boolean
                new_style: string
            outputs:
                success: boolean
            target: "flow://Save_Agent_ContextObject"

    reasoning:
        instructions: ->
            run @actions.load_and_compose_skills
                with instructionNames="workflow-escalate-to-human"
                with existingInstructionBundle=@variables.instruction_bundle_json
                set @variables.composed_instructions=@outputs.instructionsBundle

            | Follow these instructions: {!@variables.composed_instructions}
            | Before saying goodbye, call {!@actions.persist_memory} exactly once with extracted new_summary, new_goal, has_issue, new_style.

        actions:
            persist_memory: @actions.save_context_tool
                with contact_id=@variables.ContactId
                with new_summary=...
                with new_goal=...
                with has_issue=...
                with new_style=...
                with has_issue=...
                with new_style=...
```

### 4.6 Structural Summary

| Block | Role + Core Skills | Topic Skills | LTM Load | LTM Save |
|-------|-------------------|--------------|----------|----------|
| `start_agent` | ✓ Load | — | ✓ | — |
| Domain topics | Merge | ✓ Load | — | — |
| `finalization` | Merge | ✓ (e.g., escalation) | — | ✓ |

### 4.7 Key Rules for FDE Engineers

1. **Output mapping**: Always `set @variables.x=@outputs.y` inside the same `run` block. Mapping outside the block can cause errors.
2. **LTM memory access**: For `agent_memory` (formatted string from Get_Agent_ContextObject), inject directly in prompts: `{!@variables.agent_memory}`.
3. **System instructions**: Keep `system.instructions` static. Do not interpolate dynamic content there. Use topic reasoning for dynamic instruction text.
4. **Bundle continuity**: Pass `instruction_bundle_json` through every topic. Each topic merges its skills and updates the variable for the next.
5. **Naming**: Use consistent CSV for `instructionNames` (e.g., `"role-customer-support-agent,core-skill-txt-response-guidelines"`). No spaces after commas.

---

## Related Documentation

- `docs/Agent Script Manual v4.md` — Agent Script language and execution model
- `docs/Apex Action Contracts.md` — Loader, Composer, LoadAndCompose API details
- [LTM Integration Mapping](LTM%20Integration%20Mapping.md) — Optional persistent memory: object schema and flow contracts (no LTM-Agentforce dependency)
- `docs/DMO Seeding Guide.md` — Seeding demo role/skill/workflow data
- `docs/Implementation Plan v1.md` — Framework implementation baseline
