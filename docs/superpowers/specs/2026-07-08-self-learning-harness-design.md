# Self-Learning Harness Port — Design

**Date:** 2026-07-08
**Target repo:** `Agentforce-Skills` (Agent Skills Framework)
**Source repo:** `Smartsheet/Service-Agent-Script` (Smartsheet Support Agent + self-learning framework)

## Goal

Bring the **self-learning harness** (a.k.a. self-improving / SIA framework) from the
Smartsheet Service Agent project into the reusable `Agentforce-Skills` framework repo —
**only the reusable harness infrastructure**, none of the Smartsheet-specific agent
content (support-tier logic, Pro Desk, billing/finance classification, AQWK knowledge
functions, gap test data, POC result docs).

## What the harness does

The harness lets any Agentforce agent **learn from its own runtime outcomes**:

1. **Load** relevant past lessons for the current topic at the start of a turn
   (`Load_Improvement_Context` → `SelectRelevantLessons` Apex → `Select_Relevant_Lessons`
   prompt template).
2. **Classify** the outcome of each action/turn (`ClassifyAgentOutcome`,
   `set_knowledge_outcome`), recording `AgentActionOutcome__c` and rolling up an
   Agent Efficiency Score (AES) onto `AgentSession__c` via `AesCalculator`.
3. **Capture** new lessons when a gap/failure is detected
   (`Extract_And_Record_Lesson` prompt + `Extract_And_Record_Lesson_Flow` →
   `AgentLessonLearned__c`), with a dedup guard.
4. **Reward** applied lessons and good outcomes via a config-driven Platform Event
   (`Publish_Reward_Event` → `AgentReward__e` → `AgentRewardTrigger` →
   `AgentRewardHandler`), crediting `times_referenced__c` / `times_successful__c`
   and adjusting `confidence_score__c`.
5. **Govern** it all through config objects (`AgentImprovementConfig__c`,
   `AgentRewardConfig__c`, `AgentSubagentConfig__c`) and inspect it through the
   **SIA Console** Lightning app (11 `sia*` LWCs + controllers).

Everything is keyed generically by `agent_api_name__c` + `topic_area__c` — verified to
contain **zero Smartsheet hardcoding** across objects, Apex, flows, prompt templates,
and LWC.

## Inventory (what comes over)

### Custom objects (7)
`AgentLessonLearned__c`, `AgentSession__c`, `AgentActionOutcome__c`,
`AgentImprovementConfig__c`, `AgentRewardConfig__c`, `AgentSubagentConfig__c`,
`AgentReward__e` (platform event). All fields, keyed by `agent_api_name__c`/`topic_area__c`.

### Apex (classes + tests, all generic)
- Runtime: `SelectRelevantLessons`, `LessonJsonParser`, `LessonRelevanceParser`,
  `ConversationHistoryProvider`, `AesCalculator`, `ClassifyAgentOutcome`,
  `AgentRewardHandler`
- SIA console controllers: `SiaConfigController`, `SiaMetricsController`,
  `SiaSessionController`, `SiaKnowledgeController`
- Trigger: `AgentRewardTrigger` (on `AgentReward__e`)
- Companion `*_Test` classes for each.

### Flows (4)
`Check_Lessons_Learned`, `Load_Improvement_Context`, `Publish_Reward_Event`,
`Extract_And_Record_Lesson_Flow`.

### Prompt templates (2)
`Select_Relevant_Lessons`, `Extract_And_Record_Lesson`.

### UI
11 `sia*` LWC (`siaApp`, `siaOverviewDashboard`, `siaSessionExplorer`,
`siaThresholdEditor`, `siaMetricCard`, `siaRewardRulesEditor`,
`siaSubagentConfigurator`, `siaLessonDetailView`, `siaAgentSwitcher`,
`siaKnowledgeExplorer`, `siaAgentComparison`), `SIA_Console` app + tab + flexipage,
`SIA_App_Icon` content asset, `SelfImprovingAgentContext` message channel.

### Permission sets (2)
`SIA_Framework_Access` (agent runtime user), `SIA_Admin` (console users).

### Test harness
`run_agent_tests.mjs`, `run_preview_tests.mjs`, `run_runtime_tests.mjs`, README,
plus one **genericized** placeholder CSV (`agent_test_cases_sample.csv`).

## What does NOT come over
Smartsheet `.agent`/bot bundles, Smartsheet genAiFunctions (AQWK, Finance, Support-Level),
Smartsheet-specific prompt templates, gap CSV/apex/result files, POC/UAT docs.

## Authored (not copied)
1. **`docs/Self-Learning-Harness-for-FDE.md`** — generic wiring guide: the load→outcome→
   lesson→reward loop, the deterministic-`run` vs skippable-prose action rule, the
   trace-diagnostic pattern, and runtime permission requirements.
2. **Wire the harness into `customer_support_skill_demo.agent`** — a runnable,
   Smartsheet-free example (separate commit).

## Delivery
1. ✅ Commit pre-existing uncommitted work on `main`.
2. Branch `feat/self-learning-harness`.
3. Commit A — harness metadata + test-harness + docs.
4. Commit B — wire harness into `customer_support_skill_demo.agent`.
5. Update `CLAUDE.md` + `README.md`; push; open draft PR.

## Risks / cautions
- The demo bundle already had uncommitted edits (now committed to `main`); wiring is a
  **separate commit** on the branch for clean review/revert.
- SIA LWCs/app reference the harness objects and controllers only — verify all
  referenced Apex/objects are included so the app deploys.
- Prompt templates require `EinsteinGPTPromptTemplateUser` on the agent runtime user
  (documented, not enforced here).
