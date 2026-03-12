# Generic Render Action Implementation Plan

**Document Version:** 1.1  
**Created:** March 2025  
**Updated:** March 2025 — Apex-only solution; Flow removed  
**Status:** Ready for Implementation  
**Target:** Agentforce-Skills project

---

## 1. Overview

### 1.1 Purpose

Implement a **generic render action** that allows the agent to display structured data to users via custom LWC. The agent produces a data string (JSON) and a display type; the Apex action validates, normalizes, and returns a structure that the LWC renders.

**Pattern:** Mirrors the LTM persistence pattern—a core skill defines extraction/format rules; the agent produces values via slot-fill; an action processes and returns output.

### 1.2 Components

| Component | Purpose |
|-----------|---------|
| **core-skill-render-data-format** | Defines JSON schema per display type, examples, when to call the action |
| **GenericRenderAction** (Apex) | Validates inputs, returns normalized output or error |
| **GenericRenderOutput** (Apex) | Output class: jsonData, displayType, success, errorMessage |
| **Custom Lightning Type** | Maps GenericRenderOutput to LWC |
| **genericDataRenderer** (LWC) | Renders table, card, list, key-value; shows errors |
| **render_data** (Agent Script) | Tool with data=... and display_type=...; target: apex://GenericRenderAction |

---

## 2. Architecture

Agent Script invokes `apex://GenericRenderAction`. Create the Agent Action from the Apex class in Setup and set Output Rendering to the Custom Lightning Type. The LWC renders the output.

```
Agent (with core-skill loaded)
    │
    ├─ Produces: data (JSON string), display_type (table|card|list|key-value)
    │
    └─ Calls: render_data with data=... display_type=...
              │
              ▼
        apex://GenericRenderAction (Apex)
              │
              ├─ Validates JSON
              ├─ Validates display_type
              ├─ On error: returns success=false, errorMessage
              └─ On success: returns jsonData, displayType, success=true
              │
              ▼
        GenericRenderOutput → Custom Lightning Type → genericDataRenderer (LWC)
              │
              ├─ success=true: parse jsonData, render by displayType
              └─ success=false: show errorMessage
```

---

## 3. Core Skill Definition

### 3.1 Skill Metadata

| Field | Value |
|-------|-------|
| **Name** | core-skill-render-data-format |
| **Type** | Core_Skill |
| **References** | (none) |
| **When to load** | start_agent (with other core skills) |

### 3.2 Skill Instruction Body (Full Text)

```
# RENDER DATA FORMAT

Use the render_data action when you have structured data to display to the user. Produce the data string and display type following these rules.

## When to Call

- After gathering data from another action (e.g. Query Records, Get Record Details) and you want to present it in a structured format
- When you have multiple items to show (list, table)
- When you have a single record or object to show (card, key-value)

## Display Types

| Type | Use Case |
|------|----------|
| table | 2+ rows with columns (e.g. cases, accounts, products) |
| card | Single record with labeled fields |
| list | Simple list of items (strings or short objects) |
| key-value | Pairs of label/value (e.g. record details) |

## Data Format (JSON)

Produce valid JSON. Escape quotes in string values.

### table

Schema: { "columns": ["col1", "col2", ...], "rows": [["val1", "val2", ...], ...] }

Example:
{"columns":["Case Number","Subject","Status"],"rows":[["00001001","Wi-Fi not connecting","In Progress"],["00001002","Billing question","Closed"]]}

### card

Schema: { "title": "string", "fields": [{"label": "string", "value": "string"}, ...] }

Example:
{"title":"Case 00001001","fields":[{"label":"Subject","value":"Wi-Fi not connecting"},{"label":"Status","value":"In Progress"},{"label":"Priority","value":"High"}]}

### list

Schema: { "items": ["item1", "item2", ...] }

Example:
{"items":["Power cycle the modem","Wait 2 minutes","Check LED status"]}

### key-value

Schema: { "pairs": [{"key": "string", "value": "string"}, ...] }

Example:
{"pairs":[{"key":"Account","value":"Acme Corp"},{"key":"Contact","value":"Jane Smith"},{"key":"Case","value":"00001001"}]}

## Extraction Rules

When invoking render_data:
- **data:** Produce the JSON string following the schema for the chosen display_type. Ensure valid JSON (escape quotes, no trailing commas).
- **display_type:** One of: table, card, list, key-value.

If data from another action does not match a schema, transform it. For example, Query Records returns a list of records—map to table (columns + rows) or card (one per record).
```

---

## 4. Apex Logic

### 4.1 Class: GenericRenderAction

**File:** `force-app/main/default/classes/GenericRenderAction.cls`

