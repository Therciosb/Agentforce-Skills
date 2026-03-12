# How to Use LWC in Agentforce Agent Responses

A step-by-step guide to render agent action output with custom Lightning Web Components (LWC).

---

## Overview

| Component | Purpose |
|-----------|---------|
| **Agent Action** | Apex invocable method that returns structured data |
| **Custom Lightning Type** | Maps the Apex output to your LWC |
| **LWC** | Renders the data in the agent chat UI |

**Flow:** Agent invokes action → Apex returns data → Custom Lightning Type → Your LWC displays it.

---

## Prerequisites

- Agentforce Employee Agent (Lightning Experience) or Service Agent (Enhanced Chat v2)
- API version 64.0+
- Apex invocable action that returns an **Apex class** (complex type)

**Note:** Custom LWC rendering applies only to actions whose **input or output** uses Apex classes. Simple types (String, List&lt;String&gt;) use built-in renderers.

---

## Step 1: Create an Apex Invocable Action

Your action must return an Apex class. Example:

```apex
public with sharing class CaseSummaryAgent {
    @InvocableMethod(label='Get Case Summary' description='Returns case summary for display')
    public static List<CaseSummaryOutput> getCaseSummary(List<Id> caseIds) {
        List<CaseSummaryOutput> results = new List<CaseSummaryOutput>();
        for (Case c : [SELECT Id, CaseNumber, Subject, Status, Priority FROM Case WHERE Id IN :caseIds]) {
            CaseSummaryOutput out = new CaseSummaryOutput();
            out.caseNumber = c.CaseNumber;
            out.subject = c.Subject;
            out.status = c.Status;
            out.priority = c.Priority;
            results.add(out);
        }
        return results;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class CaseSummaryOutput {
        @InvocableVariable(label='Case Number') global String caseNumber;
        @InvocableVariable(label='Subject') global String subject;
        @InvocableVariable(label='Status') global String status;
        @InvocableVariable(label='Priority') global String priority;
    }
}
```

**Key:** Use `@JsonAccess`, `global` visibility, and `@InvocableVariable` on output fields.

---

## Step 2: Create the Custom Lightning Type Bundle

Create folder structure:

```
force-app/main/default/
├── lightningTypes/
│   └── caseSummaryResponse/
│       ├── schema.json
│       └── lightningDesktopGenAi/          # Employee agent in Lightning
│           └── renderer.json
│       # For Service agent (Enhanced Chat v2), add:
│       └── enhancedWebChat/
│           └── renderer.json
```

### schema.json

References your Apex class. Use `@apexClassType` with namespace prefix `c` for your org:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "lightning:objectType": "@apexClassType/c__CaseSummaryOutput",
  "title": "Case Summary",
  "description": "Case summary for agent response display"
}
```

**Note:** If your Apex class is `CaseSummaryOutput` in the default namespace, use `c__CaseSummaryOutput`. For managed packages, use the package namespace.

### renderer.json (lightningDesktopGenAi or enhancedWebChat)

Points to your LWC. Use `$` for the top-level renderer:

```json
{
  "renderer": {
    "componentOverrides": {
      "$": {
        "definition": "c/caseSummaryCard"
      }
    }
  }
}
```

`c/caseSummaryCard` = namespace `c` + LWC name `caseSummaryCard`.

---

## Step 3: Create the LWC

Create the LWC in `force-app/main/default/lwc/`:

### caseSummaryCard.js-meta.xml

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
            <property name="sourceType" type="String" default="caseSummaryResponse"/>
        </targetConfig>
    </targetConfigs>
</LightningComponentBundle>
```

**Critical:** `lightning__AgentforceOutput` is required for output rendering. `sourceType` must match your Custom Lightning Type name.

### caseSummaryCard.html

```html
<template>
    <lightning-card title="Case Summary" icon-name="standard:case">
        <div class="slds-p-around_medium">
            <template if:true={hasData}>
                <dl class="slds-dl_horizontal">
                    <dt class="slds-dl_horizontal__label">Case Number</dt>
                    <dd class="slds-dl_horizontal__detail">{caseNumber}</dd>
                    <dt class="slds-dl_horizontal__label">Subject</dt>
                    <dd class="slds-dl_horizontal__detail">{subject}</dd>
                    <dt class="slds-dl_horizontal__label">Status</dt>
                    <dd class="slds-dl_horizontal__detail">{status}</dd>
                    <dt class="slds-dl_horizontal__label">Priority</dt>
                    <dd class="slds-dl_horizontal__detail">{priority}</dd>
                </dl>
            </template>
            <template if:false={hasData}>
                <p>No case data available.</p>
            </template>
        </div>
    </lightning-card>
</template>
```

### caseSummaryCard.js

The platform passes the Apex object via `@api value`. Use a getter to normalize:

```javascript
import { LightningElement, api } from 'lwc';

export default class CaseSummaryCard extends LightningElement {
    @api value;

    get hasData() {
        return this.value != null;
    }

    get caseNumber() {
        return this.value?.caseNumber ?? '';
    }

    get subject() {
        return this.value?.subject ?? '';
    }

    get status() {
        return this.value?.status ?? '';
    }

    get priority() {
        return this.value?.priority ?? '';
    }
}
```

**For a list of items** (e.g. multiple cases), `value` may be an array. Iterate with `for:each`:

