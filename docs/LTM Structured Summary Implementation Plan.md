# LTM Structured Summary Implementation Plan

**Document Version:** 1.0  
**Created:** March 2025  
**Status:** Draft  
**Target:** `core-skill-ltmManagement-service-agent` in Agentforce-Skills

---

## 1. Overview

This plan describes the implementation of a **structured new_summary format** for the LTM (Long-Term Memory) skill. The change replaces the current flat 4–5 sentence summary with a well-defined, sectioned format that improves retrieval, merge behavior, and long-term memory effectiveness.

### 1.1 Current State

- **Skill:** `core-skill-ltmManagement-service-agent`
- **Location:** `Agent_Skill_SeedService.cls` (seeded into `Agent_Skills_Repo__c`)
- **Current new_summary rule:** "Detailed 4-5 sentence summary combining (a) last session summary from agent_memory when available, and (b) this session: user inputs, assistant recommendations, actions taken, and outcomes."

### 1.2 Target State

- **new_summary** will be a Markdown-formatted string with five sections:
  - User Context
  - Issues & Resolution Status
  - Pending Goals
  - Key Facts & Decisions
  - Session Highlights

---

## 2. Proposed Structure (Reference)

```
## User Context
[Account tier, key identifiers, communication preferences. 1–3 sentences.]

## Issues & Resolution Status
[Each issue: description, status (Open/Resolved/Escalated), resolution if any.]

## Pending Goals
[User-stated or implied unfinished goals. 1–3 bullet points.]

## Key Facts & Decisions
[Important facts, decisions, commitments. 1–2 lines per item.]

## Session Highlights
[2–3 sentences per recent session. Prepend this session; keep last 2–3 sessions.]
```

---

## 3. Implementation Tasks

### 3.1 Update Agent_Skill_SeedService.cls

**File:** `force-app/main/default/classes/Agent_Skill_SeedService.cls`

**Change:** Replace the `new_summary` extraction rule within the `core-skill-ltmManagement-service-agent` skill content (around lines 63–65).

**Current text to replace:**
```
'- **new_summary:** Extract when transitioning to a topic that persists session context (e.g. session end, handoff, checkpoint). Value: Detailed 4-5 sentence summary combining (a) last session summary from agent_memory when available, and (b) this session: user inputs, assistant recommendations, actions taken, and outcomes.\n\n' +
```

**New text:**
```
'- **new_summary:** Extract when transitioning to a topic that persists session context (e.g. session end, handoff, checkpoint). Value: A structured summary in Markdown format with these sections:\n\n' +
'  - **## User Context** — Account tier, key identifiers, communication preferences (1–3 sentences). Update when preferences change.\n\n' +
'  - **## Issues & Resolution Status** — Each issue: brief description, status (Open/Resolved/Escalated), resolution if any. Append new issues; update status of existing ones.\n\n' +
'  - **## Pending Goals** — User-stated or implied unfinished goals. Replace with current list; remove when achieved.\n\n' +
'  - **## Key Facts & Decisions** — Important facts (IDs, choices), decisions, commitments. Append new; remove when obsolete.\n\n' +
'  - **## Session Highlights** — 2–3 sentences per recent session (what was discussed, actions taken, outcomes). Prepend this session; keep last 2–3 sessions; prune older.\n\n' +
'  When merging with prior context from agent_memory, preserve existing sections and update only the parts that changed. Do not duplicate information across sections.\n\n' +
```

**Note:** Ensure proper escaping of backslashes and quotes in the Apex string literals.

### 3.2 Optional: Update LTM Hydration Instructions

**File:** Same (`Agent_Skill_SeedService.cls`)

**Consideration:** The LTM HYDRATION section currently says:
> "Here is your past context. Use it for personalization:\n{!@variables.agent_memory}"

**Optional addition:** Add a brief note that `agent_memory` may contain structured sections and the agent should use them for targeted retrieval (e.g., check Pending Goals before asking, use Issues & Resolution Status for continuity).

**Proposed addition (optional):**
```
'The context may include structured sections (User Context, Issues & Resolution Status, Pending Goals, Key Facts & Decisions, Session Highlights). Use the relevant sections for personalization and continuity.\n\n' +
```

### 3.3 No Changes Required

| Component | Reason |
|-----------|--------|
| **Agent_Context__c** | `Last_Topic_Summary__c` is Long Text Area; structured Markdown fits without schema change |
| **SaveAgentContext.cls** | Accepts `newSummary` as string; no change needed |
| **LoadAgentMemory.cls** | Reads and formats `Last_Topic_Summary__c` into `agent_memory`; structured content flows through |
| **Flow contracts** | `new_summary` remains a scalar text input; contract unchanged |
| **Agent Script (.agent files)** | `save_context_tool` / `persist_memory` action signatures unchanged |

