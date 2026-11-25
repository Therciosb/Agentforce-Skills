# Agent Script Manual (v5)

Developer guide for building Agentforce agents with Agent Script. Written for engineers who keep agents in source control, and for models that need a reliable picture of the language.

This version replaces the topic-based Agent Script Manual v4. It follows the current [Agentforce Developer Guide](https://developer.salesforce.com/docs/ai/agentforce/guide/get-started.html). Beginning in April 2026, **topics are subagents**. Behavior is the same. The `topic` keyword is deprecated; use `subagent` and `@subagent`.

Primary sources (developer doc pages):

- [Get Started with Agent Script](https://developer.salesforce.com/docs/ai/agentforce/guide/agent-script.html)
- [Language Characteristics](https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-lang.html)
- [Blocks](https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-blocks.html)
- [Flow of Control](https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-flow.html)
- [Configure Models](https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-model.md)
- [Patterns](https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-patterns.html)
- [Reference](https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-reference.html)

Salesforce also publishes a weekly markdown bundle from [Download Agent Script Documentation](https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-download-documentation.html). Treat this manual as a practical companion. Confirm org-specific behavior with preview, and re-read the guide when the bundle updates.

---

## Table of Contents

1. What Agent Script Is
2. Language Model and Syntax
3. Execution Model
4. Core Blocks
5. Variables
6. Actions and Tools
7. Reasoning Instructions
8. Conditionals and Operators
9. Transitions, Delegation, and Routing
10. Before and After Reasoning
11. Models, Voice, and Connections
12. Patterns
13. Service and Employee Blueprints
14. Long-Term Memory in This Repo
15. Validate, Preview, and Publish
16. Troubleshooting
17. Authoring Standards
18. Glossary

---

## 1) What Agent Script Is

Agent Script is the language for agents in Agentforce Builder and in Agentforce DX authoring bundles (`.agent` files). It mixes two kinds of instruction in one file:

- **Logic instructions** (`->`) run every time. Use them for rules, action calls, variable updates, and branching.
- **Prompt instructions** (`|`) are natural language. The model sees them only after logic has been resolved.

The script compiles when you save or publish an agent version. The reasoning engine runs the compiled metadata.

You can write script in Builder (chat, Canvas, or Script view) or in a Salesforce DX project. In Script view and in VS Code, `/` inserts common expressions and `@` inserts resources.

---

## 2) Language Model and Syntax

Agent Script is property-based and whitespace-sensitive. A property is `key: value`. Top-level properties are blocks. Nested values belong to the property above them.

```
config:
    developer_name: "Demo_Agent_1"
    agent_label: "Demo Agent"
    description: "Answers order questions."
```

Markers:

| Marker | Role |
| --- | --- |
| `#` | Rest of the line is a comment |
| `->` | Starts logic instructions |
| `\|` | Starts a prompt, or a multiline string |
| `{! ... }` | Interpolates a resource inside prompt text |
| `...` | Slot-fill token. The model supplies the value |
| `@actions.name` | Action |
| `@outputs.name` | Output of the action just run |
| `@variables.name` | Variable |
| `@subagent.name` | Subagent. A direct tool reference returns to the caller |
| `@connected_subagent.name` | Another agent in the org |
| `@utils.*` | Built-in tools (`transition to`, `setVariables`, `escalate`, `end_session`) |
| `@system_variables.name` | Read-only runtime value |

Indent with spaces or with tabs, and use one style for the whole file. Nested lines need at least 2 spaces or 1 tab. Sibling lines share the same indent. Mixing spaces and tabs is a parse error.

Strings in properties are double-quoted. Booleans are `True` and `False` (capitalized). The language is YAML-like. Do not rely on YAML anchors (`&`) or aliases (`*`).

Resource names (variables, actions, subagents) follow Salesforce developer-name rules: start with a letter, letters/digits/underscores only, no trailing or doubled underscores, 80 characters max. Prefer `snake_case`.

`escalate` is reserved. Do not use it as a subagent or action name.

---

## 3) Execution Model

Design around this order.

1. A request starts at `start_agent` (the agent router in Canvas).
2. The active subagent is processed top to bottom.
3. Logic runs while the prompt is being built. The model does not reason until that prompt is finished.
4. A `transition to` stops the current block, drops the prompt built so far, and starts the destination subagent from the top. The model only sees the destination prompt.
5. A transition does not return. To come back, the destination must transition explicitly, and that re-entry starts at the top of the original subagent.
6. After a destination subagent finishes, the next customer utterance returns to `start_agent`.

`config.runtime.reset_to_initial_node` changes what a later turn does when you are still inside a subagent:

- `False` (default): the next turn resumes where the previous turn left off. Use this for multi-step conversations.
- `True`: every turn restarts at `start_agent`. Use this when the agent should reclassify intent each turn.

Put gates and required transitions first. If the script transitions before later lines run, those lines never become prompt text, and any actions among them never run. That saves latency, and it also means a misplaced transition skips work you still needed.

---

## 4) Core Blocks

A script is a set of blocks. Typical order in this repo: `system`, `config`, `access` (when used), `variables`, `language`, `connection`, then `start_agent` and `subagent` blocks.

### 4.1 `system`

Agent-wide instructions and messages. `messages.welcome` and `messages.error` are required. Use `|` for multiline text. Linked or mutable variables can be interpolated, for example `{!@variables.userPreferredName}`.

Keep this block stable. Dynamic business rules belong in subagent reasoning. A subagent can override these instructions with its own `system` block. That override replaces the agent-level instructions for that subagent only. Use it when the global tone would conflict with the subagent's job.

### 4.2 `config`

Identity and runtime options.

| Parameter | Notes |
| --- | --- |
| `developer_name` | Required API name. Unique in the org. Same naming rules as other developer names. |
| `agent_label` | UI label. Generated from `developer_name` if omitted. |
| `description` | What the agent is for. |
| `company`, `role` | Optional context for the model. |
| `agent_type` | `AgentforceServiceAgent` (default) or `AgentforceEmployeeAgent`. Usually set from the template. |
| `agent_version` | Set when a version is created. |
| `enable_enhanced_event_logs` | `True` or `False`. Default `False`. |
| `user_locale` | Optional. |
| `runtime` | Streaming, citations, groundedness, and turn restart. See below. |
| `file_upload` | How customer uploads are accepted. See below. |

`default_agent_user` inside `config` is deprecated. Put it in the `access` block.

`runtime` (all optional):

| Parameter | Effect |
| --- | --- |
| `streaming` | Stream tokens as they are produced. Set `False` when the client needs one complete message. |
| `thought_chunks` | Stream step-by-step thinking. Leave off on customer-facing channels. |
| `citation` | Attach sources to knowledge answers. |
| `groundedness` | Check the reply against source content. Turning it off is faster and raises hallucination risk. |
| `reset_to_initial_node` | `True` restarts every turn at `start_agent`. Default `False`. |

`file_upload.mode` is `auto` (default handling), `managed` (you choose which files reach which subagent, including slices of `@system_variables.uploaded_files`), `disabled` (reject quietly), or `error` (reject and show `message`).

### 4.3 `access`

The user the agent runs as. Service agents require it. Permissions on that user decide which data and actions succeed.

```
access:
    default_agent_user: "service@example.com"
```

### 4.4 `variables`

Global session state. See section 5.

### 4.5 `language`

```
language:
    default_locale: "en_US"
    additional_locales: ""
    all_additional_locales: False
```

Supported locales are listed in Salesforce Help under Agentforce language support. Voice ignores adaptive language mode; set a concrete `default_locale` when you use `modality voice`.

### 4.6 `start_agent`

The entry subagent. The usual name is `agent_router`. It classifies intent and routes. It has the same shape as any other subagent (description, reasoning, actions). You can point `start_agent` at a different subagent if the conversation should not begin at the router.

Some templates classify with `model://sfdc_ai__DefaultEinsteinHyperClassifier` on the router. That model is fast at classification and handles negative instructions well. It cannot use `before_reasoning` or `after_reasoning`, and its only tool is `@utils.transition`.

### 4.7 `subagent`

A job the agent can do: description, optional system override, `actions`, and `reasoning` (`instructions` plus `reasoning.actions`).

The description is what the router uses to decide relevance. Write it in the words a customer would use, and make it distinct from sibling subagents.

`reasoning.actions` are tools the model may call. `actions` are the contracts (`target`, inputs, outputs) those tools and `run` statements call. An action the model should choose must be listed in `reasoning.actions`, not only in `actions`.

### 4.8 `connected_subagent`

A whole other Agentforce agent, addressed as `@connected_subagent.<name>`.

```
connected_subagent CRM_Agent:
    label: "CRM Agent"
    target: "agentforce://<org_agent_reference>"
    description: "CRM lookups and updates."
    loading_text: |
        Fetching CRM information.
    inputs:
        currentRecordId: string = @variables.currentRecordId
```

Two ways to call it:

- **Handoff:** `@utils.transition to @connected_subagent.CRM_Agent` gives it the conversation.
- **Supervisor:** `crm_agent: @connected_subagent.CRM_Agent` runs it as a tool. The caller stays in control and can use the result.

Inputs flow only from the caller into the connected agent. `after_response` can `set` variables or `transition` after it replies. `delegate_escalation: True` lets a handoff connected agent escalate to a person. In supervisor mode, escalation stays on the orchestrator.

### 4.9 `connection`

External channel setup. Messaging example:

```
connection messaging:
    escalation_message: "One moment while I connect you with someone who can help."
    outbound_route_type: "OmniChannelFlow"
    outbound_route_name: "agent_support_flow"
    adaptive_response_allowed: True
```

`@utils.escalate` needs this block plus an Omni-Channel route.

### 4.10 `modality voice`

How a voice agent speaks: persona, speed, keyword boosts, pronunciations, filler phrases, and turn-taking. The default voice model is ElevenLabs v3 Conversational. The voice catalog and parameter ranges live in the guide's voice pages. Branch on the live channel with `@system_variables.current_modality` (`"voice"` or `"text"`) instead of hard-coding channel logic into the modality block.

---

## 5) Variables

Variables are global for the session. Every subagent can read them. Define them only in the `variables` block.

Three kinds:

| Kind | Who sets it | Notes |
| --- | --- | --- |
| Custom (`mutable` or fixed) | Script, or the model via slot fill | Omit `mutable` to freeze the value. |
| Linked | An external source | No default. The agent cannot assign it. Not `object` or `list`. |
| System | The runtime | Read-only. Not declared in `variables`. `@system_variables.<name>`. |

Custom types: `string`, `number` (IEEE 754 double), `boolean`, `object`, `date`, and `list[<type>]`. `id` is deprecated; store Salesforce ids as `string`.

Optional metadata: `description` (needed when the model slot-fills), `label`, and `visibility` (`Internal` by default; `External` lets an API or the simulator set the value).

```
variables:
    is_verified: mutable boolean = False
        description: "True after identity checks pass."
    loyalty_tier: mutable string = "standard"
    line_items: mutable list[object]
    session_id: linked string
        source: @MessagingSession.Id
```

Linked `source` namespaces:

| Source | Properties |
| --- | --- |
| `@MessagingSession` | `Id`, `MessagingEndUserId`, `EndUserLanguage` |
| `@MessagingEndUser` | `ContactId` |
| `@VoiceCall` | `Id` |

In logic, write `@variables.loyalty_tier`. In prompt text, write `{!@variables.loyalty_tier}`.

`None` means unset and works for every type. `""` means an empty string. Check both for strings. Append strings with `+`.

Fields of an `object` variable are addressable with dot notation, in logic and in prompt text: `if @variables.order_summary.days_since_order <= 60:` and `{!@variables.Lead_Record.S4STiming}`. Fields are read-only. Assign the whole object, usually from an action output. Tested in November 2026:

- `set @variables.obj.field = ...` fails validate with "Cannot resolve variable name from expression".
- `@utils.setVariables` with `with obj.field=...` passes `sf agent validate` but fails the full compile that `sf agent preview start` runs ("error compiling").
- An Apex inner-class output (`complex_data_type_name: "@apexClassType/c__MyClass$Inner"`) assigns to a `mutable object` variable, and its fields read correctly in `if`, in `set`, and in `{! }`.
- Reading a field that is missing from the object (for example, on a `{}` default) makes the whole `if` evaluate false with no error in the trace, even inside `is None or ...`. Give the default the fields you test, for example `= {"active_skills": "unloaded"}`.
- A `Map<String, Boolean>` field on the Apex inner class is readable by key: `available when @variables.skill_state.tools.create_case == True`. A missing key evaluates false, so the tool stays hidden. The enabled tool set re-evaluates after a tool updates the object, so a tool can appear in the same turn.

List items are zero-indexed. `@variables.questions[2]` is the third string. On a list of objects, `@variables.accounts[3].data.Name` returns the raw field. `json_path(@variables.accounts, "$[3].data.Name")` returns the value wrapped as a JSON string. Helpers: `len`, `max`, `min`, `to_json`, `json_path`.

System variables:

| Name | Value |
| --- | --- |
| `user_input` | The latest customer utterance, not the full transcript. |
| `current_modality` | `"voice"` (telephony) or `"text"` (Messaging / Enhanced Chat v2). `None` if neither. |
| `current_connection` | Connected client for this turn. May be `None` until the connection is ready. |
| `uploaded_files` | Up to the 10 most recent uploads (`id`, `file_url`, `name`, `mime_type`). Requires `config.file_upload`. Slice with `[0:5]`. |

`ask for` (beta) collects one field per turn inside reasoning instructions, checks the value against the variable type, stores it, and returns to the same subagent until every `ask for` variable is set. Use it for short intake forms before a transition or a downstream action.

---

## 6) Actions and Tools

There are two `actions` lists, and they do different jobs.

### 6.1 Subagent actions

`subagent.actions` defines a contract the script can `run`:

| Property | Role |
| --- | --- |
| name | Developer name. |
| `description` | What it does. The model reads this when the action is exposed as a tool. |
| `label` | Customer-facing name. |
| `inputs` / `outputs` | Name, type, and metadata. |
| `target` | `apex://`, `flow://`, or `prompt://` plus the developer name. |
| `include_in_progress_indicator` | Show progress while it runs. |
| `require_user_confirmation` | Ask the customer before running. |

Input and output types include `string`, `number`, `integer`, `long`, `boolean`, `object`, `date`, `datetime`, `time`, `currency`, and `list[<type>]`. `id` is deprecated. Complex objects need `complex_data_type_name`: a Lightning type (including custom Lightning types) or an Apex class such as `@apexClassType/c__MyClass$Result`. Set `filter_from_agent: True` on an output to keep it out of the model's context. If a required input is left unbound, the model tries to slot-fill it.

```
actions:
    lookup_order:
        description: "Load one order by id."
        inputs:
            order_id: string
                is_required: True
        outputs:
            order_summary: string
        target: "flow://Get_Order"
```

Call it from logic. Map outputs in the same `run`:

```
run @actions.lookup_order
    with order_id=@variables.order_id
    set @variables.order_summary=@outputs.order_summary
```

`@outputs` is the result of that run. Do not read it outside the `run` that produced it.

### 6.2 Tools (`reasoning.actions`)

Tools are what the model may choose. Each tool wraps a subagent action, a util, a subagent, or a connected subagent.

```
reasoning:
    actions:
        lookup_order: @actions.lookup_order
            with order_id=@variables.order_id
            set @variables.order_summary=@outputs.order_summary
            available when @variables.is_verified == True
        capture_email: @utils.setVariables
            description: "Store the email the customer just gave."
            with customer_email=...
        go_to_returns: @utils.transition to @subagent.returns
            description: "Start a return."
```

`available when` hides the tool unless the condition is true. The model can call any tool that is available, even if the prompt never names it. Name tools for the job, and say when to use them in the prompt with `{!@actions.tool_name}` when the choice matters.

### 6.3 Which one to use

| Need | Mechanism |
| --- | --- |
| Must run, in order, with no model discretion | `run @actions...` in logic |
| Model decides whether and when | Tool in `reasoning.actions` |
| Model writes a variable from the utterance | `@utils.setVariables` with `...` |
| Guaranteed handoff | `transition to @subagent...` in logic |
| Model chooses the next subagent | `@utils.transition to` tool |
| Borrow another subagent and continue | Direct `@subagent.name` tool (returns) |
| Hand the conversation to another agent | Transition to `@connected_subagent.name` |
| End the session | `@utils.end_session` |
| Human handoff | `@utils.escalate` plus `connection messaging` |

---

## 7) Reasoning Instructions

`reasoning.instructions` is processed into the prompt. Shorter instructions are more reliable.

Logic and prompt can sit in the same block. Logic uses `->`. Prompt lines start with `|`.

```
reasoning:
    instructions: ->
        if @variables.order_summary == "":
            run @actions.lookup_order
                with order_id=@variables.order_id
                set @variables.order_summary=@outputs.order_summary
        | The customer is {!@variables.member_name}.
        | Order summary: {!@variables.order_summary}.
        | If they ask for tracking, use {!@actions.lookup_tracking}.
```

Only the `|` lines that the logic actually reaches are concatenated. Variable references inside `{! !}` are replaced before the model sees the text.

---

## 8) Conditionals and Operators

`if`, `else if`, and `else` choose actions, assignments, transitions, or prompt lines. There is no requirement to nest exclusive branches as separate `if`s; `else if` is valid.

| Category | Operators |
| --- | --- |
| Comparison | `==`, `!=`, `<`, `<=`, `>`, `>=`, `is`, `is not` |
| Logical | `and`, `or`, `not` |
| Arithmetic | `+`, `-` |
| Grouping | `( )` |

Parentheses are required for clarity when `and` and `or` mix, and `available when` accepts the same expressions.

```
if @variables.tracking_number is not None and @variables.tracking_number != "":
    run @actions.get_tracking
else:
    | Ask for the tracking number.
```

Keep conditions shallow. Store a complicated check in a boolean variable and test that.

---

## 9) Transitions, Delegation, and Routing

Two different handoffs:

| Form | Control afterward |
| --- | --- |
| `transition to @subagent.X` in logic | One-way. Current prompt is discarded. |
| `go_to_x: @utils.transition to @subagent.X` | One-way, but the model chooses when. |
| `consult: @subagent.X` | Runs X, then returns. If X itself transitions, that path runs to completion, then control returns. |

In logic, write `transition to`, not `@utils.transition to`.

```
if @variables.is_verified == False:
    transition to @subagent.identity
```

```
reasoning:
    actions:
        go_to_orders: @utils.transition to @subagent.order_management
            description: "Order status, changes, and refunds."
            available when @variables.is_verified == True
```

Router guidance:

- Keep `start_agent` to welcome, classify, and route.
- Prefix transition tools with `go_to_`.
- Descriptions must be specific and non-overlapping.
- Gate with `available when` so policy is not left to the prompt.
- For a step the customer must not skip, transition in logic at the top of the instructions.
- Do not build a cycle that transitions A to B and B back to A on the same conditions.
- Omit a subagent from the router if only another subagent should enter it.

A transition can also sit on a tool so it fires when that action finishes (`transition to` under the tool's `with` / `set` lines).

---

## 10) Before and After Reasoning

`before_reasoning` has the same syntax as `after_reasoning`. It is equivalent to logic at the top of `instructions`.

`after_reasoning` runs after the reasoning loop exits, on every request that stayed in the subagent. Use it to normalize variables, save state, or transition. It cannot contain `|`.

```
after_reasoning:
    if @variables.case_type != "":
        transition to @subagent.case_creation
```

If the subagent transitions away before the loop finishes, its `after_reasoning` does not run. Inside `after_reasoning`, use `transition to`, not `@utils.transition to`.

Neither hook is available on a subagent that uses EinsteinHyperClassifier.

---

## 11) Models, Voice, and Connections

The org default model applies unless you override it. A subagent `model_config` overrides the agent `model_config`, which overrides the org default.

```
model_config:
    model: "model://sfdc_ai__DefaultBedrockAnthropicClaude45Haiku"
    params:
        temperature: 0.7
        max_tokens: 2000
```

| Parameter | Range / meaning |
| --- | --- |
| `model` | A supported `model://` id. |
| `temperature` | `0` to `1`. Lower is more repeatable. |
| `max_tokens` | Cap on the reply. |
| `top_p` | `0` to `1`. Nucleus sampling. |

Salesforce's current testing guidance favors GPT 4.1, Claude Haiku 4.5, and Gemini Flash-class models for agents. Test the model you ship. A model that works for one subagent can be a poor fit for tools on another.

Voice persona, speed, pronunciations, and endpointing belong in `modality voice`. Human escalation belongs in `connection messaging` plus `@utils.escalate`.

---

## 12) Patterns

These are the patterns in the current guide, restated as rules of thumb.

**Fetch before reasoning.** If a variable is empty, `run` the lookup, `set` the result, then prompt with `{!@variables...}`. The model then talks about data you loaded, not data it invented.

**Chain actions in logic** when order matters. Map each output before the next `run`. You can also chain inside a tool, or transition after a tool completes.

**Filter with `available when`.** Hide tools and routes the customer must not reach. Do not rely on the prompt alone. The model may call any visible tool.

**Required workflow.** Put the mandatory `if` / `transition to` at the top of the router or of the subagent. For a multi-turn form, a step variable (or `ask for`) decides the next prompt or the next subagent.

**Name resources in the prompt.** `{!@actions.some_tool}` and `{!@variables.some_value}` raise the chance the model uses them. Still gate anything dangerous.

**Override `system` on the subagent** when agent-level instructions conflict with that subagent, or when the persona should change. The subagent system block replaces the agent one. It does not merge.

**List variables.** Keep an index variable if you walk a list one item per turn. Read object fields with `[index].data.Field` in logic and in prompts.

**Slot fill** with `@utils.setVariables` and `...` when the value comes from the customer. Give the variable a description. Bind known values with `@variables` instead of `...`.

---

## 13) Service and Employee Blueprints

### 13.1 Service agent

- `access.default_agent_user` set to the Einstein agent user.
- `connection messaging` when the agent escalates.
- `start_agent` classifies and enforces verification.
- A verification subagent, then domain subagents (orders, returns, billing).
- Escalation through `@utils.escalate` or an escalation subagent that is available only in business hours.
- A closing subagent that persists state, then `@utils.end_session` when the conversation is done.

### 13.2 Employee agent

- No `default_agent_user` and no messaging connection. The agent runs as the employee.
- `start_agent` routes internal tasks.
- Lookups against the system of record run in logic when the answer must be exact.
- Tools and routes filtered by role or record state.
- A completion subagent that writes back and ends the session.

### 13.3 Shared rules

- Deterministic logic for compliance, sequencing, and writes.
- Prompt text for dialogue.
- A small variable model is the operational state. Do not expect the transcript to remember facts you still need next turn.
- Transitions are explicit and bounded.

---

## 14) Long-Term Memory in This Repo

`customer_support_skill_demo` is the reference. Persistent memory is an Apex-backed checkpoint. Instructions are composed from `Agent_Skills_Repo__c` records, not hardcoded in the script.

### 14.1 Actions

| Action | Target | Role |
| --- | --- | --- |
| Load memory | `apex://LoadAgentMemory` | Read `Agent_Context__c` for a contact. |
| Save checkpoint | `apex://SaveAgentContext` | Write summary, goal, issue flag, and style. Action names differ per subagent because names must be unique across the agent. |
| Load and compose | `apex://Agent_Skill_LoadAndCompose` | Merge skill names into the bundle and return prompt text. |

Load inputs use `contactId`. The formatted prompt string is the `agentMemory` output. Save inputs are scalars: `contactId`, `newSummary`, `newGoal`, `hasIssue`, `newStyle`. Save returns `success`.

### 14.2 Turn shape

1. `start_agent` loads memory when `context_loaded` is false and `ContactId` is set, then loads role and core skills, then `transition to @subagent.general_support`.
2. Outputs are mapped inside the `run` (`agent_memory`, memory fields, `instruction_bundle_json`).
3. Each subagent's `before_reasoning` calls load-and-compose with that subagent's `instructionNames` and `existingInstructionBundle=@variables.instruction_bundle_json`.
4. Reasoning is two-pass. While `context_dirty` is false, the only tool is `update_memory` (`@utils.setVariables` with `...`), which sets `context_dirty` true and does not answer. On the next pass the prompt includes `{!@variables.agent_memory}` and `{!@variables.composed_instructions}`.
5. `after_reasoning` saves when `context_dirty` is true, then clears the flag. A finalization subagent saves again because an early transition skips `after_reasoning`.

`instructionNames` is a CSV with no spaces after commas.

Inject memory as the formatted string:

```
| Here is your past context. Use it for personalization:
| {!@variables.agent_memory}
```

Map outputs in the same `run`:

```
run @actions.load_user_memory
    with contactId=@variables.ContactId
    set @variables.agent_memory=@outputs.agentMemory
    set @variables.context_loaded=True
```

Linked session fields in that agent (`@MessagingSession.Id`, `@MessagingSession.MessagingEndUserId`) follow the linked-variable rules in section 5. `ContactId` is a mutable variable with a test default so preview can run without a live messaging session.

---

## 15) Validate, Preview, and Publish

Authoring bundles in this project live under `force-app/main/default/aiAuthoringBundles/<api_name>/`. The `.agent` file is the source. Published planner bundles are generated output.

Loop:

1. Validate the script.
2. Deploy action dependencies (Apex, flows, objects, permission sets) before a live preview.
3. Preview the authoring bundle. Simulated mode mocks actions. `--use-live-actions` runs the Apex, flows, and prompts in the org.
4. Publish, then preview the published agent with `--api-name`.
5. Activate when that version should serve users.
6. Test again after every publish.

```bash
sf agent validate authoring-bundle --api-name <api_name> --target-org <org>
sf agent preview --authoring-bundle <api_name> --target-org <org>
sf agent preview --authoring-bundle <api_name> --use-live-actions --target-org <org>
sf agent publish authoring-bundle --api-name <api_name> --target-org <org>
sf agent preview --api-name <api_name> --target-org <org>
```

`--api-name` on preview is the activated published agent. `--authoring-bundle` is the local script. Assign `Agent_Skills_Agent_Runtime` to the agent user before live actions that read this project's objects.

Moving an agent between orgs is metadata. Current API packaging uses `AiAgentDefinition`, `AiAgentDefinitionVersion`, and `AiAuthoringBundle`. Both orgs must be on that API version. See the guide's deploy-metadata pages before copying manifests by hand.

---

## 16) Troubleshooting

**A flow succeeds and the next step fails.** Outputs were read outside the `run`. Prompt paths do not match variable names. A transition above the `run` skipped it.

**A tool never runs.** The description is vague or overlaps another tool. `available when` is false. A required input is missing. The prompt never names the tool in a case where the model needs the hint. On a HyperClassifier router, only `@utils.transition` tools are legal.

**Routing feels random.** The router lists too many similar subagents. Descriptions overlap. A required path is a tool instead of a logic `transition to`. `reset_to_initial_node` is left at the default, so a later turn resumes the old subagent instead of reclassifying.

**A transition drops work.** Expected. The current prompt is discarded. `after_reasoning` on the source subagent does not run. Put the save before the transition, or save again in the destination.

**Personalization is blank.** The upstream output name does not match the `set`. The string is `""` and the check was only `is None`, or the reverse. Object fields are read as `@variables.obj.field`. Items in a list of records need `[n].data.<field>` or `json_path`.

**Parse errors on `&` or `*`.** Anchors and aliases are not part of Agent Script. Repeat the block.

**Escalation does nothing.** `connection messaging` is missing `outbound_route_type` and `outbound_route_name`, the Omni-Channel flow is inactive, or the agent user cannot access the route. `escalate` was reused as an action name.

**`before_reasoning` or `after_reasoning` is rejected.** The subagent's `model_config` is EinsteinHyperClassifier.

**Live preview returns empty data.** The action ran as `default_agent_user`. Object and field access are missing on that user. Simulated preview will not show this, because it never runs the action.

**Config still has `default_agent_user`.** That property is deprecated on `config`. Move it to `access`. Existing bundles in this repo may still compile with the old placement until the org's compiler drops it.

---

## 17) Authoring Standards

- One vocabulary across subagents, actions, and variables. "Customer" in one name and "client" in another makes routing worse.
- Names say the outcome: `lookup_order`, `go_to_returns`, `is_verified`, `context_loaded`.
- Descriptions are concrete and do not overlap.
- Start with the shortest prompt that works. Add a line only after a preview shows the gap.
- Logic first, prompt second, inside the same `instructions: ->` block.
- Side effects (`run`, `set`, `transition to`) are written out. They are not implied by prose.
- Prefer several small subagents over one subagent that switches persona in prose.
- Comments explain why a gate exists, not what `if` means.
- Transition tools use `go_to_<subagent>`.
- Booleans use `is_`, `has_`, or a `_loaded` / `_dirty` suffix.

---

## 18) Glossary

| Term | Meaning |
| --- | --- |
| Agent Script | Hybrid logic and prompt language. Compiled on save or publish. |
| Subagent | One job: instructions, actions, and tools. Replaces topic. |
| `topic` | Deprecated spelling of subagent. |
| Agent router | The `start_agent` block. Entry and classification. |
| Action | Contract with a `target` (`apex`, `flow`, or `prompt`). |
| Tool | A `reasoning.actions` entry the model may call. |
| Variable | Session state. Custom, linked, or system. |
| Transition | One-way move to another subagent. Prompt so far is dropped. |
| Delegation | `@subagent.name` as a tool. Runs, then returns. |
| Connected subagent | Another agent in the org. |
| `available when` | Hides a tool until the condition is true. |
| Slot fill (`...`) | The model writes the value. |
| `ask for` | Beta. Collects one typed field per turn. |
| `{! ... }` | Insert a resource into prompt text. |

```
# Deterministic action
run @actions.lookup_order
    with order_id=@variables.order_id
    set @variables.order_status=@outputs.status
```

```
# Tool the model may call
reasoning:
    actions:
        capture_order_info: @utils.setVariables
            with order_id=...
            available when @variables.is_verified == True
```

```
# Gate
if @variables.is_verified == False:
    transition to @subagent.identity
```
