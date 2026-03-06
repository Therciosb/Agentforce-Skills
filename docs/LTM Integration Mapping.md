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

## Flow Contracts

- Read: `Get_Agent_ContextObject`
  - input: `contact_id`
  - output: `context_record`
- Save: `Save_Agent_ContextObject`
  - inputs: `contact_id`, `context_record`, `new_summary`, `new_goal`, `has_issue`, `new_style`
  - output: `success`
  - The flow applies extracted scalars to `context_record` before upsert. The LLM must invoke the save action with slot-fill values for `new_summary`, `new_goal`, `has_issue`, `new_style`.

## Runtime Pattern Used

1. `start_agent` loads memory via read flow (`Get_Agent_ContextObject`).
2. Memory record mapped to `@variables.agent_context`.
3. Topics load and compose skills via `load_and_compose_skills` (Flow: `Load_And_Compose_Agent_Skills`), then consume memory context and composed instructions.
4. `finalization` persists updated memory through save flow (`Save_Agent_ContextObject`).

## Important Rules

- Keep `set @variables...=@outputs...` inside the `run` block.
- Access record outputs with `.data.<FieldApiName>` in prompt interpolation paths.
- Keep `system.instructions` static and use topic reasoning for dynamic instruction text.