**Responsibilities:**
- Accept `data` (String) and `display_type` (String)
- Validate JSON is parseable
- Validate display_type is one of: table, card, list, key-value
- On success: parse and re-serialize JSON (ensures valid), return GenericRenderOutput with success=true
- On failure: return GenericRenderOutput with success=false, errorMessage set

**Logic (pseudocode):**
```
1. If data is null or blank → return error "Data is required"
2. If display_type is null or blank → return error "Display type is required"
3. display_type = display_type.trim().toLowerCase()
4. If display_type not in ["table","card","list","key-value"] → return error "Invalid display type. Use: table, card, list, key-value"
5. Try: parse data as JSON (JSON.deserializeUntyped or similar)
6. On parse exception → return error "Invalid JSON: " + exception message
7. Re-serialize to string (JSON.serialize) to ensure valid output
8. Return GenericRenderOutput(jsonData=serialized, displayType=display_type, success=true, errorMessage=null)
```

### 4.2 Output Class: GenericRenderOutput

**Inner class in GenericRenderAction.cls (or separate file):**

```apex
@JsonAccess(serializable='always' deserializable='always')
global class GenericRenderOutput {
    @InvocableVariable(label='JSON Data' description='Valid JSON string for LWC to render')
    global String jsonData;

    @InvocableVariable(label='Display Type' description='One of: table, card, list, key-value')
    global String displayType;

    @InvocableVariable(label='Success' description='True if validation passed')
    global Boolean success;

    @InvocableVariable(label='Error Message' description='Error message when success is false')
    global String errorMessage;
}
```

### 4.3 Invocable Method Signature

```apex
@InvocableMethod(label='Render Data' description='Renders structured data in the agent UI. Validates JSON and display type.')
public static List<GenericRenderOutput> renderData(List<RenderDataInput> inputs)
```

**Input class:**
```apex
global class RenderDataInput {
    @InvocableVariable(required=true label='Data' description='JSON string following schema for the display type')
    global String data;

    @InvocableVariable(required=true label='Display Type' description='One of: table, card, list, key-value')
    global String display_type;
}
```

**Note:** Agent Script may use `display_type` as input name; Apex property can be `display_type` to match.

---

## 5. Custom Lightning Type

### 5.1 Folder Structure

```
force-app/main/default/lightningTypes/
└── genericRenderOutput/
    ├── schema.json
    ├── lightningDesktopGenAi/
    │   └── renderer.json
    └── enhancedWebChat/
        └── renderer.json
```

### 5.2 schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "lightning:objectType": "@apexClassType/c__GenericRenderOutput",
  "title": "Generic Render Output",
  "description": "Structured data or error for LWC rendering"
}
```

### 5.3 renderer.json (both channel folders)

```json
{
  "renderer": {
    "componentOverrides": {
      "$": {
        "definition": "c/genericDataRenderer"
      }
    }
  }
}
```

---

## 6. LWC: genericDataRenderer

### 6.1 Responsibilities

- Receive `value` (GenericRenderOutput) via `@api value`
- If `value.success` is false: display `value.errorMessage` in an error-style component
- If `value.success` is true: parse `value.jsonData`, render based on `value.displayType`:
  - **table:** lightning-datatable or custom table from columns + rows
  - **card:** lightning-card with field list
  - **list:** ul/ol or lightning-list
  - **key-value:** definition list (dl/dt/dd)

### 6.2 js-meta.xml

```xml
<?xml version="1.0" encoding="UTF-8"?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>64.0</apiVersion>
    <isExposed>true</isExposed>
    <targets>
        <target>lightning__AgentforceOutput</target>
    </targets>
    <targetConfigs>
        <targetConfig targets="lightning__AgentforceOutput">
            <property name="sourceType" type="String" default="genericRenderOutput"/>
        </targetConfig>
    </targetConfigs>
</LightningComponentBundle>
```

### 6.3 Rendering Logic (per displayType)

| displayType | Parse jsonData to | Render as |
|-------------|-------------------|-----------|
| table | { columns, rows } | lightning-datatable or HTML table |
| card | { title, fields } | lightning-card + field list |
| list | { items } | ul/li or lightning-list |
| key-value | { pairs } | dl/dt/dd or key-value layout |

### 6.4 Error Display

When `success === false`, show `errorMessage` in a lightning-alert or similar with variant="error".

### 6.5 Security

- Do not use `innerHTML` with raw user data
- Use `lwc:dom="manual"` only if necessary; prefer template bindings
- Sanitize or escape string values when rendering

---

## 7. Agent Script Wiring

### 7.1 Add core-skill to start_agent

**File:** `force-app/main/default/aiAuthoringBundles/customer_support_skill_demo/customer_support_skill_demo.agent`

**Change:** Add `core-skill-render-data-format` to instructionNames in start_agent:

```
instructionNames="role-customer-support-agent,core-skill-ltmManagement-service-agent,core-skill-user-otp-authentication,core-skill-txt-response-guidelines,core-skill-HTML-formatting-guidelines,core-skill-render-data-format"
```

### 7.2 Define render_data Action

Add to each topic that may return structured data (e.g. general_support, case_management, troubleshooting_support):

```yaml
render_data:
    description: "Display structured data to the user. Use when you have data to show in table, card, list, or key-value format."
    inputs:
        data: string
            description: "JSON string following the schema for the display type (see core-skill-render-data-format)."
        display_type: string
            description: "One of: table, card, list, key-value."
    outputs:
        result: object
            description: "Render output for LWC display (GenericRenderOutput)."
            complex_data_type_name: "c__genericRenderOutput"
    target: "apex://GenericRenderAction"
