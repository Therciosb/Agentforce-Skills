# LTM Integration Mapping

This document describes the optional Long-Term Memory (LTM) integration for agents that need persistent context across sessions. The Agent Skills framework **does not depend on any external LTM project**. You can implement the contracts below in your org, or use any compatible solution.

## Memory Object

- Object: `Agent_Context__c`
- Fields:
  - `Contact__c`
  - `Last_Topic_Summary__c`
  - `Pending_Goal__c`
  - `Unresolved_Issue__c`
  - `Communication_Style__c`
  - `User_Tier__c`

## Apex Action Contracts

The agents use **Apex invocable actions** directly (`apex://LoadAgentMemory`, `apex://SaveAgentContext`). This approach returns a formatted string for personalization and uses scalar-only inputs for save, which is more stable and easier to wire in Agent Script.

### LoadAgentMemory (Read)

- **Target:** `apex://LoadAgentMemory`
- **Inputs:** `contactId` (Text)
- **Outputs:**
  - `agentMemory` (Text) — formatted merge of all memory fields for prompt injection
  - `memorySummary`, `memoryGoal`, `hasIssue`, `memoryStyle` (for checkpoint agents)
- **Implementation:** Apex queries `Agent_Context__c` by Contact and formats fields into a single string.

### SaveAgentContext (Write)

- **Target:** `apex://SaveAgentContext`
- **Inputs:** `contactId`, `newSummary`, `newGoal`, `hasIssue`, `newStyle` (scalars only; no record payload)
- **Output:** `success` (Boolean)
- **Implementation:** Apex finds or creates `Agent_Context__c` by Contact and updates with scalar values.

## Runtime Pattern Used

1. `start_agent` loads memory via `apex://LoadAgentMemory`.
2. Formatted string mapped to `@variables.agent_memory` from `@outputs.agentMemory`.
3. Topics inject `agent_memory` in prompts: `Here is your past context. Use it for personalization:\n{!@variables.agent_memory}`
4. Topics load and compose skills via `load_and_compose_skills` (`apex://Agent_Skill_LoadAndCompose`), then consume memory and composed instructions.
5. `finalization` persists updated memory through `apex://SaveAgentContext` with scalar inputs only.

## Important Rules

- Keep `set @variables...=@outputs...` inside the `run` block.
- Use `agent_memory` (formatted string) directly in prompts; avoid dynamic merge expressions in `system.instructions`.
- Keep `system.instructions` static and use topic reasoning for dynamic instruction text.
- Save action: pass scalar inputs only (`contactId`, `newSummary`, `newGoal`, `hasIssue`, `newStyle`); no `context_record` input.
