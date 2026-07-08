# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A reusable **Agent Skills framework** for Agentforce. Agent instructions (roles, core skills, skills, workflows) live as `Agent_Skills_Repo__c` records in the CRM rather than hardcoded in agent bundles. At runtime, Apex invocable actions load the relevant records, recursively expand their references, and compose prompt-ready text that agents inject into topic reasoning. Editing instructions is a data change, not a redeploy.

This is a Salesforce SFDX project (`force-app/main/default`, API 66.0, no namespace). It is fully standalone — it does **not** depend on any LTM-Agentforce project, even though one demo agent optionally integrates Long-Term Memory.

## Commands

```bash
# Deploy everything
sf project deploy start --source-dir force-app/main/default --target-org <org>

# Run the core Apex test suite
sf apex run test --tests Agent_Skill_Loader_Test,Agent_Skill_PromptComposer_Test,Agent_Skill_LoadAndCompose_Test --target-org <org> --result-format human

# Run a single Apex test class
sf apex run test --tests GenericRenderActionTest --target-org <org> --result-format human

# Seed demo instruction records (and Agent_Context__c records if that object exists)
sf apex run --file scripts/apex/seed_agent_skills.apex --target-org <org>

# Validate / publish an agent authoring bundle
sf agent validate authoring-bundle --api-name skill_load_test --target-org <org>
sf agent publish  authoring-bundle --api-name skill_load_test --target-org <org>

# JS tooling
npm run lint            # eslint over aura/lwc
npm run test:unit       # sfdx-lwc-jest
npm run prettier        # format cls/html/xml/etc.
```

Targeted deploys use the pre-built manifests in `manifest/` (`package-apex.xml`, `package-deploy-objects.xml`, `package-ui.xml`, `package-no-agent.xml`, etc.) — prefer these over hand-rolling `--metadata` lists.

## Architecture

### Instruction taxonomy (data, in `Agent_Skills_Repo__c`)

Every record has a `Name__c` following a strict prefix convention, plus `Status__c` (`active`/`deprecated`), `Version__c`, `Locale__c`, and `References__c` (a no-spaces CSV of other record names):

- `role-*` — agent persona/identity
- `core-skill-*` — cross-cutting behaviors loaded for every topic
- `skill-*` — topic-specific capabilities
- `workflow-*` — procedures; referenced by skills and by other workflows

Seed data lives in `data/agent-skills/{roles,skills,workflows,references}.csv`.

### Runtime composition pipeline (Apex invocable actions)

Three classes form a layered pipeline, all in `force-app/main/default/classes/`:

- `Agent_Skill_Loader` — resolves `instructionNames` CSV → records, filters by status/version/locale, expands `References__c`, and produces a `loadedInstructionBundle` (JSON). Accepts `existingInstructionBundle` to **merge** across calls.
- `Agent_Skill_PromptComposer` — takes a bundle JSON and recursively expands references (`maxReferenceDepth`, default 4) into a single concatenated `composedInstructions` string for the prompt.
- `Agent_Skill_LoadAndCompose` — the façade agents actually call (`apex://Agent_Skill_LoadAndCompose`, or via `flow://Load_And_Compose_Agent_Skills`). Runs Loader then Composer, returning both `instructionsBundle` (prompt text) and `loadedInstructionBundle` (raw JSON for the next merge).

`Agent_Skill_SeedService` backs the anonymous-apex seed scripts.

### How agents consume it (Agent Script, in `aiAuthoringBundles/`)

The contract every agent follows:

1. **`start_agent`** loads role + core skills, stores the JSON in `@variables.instruction_bundle_json`, then transitions to the first topic.
2. **Each topic** calls Load_And_Compose with its own `instructionNames` plus `existingInstructionBundle=@variables.instruction_bundle_json`, then updates both `instruction_bundle_json` and `composed_instructions`, and injects `{!@variables.composed_instructions}` into reasoning.

**Critical Agent Script rules** (see `docs/Agent-Skills-Framework-for-FDE.md` §4.7):
- Map outputs with `set @variables.x=@outputs.y` **inside the same `run` block** — mapping outside it can error.
- Keep `system.instructions` static; put dynamic instruction text only in topic reasoning.
- Thread `instruction_bundle_json` through every topic so each merges onto the prior bundle.
- `instructionNames` CSV has **no spaces after commas**.