```

### 7.3 Expose as Reasoning Action (Tool)

In each topic's reasoning.actions, add:

```yaml
render_data: @actions.render_data
    with data=...
    with display_type=...
```

And in instructions, add guidance such as:
```
| When you have structured data to display (e.g. from a query or list of items), use {!@actions.render_data} with data as JSON and display_type (table, card, list, or key-value).
```

### 7.4 Topics to Update

| Topic | Add render_data? |
|-------|------------------|
| start_agent | No (add skill only) |
| general_support | Yes |
| troubleshooting_support | Yes |
| case_management | Yes |
| finalization | Optional |

---

## 8. Agent Action in Setup (Manual Step)

1. **Setup** → **Agentforce Agents** → **Agent Actions** → **New**
2. Choose **Apex** → select `GenericRenderAction` and method `renderData`
3. Configure inputs (data, display_type) to match the invocable method
4. For the output parameter, set **Output Rendering** to `genericRenderOutput` (Custom Lightning Type)
5. Save and assign to the agent

---

## 9. Package and Metadata

### 9.1 package.xml

Add if not present:

```xml
<types>
    <members>*</members>
    <name>LightningTypeBundle</name>
</types>
```

### 9.2 Seed Service

Add `core-skill-render-data-format` to `Agent_Skill_SeedService.seedCustomerSupportDemo()` with the full instruction body from §3.2.

---

## 10. Implementation Checklist

| # | Task | File/Location |
|---|------|---------------|
| 1 | Create GenericRenderAction.cls with RenderDataInput, GenericRenderOutput, validation logic | `force-app/main/default/classes/` |
| 2 | Create GenericRenderActionTest.cls | `force-app/main/default/classes/` |
| 3 | Add core-skill-render-data-format to Agent_Skill_SeedService | `Agent_Skill_SeedService.cls` |
| 4 | Create lightningTypes/genericRenderOutput/schema.json | `force-app/main/default/lightningTypes/` |
| 5 | Create renderer.json in lightningDesktopGenAi and enhancedWebChat | Same |
| 6 | Create genericDataRenderer LWC (html, js, js-meta.xml) | `force-app/main/default/lwc/` |
| 7 | Add LightningTypeBundle to package.xml | `manifest/package.xml` |
| 8 | Add core-skill-render-data-format to start_agent instructionNames | `customer_support_skill_demo.agent` |
| 9 | Add render_data action (target: apex://GenericRenderAction) to topics | Same |
| 10 | Add render_data to reasoning.actions in those topics | Same |
| 11 | Create Agent Action in Setup from Apex; set Output Rendering = genericRenderOutput | Setup UI |
| 12 | Deploy and reseed | CLI |
| 13 | Run seed script | `scripts/apex/seed_agent_skills.apex` |

---

## 11. Testing

### 11.1 Apex Unit Tests

- Valid JSON + valid display_type → success=true, jsonData populated
- Invalid JSON → success=false, errorMessage set
- Invalid display_type → success=false, errorMessage set
- Null/blank data → success=false
- Null/blank display_type → success=false
- Each display type (table, card, list, key-value) with valid JSON

### 11.2 Manual Agent Testing

- Ask agent to show a list of items → verify list render
- Ask agent to show case details → verify card or key-value render
- Ask agent to show multiple cases → verify table render
- Trigger invalid JSON (if possible) → verify error message displays

---

## 12. Dependencies and Risks

| Item | Notes |
|------|------|
| **Agentforce LWC support** | Requires Employee or Service (Enhanced Chat v2) agent |
| **API version** | 64.0+ for LightningTypeBundle |
| **LLM JSON production** | Agent may produce invalid JSON; core skill examples are critical |
| **Action repetition** | render_data must be defined in each topic; consider copy-paste or template |

---

## 13. Rollback

If issues arise:

1. Remove core-skill-render-data-format from instructionNames
2. Remove render_data action from topics
3. Re-seed to restore prior skill set (optional; new skill can remain in repo)
4. Deactivate or delete Agent Action in Setup

---

*Document Version: 1.1 | March 2025*
