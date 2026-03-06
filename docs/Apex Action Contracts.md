# Apex Action Contracts

## Agent_Skill_LoadAndCompose

Invocable Apex action that aggregates Load + Compose. Invoked by the `Load_And_Compose_Agent_Skills` Flow, which is the primary action target for agents.

### Input

- `instructionNames` (CSV string, optional when `existingInstructionBundle` provided for merge-only)
- `existingInstructionBundle` (JSON string, optional)
- `maxReferenceDepth` (Integer, optional, default 4)
- `includeReferences` (Boolean, optional, default true)
- `includeReferenceExpansion` (Boolean, optional, default true)

### Output

- `instructionsBundle` (formatted prompt-ready text)
- `loadedInstructionBundle` (raw JSON from loader)
- `skillsLoadedCount` (Integer)
- `composeRan` (Boolean)
- `warnings` (String)

### Behavior Rules

- Calls `Agent_Skill_Loader.load()` then `Agent_Skill_PromptComposer.compose()` when load succeeds.
- Supports merge-only: pass `existingInstructionBundle` with `instructionNames=""` to compose without loading new skills.
- `instructionNames` is optional (`required=false`) for merge-only scenarios.

---

## Agent_Skill_Loader

Invocable Apex action that retrieves active role/skill/workflow instructions.

### Input

- `instructionNames` (CSV string)
- `existingInstructionBundle` (JSON string, optional, for merge)
- `includeReferences` (Boolean)
- `version` (String, optional)
- `locale` (String, optional)

### Output

- `loadedInstructionBundle` (JSON string)
- `skillsLoadedCount` (Integer)
- `timestamp` (String, ISO-8601 UTC)
- `missingNames` (CSV string)
- `warnings` (String)

### Behavior Rules

- Includes only active records.
- Excludes deprecated records by default.
- Reports non-loaded requested items in diagnostics.

## Agent_Skill_PromptComposer

Invocable Apex action that assembles prompt-ready instruction text.

### Input

- `instructionBundle` (JSON string from loader output)
- `requiredNames` (CSV string)
- `includeReferenceExpansion` (Boolean)
- `maxReferenceDepth` (Integer)
- `includeDeprecated` (Boolean)

### Output

- `composedInstructions` (String)
- `resolvedNames` (CSV string)
- `missingNames` (CSV string)
- `warnings` (String)

### Behavior Rules

- Always includes available `role-*` and `core-skill-*` entries from bundle.
- Adds required seed names.
- Expands references recursively via `References__c` field on each record.
- Orders output deterministically.