---

## 4. Seeding and Deployment

### 4.1 Re-seed the Skill

After updating `Agent_Skill_SeedService.cls`:

1. **Option A — Full re-seed:** Run the seed logic to recreate `Agent_Skills_Repo__c` records. This overwrites existing skill content.
2. **Option B — Update existing record:** If the skill is already in use, update the `Agent_Skills_Repo__c` record for `core-skill-ltmManagement-service-agent` with the new content (via Data Loader, Flow, or Apex).

**Caution:** Re-seeding may affect other skills. Prefer updating only the LTM skill record if other skills are in production.

### 4.2 Deployment Steps

1. Deploy `Agent_Skill_SeedService.cls` to the target org.
2. Execute re-seed or manual update of `core-skill-ltmManagement-service-agent`.
3. Verify the skill is loaded by agents that use `instructionNames="core-skill-ltmManagement-service-agent"` (e.g., `customer_support_skill_demo`, `skill_load_test`).

---

## 5. Testing

### 5.1 Unit Tests

- **Agent_Skill_SeedServiceTest.cls:** If it asserts skill content, update expectations to include the new `new_summary` rule text.
- **No Apex changes** to SaveAgentContext or LoadAgentMemory; existing tests remain valid.

### 5.2 Manual Testing

| Test Case | Steps | Expected Result |
|-----------|-------|-----------------|
| **First session (no prior context)** | New user; complete conversation; trigger persist at session end | `new_summary` contains all five sections with content from this session only |
| **Second session (with prior context)** | Return user; have conversation; trigger persist | `new_summary` merges prior sections with new Session Highlights; Issues/Goals/Facts updated as appropriate |
| **Retrieval** | Load memory in new session; ask about prior issue | Agent uses Issues & Resolution Status and Session Highlights for continuity |
| **Section pruning** | Multiple sessions over time | Session Highlights keeps last 2–3 sessions; older content pruned |

### 5.3 Validation Checklist

- [ ] New skill content deployed and visible in `Agent_Skills_Repo__c`
- [ ] Agent loads skill via `load_and_compose_skills`
- [ ] Save action receives structured `new_summary` with section headings
- [ ] `Agent_Context__c.Last_Topic_Summary__c` stores full structured content
- [ ] Load flow returns `agent_memory` with structured content for prompt injection
- [ ] Agent responses reflect personalized context from sections

---

## 6. Rollback

If issues arise:

1. Revert `Agent_Skill_SeedService.cls` to the previous `new_summary` rule.
2. Re-seed or manually restore the prior skill content in `Agent_Skills_Repo__c`.
3. Existing `Agent_Context__c` records retain whatever was last saved; no data migration needed. New sessions will produce flat summaries again.

---

## 7. Documentation Updates

After implementation:

| Document | Update |
|----------|--------|
| **LTM Integration Mapping.md** | Add note that `new_summary` uses structured Markdown format; reference this plan |
| **Agent-Skills-Framework-for-FDE.md** | Update LTM skill description if it references summary format |
| **This plan** | Mark status as Implemented; add completion date |

---

## 8. Dependencies and Risks

| Item | Notes |
|------|-------|
| **Agentforce-LTM** | No code changes required. Compatible with existing `Agent_Context__c` and flows. |
| **Token usage** | Structured format may be slightly longer; monitor if token limits are a concern. |
| **LLM compliance** | The new rule is more prescriptive; validate that the model consistently produces the structure. |
| **Backward compatibility** | Existing flat summaries in `Last_Topic_Summary__c` will still load; agent will receive them as-is. New saves will use the structured format. |

---

## 9. Appendix: Full New Extraction Rule Text

For copy-paste into the skill content:

```
**new_summary:** Extract when transitioning to a topic that persists session context (e.g. session end, handoff, checkpoint). Value: A structured summary in Markdown format with these sections:

- **## User Context** — Account tier, key identifiers, communication preferences (1–3 sentences). Update when preferences change.
- **## Issues & Resolution Status** — Each issue: brief description, status (Open/Resolved/Escalated), resolution if any. Append new issues; update status of existing ones.
- **## Pending Goals** — User-stated or implied unfinished goals. Replace with current list; remove when achieved.
- **## Key Facts & Decisions** — Important facts (IDs, choices), decisions, commitments. Append new; remove when obsolete.
- **## Session Highlights** — 2–3 sentences per recent session (what was discussed, actions taken, outcomes). Prepend this session; keep last 2–3 sessions; prune older.

When merging with prior context from agent_memory, preserve existing sections and update only the parts that changed. Do not duplicate information across sections.
```

---

*Document Version: 1.0 | March 2025*
