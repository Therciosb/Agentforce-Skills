# Self-Learning Harness — Engineering Guide

A reusable Agentforce harness that lets **any** Agent Script agent learn from its own
runtime outcomes: surface relevant past lessons at the start of a turn, record whether
each turn resolved the user's problem, capture new lessons when a gap is detected, and
reward lessons that prove helpful. Everything is keyed generically by
`agent_api_name` + `topic_area`, so one deployment serves many agents.

This guide covers the moving parts, the runtime loop, how to **wire the harness into an
agent**, and the deterministic-vs-prose rule that makes the loop reliable. It contains
no agent-specific (domain) content — see `customer_support_skill_demo` for a wired
example.

---

## 1. Components

### Custom objects
| Object | Purpose |
|--------|---------|
| `AgentLessonLearned__c` | The lesson store. `lesson_text__c`, `confidence_score__c`, `topic_area__c`, `agent_api_name__c`, `categories__c`, `times_referenced__c`, `times_successful__c`, `is_archived__c`, `is_promoted__c`, `outcome_type__c`. |
| `AgentSession__c` | One row per agent session; rolls up the Agent Efficiency Score (`aes_score__c` + `aes_goal__c`/`aes_efficiency__c`/`aes_learning__c`), `final_outcome__c`, `lessons_applied__c`, `lessons_created__c`. |
| `AgentActionOutcome__c` | One row per classified action/turn outcome: `action_name__c`, `outcome__c`, `reward_points__c`, `lesson_linked__c`, `lesson_was_helpful__c`. |
| `AgentImprovementConfig__c` | Per-agent tuning: `lesson_selection_pool_size__c`, `lesson_selection_min_confidence__c`, `max_lessons_per_topic__c`, `promotion_confidence__c`, `demotion_confidence__c`, `decay_rate_per_month__c`, `loop_detection_threshold__c`, A/B fields. |
| `AgentRewardConfig__c` | Point values per `action_name__c` × `topic_area__c` (`points__c`, `is_active__c`). |
| `AgentSubagentConfig__c` | Per-topic outcome mapping: `optimal_actions__c`, `outcome_mapping_json__c`, `significant_outcome_triggers__c`. |
| `AgentReward__e` | **Platform event** fired by the agent; carries `Reward_Category__c`, `Outcome__c`, `Lesson_Id__c`, `Session_Id__c`, `Topic_Area__c`, `Agent_Api_Name__c`. |

### Apex
| Class | Role |
|-------|------|
| `SelectRelevantLessons` | `@InvocableMethod` **Select Relevant Lessons** — Stage-1 SOQL pool + Stage-2 semantic rank via the `Select_Relevant_Lessons` prompt template; hard-caps at `max_lessons`; degrades to top-N-by-confidence on PT failure. |
| `AgentRewardHandler` | Consumes `AgentReward__e`: classifies the outcome (config-driven), writes `AgentActionOutcome__c`, credits `times_referenced__c`/`times_successful__c`, adjusts `confidence_score__c`, promotes/demotes lessons. |
| `ClassifyAgentOutcome` | Config-driven outcome classification (success/failure/neutral) from a raw domain event + `AgentSubagentConfig__c` mapping. |
| `AesCalculator` | Computes the Agent Efficiency Score onto `AgentSession__c`. |
| `ConversationHistoryProvider` | Supplies recent conversation context to lesson extraction. |
| `LessonJsonParser`, `LessonRelevanceParser` | Parse LLM/PT JSON responses into typed lesson data (parser is dormant/legacy but kept). |
| `SiaConfigController`, `SiaMetricsController`, `SiaSessionController`, `SiaKnowledgeController` | `@AuraEnabled` back-ends for the SIA Console LWCs. |
| `AgentRewardTrigger` | Trigger on `AgentReward__e` → `AgentRewardHandler`. |

### Flows (the agent's action surface)
| Flow | Called by agent as | Does |
|------|--------------------|------|
| `Load_Improvement_Context` | `load_lessons` | Returns `improvement_context` (formatted lessons), `lesson_count`, `lesson_ids`. Wraps `Check_Lessons_Learned`. |
| `Check_Lessons_Learned` | (sub-flow) | One-step wrapper over `SelectRelevantLessons` Apex. |
| `Extract_And_Record_Lesson_Flow` | `create_lesson`/`extract_lesson` | Runs the `Extract_And_Record_Lesson` prompt and inserts an `AgentLessonLearned__c` (with a dedup guard). |
| `Publish_Reward_Event` | `report_lesson_outcome` | Publishes an `AgentReward__e`. |

