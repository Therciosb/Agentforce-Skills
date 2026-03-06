# Agent Script Manual (v4)

Complete developer guide for building Agentforce agents with Agent Script.

This document is designed for:
- Engineers implementing Agentforce agents in source control
- Teams using Salesforce CLI + VS Code (Agentforce DX)
- LLMs that need reliable context about Agent Script concepts and patterns

Primary references used in this rewrite:
- Salesforce Developer Guide: Agent Script, Reference, Blocks, Flow of Control, Patterns, and Agentforce DX
- Current repository implementation (`ltm_agent`, `ltm_agent_checkpoint`, Flow contracts)

---

## Table of Contents

1. What Agent Script Is
2. Language Model and Syntax
3. Execution Model (Flow of Control)
4. Core Blocks and Responsibilities
5. Variables: State Management
6. Actions vs Tools (Reasoning Actions)
7. Reasoning Instructions
8. Conditionals and Operators
9. Transitions and Routing
10. Before/After Reasoning
11. High-Value Patterns
12. Implementation Blueprint (Service and Employee Agents)
13. Long-Term Memory Reference Architecture (This Repo)
14. Testing, Validation, and Release Workflow
15. Troubleshooting Guide
16. Authoring Standards for LLM-Friendly Scripts
17. Glossary and Quick Reference

---

## 1) What Agent Script Is

Agent Script is Salesforce's language for building Agentforce agents with a hybrid approach:
- deterministic logic for business control (`if`, `run`, `set`, `transition`)
- natural-language prompt directives for LLM behavior (`| ...`)

Key value:
- predictable execution where reliability matters
- flexible conversational reasoning where language understanding matters

Agent Script is compiled when you save/publish agent versions.

---

## 2) Language Model and Syntax

Agent Script is:
- YAML-like and whitespace-sensitive
- block-structured
- based on `key: value` properties

Important syntax markers:
- `#` comment
- `|` prompt instruction sent to the LLM
- logic instructions (`if`, `run`, `set`, `transition to`)
- `@variables.<name>` global variables
- `@actions.<name>` action or tool reference
- `@outputs.<name>` output of the most recently run action in the current run scope
- `@topic.<name>` topic reference
- `@utils.<function>` utility functions (`setVariables`, `transition`, `escalate`)
- `{! ... }` inline interpolation in prompt text
- `...` slot-fill token (LLM supplies value, typically with `@utils.setVariables` or top-level reasoning actions)

Whitespace rules:
- use one indentation style consistently (spaces or tabs; do not mix)
- sibling properties must align
- nested properties require indentation

---

## 3) Execution Model (Flow of Control)

Agentforce execution rules to design around:

1. Every user turn starts at `start_agent`.
2. Script is processed top-to-bottom.
3. Deterministic logic executes before prompt reasoning.
4. LLM receives only the resolved prompt after deterministic preprocessing.
5. If a transition occurs, current prompt context is discarded and target topic is processed.
6. After topic execution, next user turn re-enters `start_agent`.

Practical implication:
- Put mandatory routing and guard logic first.
- Fetch required data before prompt text.
- Avoid expensive actions that could be skipped by immediate transitions.

---

## 4) Core Blocks and Responsibilities

### 4.1 `system`

Global agent behavior and standard messages:
- `system.instructions`
- `system.messages` (for example `welcome`, `error`)

Use for stable, broad behavior constraints. Avoid overloading with dynamic business logic.

### 4.2 `config`

Agent metadata and runtime configuration:
- `developer_name` (unique, naming rules apply)
- `default_agent_user` (required for service agents)
- `agent_label`
- `description`
- optional `role`, `company`, `agent_type`, locale/log settings

### 4.3 `variables`

Global cross-topic state.
- linked variables: bound to external runtime sources
- mutable (regular) variables: initialized defaults, updated in script

### 4.4 `language`

Locale configuration and supported locales for responses.

### 4.5 `topic <name>`

Primary work unit containing:
- topic metadata (`label`, `description`)
- `actions` (topic-defined deterministic actions)
- `reasoning` block (`instructions`, `reasoning.actions`)
- optional `before_reasoning` / `after_reasoning`

### 4.6 `start_agent <name>`

Special entry topic for routing and initial setup. Usually acts as topic selector.

---

## 5) Variables: State Management

Variables are global across topics and turns in a session.

Best practices:
- use explicit defaults (`""`, `False`, numeric baseline)
- use descriptive names (`order_return_eligible`, not `flag1`)
- persist outputs needed for deterministic control
- keep a small, intentional state model (avoid storing everything)

Typical uses:
- gate tools/topics with `available when`
- store outputs from deterministic actions
- reuse values across topics
- inject values into prompt text with `{!@variables.x}`

Null handling:
- `is None` checks unassigned/null
- `== ""` checks empty string
- treat them differently

---

## 6) Actions vs Tools (Reasoning Actions)

This distinction is critical.

### 6.1 Topic Actions (`topic.actions`)

Defined action contracts (Flow, Apex, prompt targets), with:
- `inputs`
- `outputs`
- `target`
- optional metadata (`description`, labels, confirmation/progress)