```html
<template for:each={items} for:item="item">
    <div key={item.caseNumber}>{item.subject} - {item.status}</div>
</template>
```

```javascript
get items() {
    if (Array.isArray(this.value)) return this.value;
    return this.value ? [this.value] : [];
}
```

---

## Step 4: Add LightningTypeBundle to package.xml

Add to `manifest/package.xml`:

```xml
<types>
    <members>*</members>
    <name>LightningTypeBundle</name>
</types>
```

---

## Step 5: Create the Agent Action in Agentforce Builder

1. Go to **Setup** → **Agentforce Agents** → **Agent Actions** (or Agentforce Builder).
2. **New Agent Action** → choose **Apex**.
3. Select your Apex class and the invocable method.
4. For the **output** parameter (e.g. the field that returns `CaseSummaryOutput`):
   - Set **Output Rendering** to your custom Lightning type: `caseSummaryResponse`.
5. Save.
6. Assign the action to the relevant agent topic.

**Note:** "Unsupported Data Type" in Map to Variable can be ignored.

---

## Step 6: Wire the Action to Your Agent

### If using Agentforce Builder (UI)

- Add the action to the topic that should use it.
- The reasoning engine will invoke it when appropriate.

### If using Agent Script

Agent Script supports `apex://` targets. Define the action in your topic and reference it in reasoning.

#### 6a. Create the Agent Action in Setup (for LWC rendering)

1. **Setup** → **Agentforce Agents** → **Agent Actions** (or Agentforce Builder).
2. **New** → choose **Apex** → select your Apex class and invocable method.
3. For the output parameter, set **Output Rendering** to your Custom Lightning Type (e.g. `caseSummaryResponse`).
4. Save. This configures how the output is rendered when the Apex is invoked.

#### 6b. Define the action in your Agent Script

In your `.agent` file, add the action under the topic's `actions` block:

```yaml
topic general_support:
    label: "General Support Intake"
    description: "Primary customer support intake."

    actions:
        get_case_summary:
            description: "Retrieves case summary for display. Use when user asks about a specific case."
            inputs:
                case_id: string
                    description: "The Case Id to summarize."
            outputs:
                case_summary: object
                    description: "Case summary with caseNumber, subject, status, priority."
                    complex_data_type_name: "lightning__textType"
            target: "apex://CaseSummaryAgent"
```

**Target format:** `apex://` + Apex class name (e.g. `apex://CaseSummaryAgent`). The class must have an `@InvocableMethod`.

#### 6c. Expose the action in reasoning

Make it available as a tool so the LLM can call it:

```yaml
    reasoning:
        instructions: ->
            run @actions.load_and_compose_skills
                with instructionNames="skill-support-case-management"
                with existingInstructionBundle=@variables.instruction_bundle_json
                set @variables.composed_instructions=@outputs.instructionsBundle

            | {!@variables.composed_instructions}
            | When the user asks about a specific case (e.g. "What's the status of my case?"), use {!@actions.get_case_summary} with the case ID to fetch and display the case summary.

        actions:
            get_case_summary: @actions.get_case_summary
                with case_id=...
```

Or call it deterministically:

```yaml
            if @variables.case_id:
                run @actions.get_case_summary
                    with case_id=@variables.case_id
                    set @variables.case_summary=@outputs.case_summary
```

#### 6d. Output rendering

The **Agent Action** you created in Setup (Step 6a) controls Output Rendering. When the agent invokes `apex://CaseSummaryAgent`, the platform uses that Agent Action’s Output Rendering (your Custom Lightning Type + LWC) to display the result.

**Note:** Ensure the Agent Action in Setup uses the same Apex class as your `apex://` target. The Output Rendering on that Agent Action is what enables LWC rendering.

---

## Channel Folders

| Channel | Folder | Use Case |
|---------|--------|----------|
| Employee agent (Lightning) | `lightningDesktopGenAi` | Agents in Lightning Experience |
| Service agent (Enhanced Chat v2) | `enhancedWebChat` | Embedded chat, Service Cloud |

Create the channel folder and `renderer.json` for each channel where the agent runs.

---

## Troubleshooting

| Issue | Check |
|-------|-------|
| LWC not rendering | `sourceType` in js-meta.xml matches Custom Lightning Type name |
| LWC not rendering | `lightning__AgentforceOutput` target is set |
| LWC not rendering | `renderer.json` uses correct channel folder |
| No data in LWC | `@api value` receives the Apex object; verify field names match |
| Action not found | Agent action created in Setup; assigned to topic |

---

## Sample Files (Salesforce)

- [flightResponseCLTandLWC.zip](https://resources.docs.salesforce.com/rel1/doc/en-us/static/misc/flightResponseCLTAndLWCExample.zip) – Custom Lightning Type + LWC for output
- [apexClass.zip](https://resources.docs.salesforce.com/rel1/doc/en-us/static/misc/apexClassExample.zip) – Apex classes

---

## Reference

- [Enhance the Agent UI with Custom LWCs and Lightning Types](https://developer.salesforce.com/docs/ai/agentforce/guide/lightning-types.html)
- [lightning__AgentforceOutput Target](https://developer.salesforce.com/docs/platform/lwc/guide/targets-lightning-agentforce-output.html)
- [Custom Lightning Type Example (Full Editor + Renderer)](https://developer.salesforce.com/docs/ai/agentforce/guide/lightning-types-example-full-editor-renderer.html)