Bundles:
- `skill_load_test` — minimal agent to validate the load/compose pipeline (no LTM).
- `customer_support_skill_demo` — full demo with **optional** LTM via `Agent_Context__c` and the Get/Save agent-context flows (`agent_memory` injected directly as `{!@variables.agent_memory}`). See `docs/LTM Integration Mapping.md`.
- `render_data_test` — exercises the Generic Render Action.

Published agents materialize as `genAiPlannerBundles/<bundle>_v<N>/` — these are versioned generated output; the editable source of truth is the `.agent` file in `aiAuthoringBundles/`.

### Generic Render Action (structured UI in agent responses)

`GenericRenderAction` (`@InvocableMethod` "Render Data") validates a JSON payload + `display_type` (`table`/`card`/`list`/`key-value`), returns a `GenericRenderOutput`, and the `genericDataRenderer` LWC renders it in the agent UI. Bridged to agents via the `Render_Data` flow. See `docs/Generic-Render-Action-Implementation-Plan.md`, `docs/LWC-in-Agent-Responses-Guide.md`, and `docs/Render-Data-LWC-Troubleshooting.md`.

### Self-Learning Harness (optional, reusable)

A drop-in harness that lets any Agentforce agent **learn from its own runtime
outcomes** — surface relevant past lessons at the start of a turn, record whether the
turn resolved the problem, capture new lessons on failure-then-success, and reward
lessons that prove helpful. Fully generic: keyed by `agent_api_name` + `topic_area`,
with **no domain hardcoding**.

- **Objects:** `AgentLessonLearned__c`, `AgentSession__c`, `AgentActionOutcome__c`,
  `AgentImprovementConfig__c`, `AgentRewardConfig__c`, `AgentSubagentConfig__c`,
  `AgentReward__e` (platform event).
- **Apex:** `SelectRelevantLessons` (lesson pool + PT semantic rank),
  `AgentRewardHandler` (+ `AgentRewardTrigger`), `ClassifyAgentOutcome`, `AesCalculator`,
  `ConversationHistoryProvider`, `LessonJsonParser`/`LessonRelevanceParser`, and the
  `Sia*Controller` back-ends for the console.
- **Flows:** `Load_Improvement_Context` → `Check_Lessons_Learned` + `Get_Agent_Points`;
  `Extract_And_Record_Lesson_Flow`; `Publish_Reward_Event`.
- **Prompt templates:** `Select_Relevant_Lessons`, `Extract_And_Record_Lesson`.
- **UI:** the `SIA_Console` Lightning app (11 `sia*` LWCs, tab, flexipage,
  `SelfImprovingAgentContext` message channel, `SIA_App_Icon`).
- **Permission sets:** `SIA_Framework_Access` (agent runtime user — also needs
  `EinsteinGPTPromptTemplateUser`), `SIA_Admin` (console users).
- **Wired example:** `customer_support_skill_demo`'s `troubleshooting_support` topic
  demonstrates the load→outcome→lesson→reward loop. See
  **`docs/Self-Learning-Harness-for-FDE.md`** for the full wiring guide and the
  deterministic-`run`-vs-prose rule.
- **Test harness:** `test-harness/` (`run_agent_tests.mjs`, `run_preview_tests.mjs`,
  `run_runtime_tests.mjs`) drives CSV-defined multi-turn conversations against any
  activated agent — see `test-harness/README.md`.

### Permission sets

`Agent_Skills_Agent_Runtime` must be assigned to the **agent bot user** for runtime access. `Agent_Skills_Author`/`Reviewer`/`Consumer` gate the Admin app (`Agent_Skills_Admin`). For the self-learning harness, assign `SIA_Framework_Access` to the agent bot user and `SIA_Admin` to SIA Console users.

## Key documentation

- `docs/Agent-Skills-Framework-for-FDE.md` — primary engineering reference (composition flow + Agent Script rules)
- `docs/Self-Learning-Harness-for-FDE.md` — self-learning harness components, runtime loop, and agent-wiring guide
- `docs/Apex Action Contracts.md` — Loader/Composer/LoadAndCompose I/O contracts
- `docs/Agent Script Manual v4.md` — Agent Script language and execution model
- `docs/LTM Integration Mapping.md` — optional persistent-memory object schema and flow contracts