### Prompt templates
- `Select_Relevant_Lessons` — ranks the candidate lesson pool against the user message.
  Callers **must** set `body.isPreview = false` (omitting it triggers a platform NPE).
- `Extract_And_Record_Lesson` — distills a new lesson from a fail-then-succeed turn.

### UI — the SIA Console
Lightning app `SIA_Console` (tab + flexipage + `SIA_App_Icon`) hosting 11 `sia*` LWCs
(`siaApp`, `siaOverviewDashboard`, `siaSessionExplorer`, `siaThresholdEditor`,
`siaMetricCard`, `siaRewardRulesEditor`, `siaSubagentConfigurator`,
`siaLessonDetailView`, `siaAgentSwitcher`, `siaKnowledgeExplorer`,
`siaAgentComparison`). Cross-LWC state travels over the `SelfImprovingAgentContext`
Lightning message channel.

### Permission sets
- **`SIA_Framework_Access`** — assign to the **agent runtime user**. Grants object CRUD +
  the runtime Apex (`SelectRelevantLessons`, `AgentRewardHandler`, `AesCalculator`,
  `ClassifyAgentOutcome`, `ConversationHistoryProvider`, `LessonJsonParser`).
- **`SIA_Admin`** — assign to console users. Grants the `sia*` controllers, objects,
  tab, and app.

The runtime user also needs `EinsteinGPTPromptTemplateUser` (ideally
`…Manager`) so `SelectRelevantLessons` and the lesson-extraction flow can invoke the
prompt templates.

---

## 2. The runtime loop

```
turn starts
  └─ load_lessons  → Load_Improvement_Context → Check_Lessons_Learned
                     → SelectRelevantLessons → Select_Relevant_Lessons PT
                     ⇒ improvement_context, lesson_count, lesson_ids
  └─ (agent answers using improvement_context + its own knowledge action)
  └─ set_knowledge_outcome  ⇒ outcome_type = resolved | unresolved
  └─ if a surfaced lesson reached a terminal outcome:
       report_lesson_outcome → Publish_Reward_Event → AgentReward__e
         → AgentRewardTrigger → AgentRewardHandler
           ⇒ AgentActionOutcome__c + confidence/promotion updates
  └─ if failure-then-success and NO lesson was surfaced:
       create_lesson → Extract_And_Record_Lesson_Flow ⇒ new AgentLessonLearned__c
session ends
  └─ AesCalculator rolls up AgentSession__c.aes_score__c
```

---

## 3. Wiring the harness into an agent (Agent Script)

Add **four reasoning actions** to the topic/subagent that answers questions, plus the
underlying `flow://` action definitions. Names on the left are the LLM-facing tool
names; the `@actions.*` on the right bind to the copied flows.

```
reasoning:
    actions:
        # 1) Surface relevant lessons at the start of the turn.
        load_lessons: @actions.Load_Improvement_Context
            description: "Load relevant lessons for the user's current question. ALWAYS call when the user presents a new issue."
            with agent_api_name = "<your_agent_api_name>"
            with topic_area = "<topic>"
            with session_id = @variables.session_key
            with user_message = ...
            set @variables.improvement_context = @outputs.improvement_context
            set @variables.lesson_count = @outputs.lesson_count
            set @variables.applied_lesson_id = @outputs.lesson_ids

        # 2) Record whether THIS turn resolved the problem.
        set_knowledge_outcome: @utils.setVariables
            description: "Record outcome. outcome_type: 'resolved' when fixed/confirmed; 'unresolved' otherwise. last_action_result: 1-2 sentence reason."
            with outcome_type = ...
            with last_action_result = ...

        # 3) Report an applied lesson's terminal outcome (platform judges success/points).
        report_lesson_outcome: @actions.Publish_Reward_Event
            description: "Call ONCE when a surfaced lesson reached a terminal outcome this turn. Report the raw domain event only; do not pre-judge success."
            with session_id = @variables.session_key
            with reward_category = "lesson"
            with domain_event = @variables.outcome_type
            with topic_area = "<topic>"
            with lesson_id = @variables.applied_lesson_id
            with agent_api_name = "<your_agent_api_name>"
            available when @variables.lesson_resolved_this_turn == True or @variables.failure_detected_this_turn == True

        # 4) Capture a NEW lesson on fail-then-succeed when none was surfaced.
        create_lesson: @actions.Extract_And_Record_Lesson_Flow
            description: "Record a NEW lesson from a failure-then-success pattern. Only when no existing lesson was surfaced this session."
            available when @variables.previous_action_failed == True and @variables.lesson_count == 0
```