Use `run @actions.<name>` in deterministic logic to execute explicitly.

### 6.2 Tools / Reasoning Actions (`topic.reasoning.actions`)

Functions the LLM can choose to call.
They can wrap:
- topic actions
- `@utils.setVariables`
- `@utils.transition to @topic.x`
- `@utils.escalate`

Tool reliability depends heavily on:
- clear name
- precise description
- availability gating (`available when`)

### 6.3 Deterministic vs LLM-Selected

- Deterministic action call:
  - always runs when instruction path is reached
- Tool call:
  - only runs if LLM chooses it and availability conditions are met

Guideline:
- use deterministic `run` for business-critical workflows
- use tools where conversational discretion is desirable

---

## 7) Reasoning Instructions

`reasoning.instructions` resolves into final prompt text.

Guidelines:
- keep instructions short and explicit
- separate control logic from conversational text
- fetch/set variables before prompt lines that depend on them
- reference tools directly when usage conditions matter

Example:

```yaml
reasoning:
    instructions: ->
        if @variables.order_summary == "":
            run @actions.lookup_current_order
                with member_email=@variables.member_email
                set @variables.order_summary=@outputs.order_summary
        | Refer to the user by name {!@variables.member_name}.
        | Show order summary: {!@variables.order_summary}.
        | If they ask for details, use {!@actions.lookup_order_tool}.
```

---

## 8) Conditionals and Operators

Supported control model:
- `if`
- `else`
- no `else if` (use nested/stacked `if` blocks instead)

Common operators:
- comparison: `==`, `!=`, `<`, `<=`, `>`, `>=`, `is`, `is not`
- logical: `and`, `or`, `not`
- arithmetic: `+`, `-`

Design recommendations:
- keep conditions shallow and readable
- split complex checks into intermediate variables
- initialize variables to support deterministic checks

---

## 9) Transitions and Routing

Two transition modes:

1. Deterministic transition in logic:
   - `transition to @topic.X`
2. LLM-selectable transition tool:
   - `go_to_x: @utils.transition to @topic.X`

Transition behavior:
- one-way transfer
- current prompt context is discarded
- flow resumes from start of destination topic

Routing guidance:
- keep `start_agent` focused on routing and prerequisites
- use `go_to_` naming for transition tools
- gate transitions with `available when` where appropriate
- avoid transition loops

---

## 10) Before/After Reasoning

### `before_reasoning`

Same capability as deterministic logic at top of topic instructions; useful for setup.

### `after_reasoning`

Runs after reasoning loop exits on every request.

Use for:
- final variable normalization
- deterministic save/checkpoint actions
- post-response transitions

Constraints:
- do not use prompt pipe `|` in `after_reasoning`
- if topic transitions away early, original topic `after_reasoning` does not run
- when transitioning from `after_reasoning`, use `transition to` (not `@utils.transition`)

---

## 11) High-Value Patterns

### 11.1 Fetch Data Before Reasoning

Check cache variable, run action if empty, then prompt with resolved data.
Benefits: accuracy, lower hallucination risk, less stale context.

### 11.2 Action Chaining and Sequencing

Run actions in deterministic order when workflow requires strict sequencing.
Map outputs immediately to variables.

### 11.3 Filtering with `available when`

Hide tools/topics when business conditions are not met.
Use for policy enforcement and to reduce reasoning noise.

### 11.4 Required Workflow via Conditional Transition

Put mandatory routing checks at top of instructions.
Use for identity verification, compliance gates, prerequisite steps.

### 11.5 Resource References in Prompt

Reference tools and variables directly in text:
- `{!@actions.some_tool}`
- `{!@variables.some_value}`

This improves tool selection reliability.

### 11.6 System Instruction Overrides

Add a topic-level `system` block when that topic needs a different operating mode.
Use to avoid conflicts between global system tone/rules and topic needs.

---

## 12) Implementation Blueprint (Service and Employee Agents)

### 12.1 Service Agent Blueprint

- `start_agent`: classification + access gates
- identity/verification topic
- domain topics (orders, returns, billing, support)
- escalation path (`@utils.escalate` or escalation topic)
- finalization topic for closing and persistence

### 12.2 Employee Agent Blueprint

- `start_agent`: intent routing for internal workflows
- system-of-record lookup actions
- procedural topics (approvals, case updates, HR/IT workflows)
- policy filters on tools/topics
- completion topic with state persistence

### 12.3 Shared Blueprint Principles

- deterministic steps for compliance and critical actions
- LLM freedom for dialogue and adaptation
- explicit variable model as source of operational state
- bounded, testable transitions

---

## 13) Long-Term Memory Reference Architecture (This Repo)

This project implements persistent memory with Apex-backed flows that return a formatted string and accept scalar inputs for save.

### 13.1 Data and Actions

- Object: `Agent_Context__c`
- Read flow target: `flow://Get_Agent_ContextObject` (invokes `LoadAgentMemory` Apex)
- Save flow target: `flow://Save_Agent_ContextObject` (invokes `SaveAgentContext` Apex)
- Skill load/compose: `flow://Load_And_Compose_Agent_Skills` (action `load_and_compose_skills`; aggregates Loader + Composer)

