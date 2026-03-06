# Agent Skills Framework Implementation Plan

This document is the implemented in-repo plan baseline for the Agent Skills framework.

## Scope

- Agent Script architecture with deterministic instruction loading and prompt composition.
- CRM repository model for `roles`, `skills`, `workflows`, and references.
- Invocable Apex actions:
  - `Agent_Skill_Loader` (loads role/skill/workflow records)
  - `Agent_Skill_PromptComposer` (composes prompt-ready format)
  - `Agent_Skill_LoadAndCompose` (aggregates Load + Compose; invoked via Flow)
- Flow: `Load_And_Compose_Agent_Skills` (primary agent action target)
- Admin UI through Salesforce custom object tabs, app navigation, and permission sets.
- Customer Support demo scenario with seeded role/skills/workflows.
- Long-Term Memory alignment with `Agent_Context__c` and flow contracts.

## Implemented Metadata

- Objects:
  - `Agent_Skills_Repo__c` (consolidated roles, core skills, skills, workflows with Type__c)
  - `Agent_Context__c`
- Validation rules for naming convention:
  - `role-*` / `core-skill-*` / `skill-*` / `workflow-*` (enforced by Type__c)
- UI assets:
  - `Agent_Skills_Admin` custom app
  - tab for Agent_Skills_Repo__c
  - permission sets: `Agent_Skills_Author`, `Agent_Skills_Reviewer`, `Agent_Skills_Consumer`
- Agent bundles:
  - `customer_support_skill_demo`
  - `skill_load_test`

## Apex Contracts

### 1) Agent_Skill_Loader

- Purpose: load active role/skill/workflow records and produce a bundle JSON.
- Input:
  - `instructionNames` (CSV)
  - `includeReferences` (Boolean)
  - `version` (String)
  - `locale` (String)
- Behavior:
  - loads active-only records (`Status__c = 'active'`)
  - optional dependency expansion via `References__c` field on each record
  - filters by requested locale/version when provided
- Output:
  - `loadedInstructionBundle` (JSON string)
  - `skillsLoadedCount`
  - `timestamp`
  - `missingNames`
  - `warnings`

`loadedInstructionBundle` schema:

```json
{
  "skillsLoadedCount": 0,
  "timestamp": "2026-03-03T00:00:00Z",
  "bundles": [
    {
      "metadata": {
        "version": "v1",
        "name": "role-customer-support-agent",
        "status": "active"
      },
      "instructions": "..."
    }
  ]
}
```

### 2) Agent_Skill_PromptComposer

- Purpose: assemble prompt-ready instructions by combining:
  - global role/core-skill items from bundle
  - required skill/workflow seed names
  - recursive references
- Input:
  - `instructionBundle` (bundle JSON)
  - `requiredNames` (CSV)
  - `includeReferenceExpansion` (Boolean)
  - `maxReferenceDepth` (Integer)
  - `includeDeprecated` (Boolean)
- Output:
  - `composedInstructions`
  - `resolvedNames`
  - `missingNames`
  - `warnings`
- Deterministic ordering:
  - `role-*`
  - `core-skill-*`
  - `skill-*`
  - `workflow-*`
  - lexical within each group

## Agent Script Wiring

- `start_agent`:
  - loads memory (`flow://Get_Agent_ContextObject`)
  - loads role/core with `flow://Load_And_Compose_Agent_Skills` (action: `load_and_compose_skills`)
  - maps `loadedInstructionBundle` to `@variables.instruction_bundle_json`
  - transitions to first topic
- Each topic:
  - calls `flow://Load_And_Compose_Agent_Skills` with topic-specific `instructionNames` and `existingInstructionBundle`
  - maps `instructionsBundle` to `@variables.composed_instructions`, `loadedInstructionBundle` to `@variables.instruction_bundle_json`
- Topic reasoning:
  - places composed instructions at top
  - adds topic-specific routing/tool logic
- `finalization`:
  - persists context through `flow://Save_Agent_ContextObject`

## Demo Scenario

Role:
- `role-customer-support-agent`

Skills:
- `skill-product-information-qa`
- `skill-troubleshooting-support` (generic; references product workflows)
- `skill-support-case-management`
- `core-skill-user-otp-authentication`

Workflows:
- `workflow-support-case-lifecycle`
- `workflow-escalate-to-human`
- `workflow-troubleshooting-wifi-modem`
- `workflow-troubleshooting-5g-modem`
- `workflow-troubleshooting-iphone-16`
- `workflow-troubleshooting-iphone-16-pro`
- `workflow-troubleshooting-galaxy-s25`
- `workflow-troubleshooting-galaxy-s25-ultra`

## Seeding

- CSV seed artifacts:
  - `data/agent-skills/roles.csv`
  - `data/agent-skills/skills.csv`
  - `data/agent-skills/workflows.csv`
  - `data/agent-skills/references.csv`
- Apex seed utility:
  - `Agent_Skill_SeedService.seedCustomerSupportDemo()`
- Anonymous Apex runner:
  - `scripts/apex/seed_agent_skills.apex`

## LTM Integration (Optional)

For agents using persistent memory, implement per [LTM Integration Mapping](LTM%20Integration%20Mapping.md):

- Object: `Agent_Context__c`
- Flow contracts: `Get_Agent_ContextObject`, `Save_Agent_ContextObject`
- Runtime rules: map action outputs inside the same `run` block; use `.data.<FieldApiName>` for record payloads; keep `system.instructions` static

## Test Strategy

- Apex tests:
  - `Agent_Skill_Loader_Test`
  - `Agent_Skill_PromptComposer_Test`
  - `Agent_Skill_LoadAndCompose_Test`
- Validation scenarios:
  - active-only filtering
  - missing/deprecated handling
  - recursive dependency expansion
  - deterministic ordering

## Deployment and Verification

```bash
sf project deploy start --source-dir force-app/main/default --target-org <orgAlias>
sf apex run test --tests Agent_Skill_Loader_Test,Agent_Skill_PromptComposer_Test,Agent_Skill_LoadAndCompose_Test --target-org <orgAlias> --result-format human
sf apex run --file scripts/apex/seed_agent_skills.apex --target-org <orgAlias>
sf agent validate authoring-bundle --api-name customer_support_skill_demo --target-org <orgAlias>
sf agent publish authoring-bundle --api-name customer_support_skill_demo --target-org <orgAlias>
```
