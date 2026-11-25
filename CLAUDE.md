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
sf apex run test --tests Agent_Skill_Catalog_Test,Agent_Skill_Loader_Test,Agent_Skill_PromptComposer_Test,Agent_Skill_LoadAndCompose_Test,Agent_Skill_State_Test,Agent_Skill_Binding_Controller_Test,Agent_Skill_Test_Runner_Test --target-org <org> --result-format human

# Run a single Apex test class
sf apex run test --tests GenericRenderActionTest --target-org <org> --result-format human

# Seed demo instruction records (and Agent_Context__c records if that object exists)
sf apex run --file scripts/apex/seed_agent_skills.apex --target-org <org>

# Seed agent wiring (bindings) and skill routing test cases for the pd2 demo agent
sf apex run --file scripts/apex/seed_agent_skill_bindings.apex --target-org <org>
sf apex run --file scripts/apex/seed_agent_skill_tests.apex --target-org <org>

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

Layered classes, all in `force-app/main/default/classes/`:

- `Agent_Skill_Catalog` — the single record lookup used by Loader, Composer, and HeaderProvider. Picks the live version per name (numeric version order, effective window, not Rejected, Approved when `requireApproval`), cached per transaction and in the `AgentSkills` org cache partition. `Agent_Skills_Repo_Trigger` invalidates entries on change.
- `Agent_Skill_Loader` — resolves `instructionNames` CSV → records via the catalog, expands `References__c`, and produces a `loadedInstructionBundle` (JSON). Accepts `existingInstructionBundle` to **merge** across calls.
- `Agent_Skill_PromptComposer` — takes a bundle JSON and recursively expands references (`maxReferenceDepth`, default 4) into a single concatenated `composedInstructions` string. Rewrites `[[tool:Name]]` indicators to `@actions.snake_name`, validated against `knownActionNames` when given.
- `Agent_Skill_LoadAndCompose` — Loader then Composer in one call (`apex://Agent_Skill_LoadAndCompose`, or `flow://Load_And_Compose_Agent_Skills`). Optional `locale`, `requireApproval`, `knownActionNames`.
- `Agent_Skill_State` — the action wired agents call (`apex://Agent_Skill_State`). Takes `agentName` + `requestedSkills`, reads the agent's binding, and returns a `SkillState` object: `skill_menu`, `active_skills`, `skill_instructions`, `skill_warnings`, and a `tools` map of action names the active skills reference. Publishes an `Agent_Skill_Usage__e` per call (logged to `Agent_Skill_Usage_Log__c`) unless `recordUsage` is false.

`Agent_Skill_SeedService` backs the anonymous-apex seed scripts.

### Wiring skills to agents (data, in the Admin app's Agents tab)

`Agent_Skill_Binding__c` (one per agent, keyed by `Agent_Developer_Name__c`) with `Agent_Skill_Binding_Item__c` rows: `Always` (loaded every turn), `Selectable` (in the skill menu), `Default` (active when nothing else is requested). The binding also holds `Require_Approval__c` and `Agent_Tools__c` (CSV of the agent's action names; skills may only reference these). Changing wiring is a data change — no republish.

The Tests tab (`Agent_Skill_Test_Case__c` / `Agent_Skill_Test_Result__c`, `Agent_Skill_Test_Runner`) routes each utterance through the `Route_Agent_Skill` prompt template against the agent's real skill menu, checks the chosen skills and enabled tools, and exports a Testing Center spec.

### How agents consume it (Agent Script, in `aiAuthoringBundles/`)

**Wired agents (preferred, e.g. `customer_support_progressive_pd2`)** use one host subagent and no skill names in the script:

1. `skill_state: mutable object = {"active_skills": "unloaded"}` and `requested_skills: mutable string = ""`. The non-empty default matters: reading a missing field makes the whole `if` false.
2. Reasoning runs `load_skill_state` when `requested_skills != skill_state.active_skills`, then injects `{!@variables.skill_state.skill_menu}` and `{!@variables.skill_state.skill_instructions}`.
3. A `switch_skills` `@utils.setVariables` tool sets `requested_skills`; instructions re-resolve after the tool runs, so the reload happens in the same turn.
4. Each skill-owned tool has `available when @variables.skill_state.tools.<action> == True`.

Object fields are read-only: replace the whole object from an action output; never `set` or `setVariables` a single field. The Agents tab's "Agent Script snippet" button generates this scaffold.

**Legacy topic agents** follow this contract:

1. **`start_agent`** loads role + core skills, stores the JSON in `@variables.instruction_bundle_json`, then transitions to the first topic.
2. **Each topic** calls Load_And_Compose with its own `instructionNames` plus `existingInstructionBundle=@variables.instruction_bundle_json`, then updates both `instruction_bundle_json` and `composed_instructions`, and injects `{!@variables.composed_instructions}` into reasoning.

**Critical Agent Script rules** (see `docs/Agent-Skills-Framework-for-FDE.md` §4.7):
- Map outputs with `set @variables.x=@outputs.y` **inside the same `run` block** — mapping outside it can error.
- Keep `system.instructions` static; put dynamic instruction text only in topic reasoning.
- Thread `instruction_bundle_json` through every topic so each merges onto the prior bundle.
- `instructionNames` CSV has **no spaces after commas**.

Bundles:
- `customer_support_progressive_pd2` — the wired reference agent: `Agent_Skill_State`, skill switching, tool gating, LTM with a deterministic save in `after_reasoning`.
- `skill_load_test` — minimal agent to validate the load/compose pipeline (no LTM).
- `customer_support_skill_demo` — full demo with **optional** LTM via `Agent_Context__c` and the Get/Save agent-context flows (`agent_memory` injected directly as `{!@variables.agent_memory}`). See `docs/LTM Integration Mapping.md`.
- `render_data_test` — exercises the Generic Render Action.

Published agents materialize as `genAiPlannerBundles/<bundle>_v<N>/` in the org. That folder is generated output and is git-ignored; the editable source of truth is the `.agent` file in `aiAuthoringBundles/`.

### Generic Render Action (structured UI in agent responses)

`GenericRenderAction` (`@InvocableMethod` "Render Data") validates a JSON payload + `display_type` (`table`/`card`/`list`/`key-value`), returns a `GenericRenderOutput`, and the `genericDataRenderer` LWC renders it in the agent UI. Bridged to agents via the `Render_Data` flow. See `docs/Generic-Render-Action-Implementation-Plan.md`, `docs/LWC-in-Agent-Responses-Guide.md`, and `docs/Render-Data-LWC-Troubleshooting.md`.

### Permission sets

`Agent_Skills_Agent_Runtime` must be assigned to the **agent bot user** for runtime access. `Agent_Skills_Author`/`Reviewer`/`Consumer` gate the Admin app (`Agent_Skills_Admin`).

## Key documentation

- `docs/Agent-Skills-Framework-for-FDE.md` — primary engineering reference (composition flow + Agent Script rules)
- `docs/Apex Action Contracts.md` — Loader/Composer/LoadAndCompose I/O contracts
- `docs/Agent Script Manual v5.md` — Agent Script language and execution model
- `docs/LTM Integration Mapping.md` — optional persistent-memory object schema and flow contracts