### 13.2 Read Contract

- Inputs: `contact_id` (Text), `variable_name` (Text, optional)
- Output: `agent_memory` (Text) — formatted merge of all memory fields for prompt injection

### 13.3 Save Contract

- Inputs (scalars only): `contact_id`, `new_summary`, `new_goal`, `has_issue`, `new_style`
- Output: `success` (Boolean)

### 13.4 Script Pattern Used

1. `start_agent` loads LTM (guarded by `context_loaded`) and role/core via `load_and_compose_skills`
2. flow outputs mapped into `@variables.agent_memory`, `@variables.instruction_bundle_json`, `@variables.composed_instructions`
3. each topic calls `load_and_compose_skills` with topic-specific `instructionNames` and `existingInstructionBundle`
4. topic reasoning personalizes using `agent_memory` (formatted string) and `composed_instructions`
5. finalization performs a final deterministic save with scalar inputs only

### 13.5 Memory Access Rule

Inject `agent_memory` (formatted string) directly in prompts:

```
Here is your past context. Use it for personalization:
{!@variables.agent_memory}
```

### 13.6 Mapping Rule (Critical)

Set outputs in the same `run` block:

```yaml
run @actions.load_user_memory
    with contact_id=@variables.ContactId
    set @variables.agent_memory=@outputs.agent_memory
    set @variables.context_loaded=True
```

Avoid output mapping outside the `run` scope.

---

## 14) Testing, Validation, and Release Workflow

Recommended developer loop:

1. Validate script
2. Deploy dependencies (objects, flows, permission sets)
3. Publish authoring bundle
4. Preview/test with realistic scenarios
5. Iterate and republish

Core commands:

```bash
sf agent validate authoring-bundle --api-name <api_name> --target-org <org>
sf project deploy start --source-dir force-app/main/default --target-org <org>
sf agent publish authoring-bundle --api-name <api_name> --target-org <org>
sf agent preview --api-name <api_name> --target-org <org>
```

Always retest after publishing.

---

## 15) Troubleshooting Guide

### Issue: Generic error after successful Flow step

Check:
1. output mappings are inside `run`
2. prompt references use valid variable paths
3. transitions are not bypassing expected blocks
4. no conflicting system/topic instructions

### Issue: Tool is never called

Check:
1. tool name/description clarity
2. `available when` conditions are true
3. required inputs are available
4. explicit reference in prompt where appropriate

### Issue: Transition behavior is unexpected

Check:
1. deterministic transitions at top of instructions
2. no accidental loops between topics
3. understanding that previous prompt context is discarded

### Issue: Null or empty personalization

Check:
1. upstream action outputs
2. variable defaults and null checks
3. `.data` path usage for record payloads
4. conditional guards before prompt interpolation

### Issue: YAML anchors/aliases cause parse errors

Agent Script uses a custom parser; YAML anchors (`&`) and aliases (`*`) are **not supported**. Avoid them; repeat action definitions per topic.

### Issue: Escalation does not work

Check:
1. messaging connection configured
2. Omni-Channel route setup
3. runtime user permissions and routing config

---

## 16) Authoring Standards for LLM-Friendly Scripts

For maintainability and better model behavior:

- Use consistent domain vocabulary across topics/actions/variables.
- Keep names specific and non-overlapping.
- Keep descriptions concrete and outcome-oriented.
- Keep prompts concise; avoid long multi-objective instructions.
- Separate deterministic logic from conversational instructions.
- Keep transition/action side effects explicit.
- Prefer small focused topics over monolithic topics.
- Add comments for intent, not obvious mechanics.

Recommended naming:
- transition tools: `go_to_<topic>`
- boolean variables: `is_*`, `has_*`, `*_loaded`, `*_dirty`
- action names: `verb_object` (`lookup_order`, `save_context`)

---

## 17) Glossary and Quick Reference

- **Agent Script**: Hybrid deterministic + LLM agent language.
- **Topic**: Work unit with reasoning + actions/tools.
- **Start Agent**: Entry topic for every turn.
- **Action**: Deterministic executable contract (Flow/Apex/prompt).
- **Tool**: LLM-callable reasoning action.
- **Variable**: Global session state.
- **Transition**: One-way topic handoff.
- **`available when`**: Deterministic visibility filter for tools/topics.
- **Slot filling (`...`)**: LLM populates input values.

Quick snippets:

```yaml
# Deterministic action
run @actions.lookup_order
    with order_id=@variables.order_id
    set @variables.order_status=@outputs.status
```

```yaml
# LLM-callable tool
actions:
    capture_order_info: @utils.setVariables
        with order_id=...
        with customer_email=...
        available when @variables.verified == True
```

```yaml
# Required workflow gate
if @variables.verified == False:
    transition to @topic.Identity
```

---

## Scope Note

This manual is implementation-oriented and optimized for engineering use.  
Treat it as a practical companion to Salesforce official docs, not a replacement for release notes and org-specific validation.