Then declare the `flow://` action definitions (inputs/outputs matching the flow
signatures — see the `customer_support_skill_demo` bundle for a full copy-paste block),
and inject the surfaced lessons into reasoning with `{!@variables.improvement_context}`.

### Supporting variables
Declare (as `mutable`): `improvement_context`, `lesson_count`, `applied_lesson_id`,
`session_key`, `outcome_type`, `last_action_result`, plus the latch booleans
`awaiting_knowledge_outcome`, `lesson_resolved_this_turn`, `failure_detected_this_turn`,
`previous_action_failed`.

### The router-bypass latch
Use an `after_reasoning:` block to keep the user in the answering topic while a
knowledge thread is unresolved, so the next "it worked" / "it failed" reply is routed
back and its outcome recorded:

```
after_reasoning:
    if @variables.outcome_type == "resolved":
        set @variables.awaiting_knowledge_outcome = False
    if @variables.outcome_type != "resolved":
        set @variables.awaiting_knowledge_outcome = True
```

---

## 4. The one rule that makes it reliable: `run` vs prose

**A critical action must be wired as a deterministic `run @actions.X`, not as an
optional prose directive.** The LLM can silently skip prose suggestions.

```
# WRONG — skippable suggestion. The planner may never invoke it.
|After answering, set {!@actions.set_knowledge_outcome}: ...

# RIGHT — guaranteed. Always executes.
run @actions.set_knowledge_outcome with outcome_type=..., last_action_result=...
```

Outcome recording and lesson creation are exactly the steps you cannot afford to have
skipped, so prefer `run` for them where the flow allows a deterministic call.

### Diagnosing skipped actions from traces
`run_preview_tests.mjs --authoring-bundle` writes full execution traces. Compare the
actions the planner *could* invoke (`EnabledToolsStep`) against the ones it *did*
(`FunctionStep`):

```bash
jq '.plan[] | select(.type == "FunctionStep") | .function.name' trace.json
```

An action present in `EnabledToolsStep` but absent from `FunctionStep` is almost always
one wired as prose instead of `run` — that gap points straight at the defect. (Only the
`--authoring-bundle` preview path emits populated traces; `--api-name`, the SDK harness,
and the runtime Agent API return reply text only.)

---

## 5. Testing

Use `test-harness/` (`run_agent_tests.mjs`, `run_preview_tests.mjs`,
`run_runtime_tests.mjs`) to drive CSV-defined multi-turn conversations against the wired
agent. For **trace/variable verification** run with `--authoring-bundle --mode live`;
for **console-visible runtime sessions** use `run_runtime_tests.mjs` with a
client-credentials Connected App. See `test-harness/README.md`.

Apex tests included: `SelectRelevantLessons_Test`, `ClassifyAgentOutcome_Test`,
`AgentRewardHandlerTest`, `AesCalculatorTest`, and the `Sia*ControllerTest` classes.

```bash
sf apex run test --target-org <org> \
  --class-names SelectRelevantLessons_Test,ClassifyAgentOutcome_Test,AgentRewardHandlerTest,AesCalculatorTest \
  --result-format human --synchronous --code-coverage
```

---

## 6. Deploy order

1. Objects + platform event (`AgentReward__e`).
2. Apex classes + `AgentRewardTrigger`.
3. Flows + prompt templates.
4. LWC + `SIA_Console` app/tab/flexipage + `SelfImprovingAgentContext` message channel.
5. Permission sets — assign `SIA_Framework_Access` to the agent user,
   `SIA_Admin` to console users; grant the agent user `EinsteinGPTPromptTemplateUser`.
6. Seed at least one `AgentImprovementConfig__c` and the `AgentRewardConfig__c` rows per
   `topic_area`, then wire and publish the agent bundle.
