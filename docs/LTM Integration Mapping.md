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

## Flow Contracts (Recommended: Apex-Backed)

The recommended implementation uses **Apex-backed flows** that invoke `LoadAgentMemory` and `SaveAgentContext` invocable actions. This approach returns a formatted string for personalization and uses scalar-only inputs for save, which is more stable and easier to wire in Agent Script.

### Get_Agent_ContextObject (Read)

- **Inputs:** `contact_id` (Text), `variable_name` (Text, optional, default: agent_memory)
- **Outputs:**
  - `agent_memory` (Text) — formatted merge of all memory fields for prompt injection
  - `memory_summary`, `memory_goal`, `memory_has_issue`, `memory_style` (for checkpoint agents)
- **Implementation:** Flow invokes `LoadAgentMemory` Apex action, which queries `Agent_Context__c` by Contact and formats fields into a single string.

### Save_Agent_ContextObject (Write)

- **Inputs:** `contact_id`, `new_summary`, `new_goal`, `has_issue`, `new_style` (scalars only; no record payload)
- **Output:** `success` (Boolean)
- **Implementation:** Flow invokes `SaveAgentContext` Apex action, which finds or creates `Agent_Context__c` by Contact and updates with scalar values.

## Runtime Pattern Used

1. `start_agent` loads memory via read flow (`Get_Agent_ContextObject`).
2. Formatted string mapped to `@variables.agent_memory`.
3. Topics inject `agent_memory` in prompts: `Here is your past context. Use it for personalization:\n{!@variables.agent_memory}`
4. Topics load and compose skills via `load_and_compose_skills` (Flow: `Load_And_Compose_Agent_Skills`), then consume memory and composed instructions.
5. `finalization` persists updated memory through save flow (`Save_Agent_ContextObject`) with scalar inputs only.

## Important Rules

- Keep `set @variables...=@outputs...` inside the `run` block.
- Use `agent_memory` (formatted string) directly in prompts; avoid dynamic merge expressions in `system.instructions`.
- Keep `system.instructions` static and use topic reasoning for dynamic instruction text.
- Save action: pass scalar inputs only (`new_summary`, `new_goal`, `has_issue`, `new_style`); no `context_record` input.
