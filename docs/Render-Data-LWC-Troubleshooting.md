# Render Data LWC Troubleshooting

## Preview Findings (render_data_test agent)

### Issue 1: Agent Not Invoking render_data Action

**Symptom:** The agent returns the table as plain text in the message instead of calling the `render_data` action.

**Trace evidence:** The session trace shows:
- `load_and_compose_skills` was invoked (Load And Compose Skills)
- The main topic had "Render Data" available as a tool
- The LLM chose to generate text ("Here is a table of 3 sample support cases...") instead of invoking the render_data action
- No `FunctionStep` for "Render Data" or "GenericRenderAction" in the plan

**Root cause:** The LLM is not following the instruction to call `render_data`; it prefers to output formatted text directly.

**Fix:** Strengthen the agent instructions to make action invocation mandatory and more explicit. Consider:
- Adding "NEVER output tables or structured data in your message. ALWAYS use render_data."
- Making the CRITICAL instruction more prominent
- Using deterministic `run` for certain intents if the platform supports it

---

### Issue 2: LWC Not Rendering (When Action Is Called)

**Symptom:** Even when the action is invoked, output appears as plain text instead of the custom LWC (genericDataRenderer).

**Root cause:** LWC rendering requires an **Agent Action** to be created in Setup with **Output Rendering** set to the Custom Lightning Type. The Agent Script `apex://GenericRenderAction` target does not automatically get LWC rendering—it must be configured in Setup.

**Required setup:**

1. **Create Agent Action in Setup**
   - Setup → Quick Find → **Agentforce Assets**
   - New Agent Action → Reference Action Type: **Apex** → Select `GenericRenderAction.renderData`

2. **Set Output Rendering**
   - The output is now **`result`** (type: GenericRenderOutput) — a single complex type
   - For the **`result`** output, set **Output Rendering** to the Custom Lightning Type **`genericRenderOutput`**
   - Custom Lightning types only appear when the output is a complex (Apex class) type, not flattened primitives

3. **Assign to Agent**
   - The Agent Action must be assigned to the agent (or the agent's apex:// target must resolve to this configured action)

4. **Verify Custom Lightning Type**
   - `genericRenderOutput` schema references `@apexClassType/c__GenericRenderOutput`
   - `genericDataRenderer` LWC has `lightning__AgentforceOutput` target
   - Renderer config: `c/genericDataRenderer` for `$` (top-level)

**Reference:** [Lightning Types - Agentforce](https://developer.salesforce.com/docs/ai/agentforce/guide/lightning-types.html): *"For the action's output, edit the Output Rendering parameter and select your custom Lightning type."*

---

### Issue 3: Agent User Permissions

**Finding:** The agent user (bot user) may not have the **Agent Skills Agent Runtime** permission set assigned.

**Impact:** Without this permission set, the agent user cannot execute `GenericRenderAction` (Apex). The action may fail with a permission error when invoked.

**Fix:** Assign **Agent Skills Agent Runtime** to the agent user in Setup → Users → [agent user] → Permission Set Assignments.

**What the permission set includes:**
- `GenericRenderAction` (Apex class access)
- `Agent_Skill_LoadAndCompose` (Apex class access)
- `Load_And_Compose_Agent_Skills`, `Render_Data` (Flow access; optional; agents use Apex directly)
- `Agent_Skills_Repo__c` (object read)

---

### Issue 4: Output Not Shown in Conversation

**Symptom:** Action executes successfully (trace shows `FunctionStep` with valid output), but nothing renders in the chat.

**Fix:** In the Agent Action's Output configuration (Setup → Agentforce Assets → [your Agent Action] → Output → Result → Advanced Settings):
- Check **Show in conversation** — Without this, the output is not displayed in the chat UI even when the action returns data.

---

### Issue 5: Agent Action Not Assigned to Agent

**Symptom:** Agent Action exists but output rendering does not apply.

**Fix:** The Agent Action must be assigned to the agent. For Agent Script agents:
1. Go to **Agentforce Builder** (or Setup → Agentforce Agents).
2. Open the agent (e.g. `render_data_test`).
3. Ensure the agent's action list includes the action that references `GenericRenderAction.renderData`.
4. When the agent is published from Agent Script, the `apex://GenericRenderAction` target should resolve to the Agent Action you created in Setup. If you created the Agent Action manually, verify it matches the same Apex class and method.

---

### Issue 6: "Assigned to Active Agent" Not Showing in Setup

**Symptom:** The Render_Data Agent Action in Setup shows "Assigned to Active Agent: No" even though the agent uses `apex://GenericRenderAction` and LWC rendering works.

**Investigation findings:**

| Target format | Result |
|---------------|--------|
| `apex://GenericRenderAction` | Works. Platform resolves to Agent Action for Output Rendering. LWC renders correctly. "Assigned to Active Agent" may remain unchecked. |
| `flow://Render_Data` | Invokes the Flow (wraps Apex). GenAiPlannerBundle uses this. Output Rendering requires Apex class output—Flow returns flat primitives, so custom Lightning Type may not apply. |
| `standardInvocableAction://Render_Data` | Causes internal error during publish ("Internal Error, try again later"). Would reference the Agent Action by API name directly. |
| `agentAction://Render_Data` | Not supported; validation error. |

**Root cause:** Agent Script supports `apex://`, `flow://`, and `generatePromptResponse://` targets. There is no documented target format that references a Setup-defined Agent Action by its API name. The "Assigned to Active Agent" flag appears to be set only when the agent explicitly references the Agent Action metadata (e.g., via Builder UI assignment), not when using `apex://ClassName`.

**Recommendations:**

1. **Keep `apex://GenericRenderAction`** — This is the correct target for LWC rendering. The platform resolves the Apex class to your Agent Action for Output Rendering. Functionality is correct; the Setup indicator may be a platform limitation.

2. **Post-publish assignment (if available)** — After publishing from Agent Script, open the agent in **Agentforce Builder** and check if you can add the Render_Data Agent Action from the Asset Library to the topic. This may set "Assigned to Active Agent."

3. **Report to Salesforce** — If "Assigned to Active Agent" is required for compliance or visibility, consider opening a case: Agent Script `apex://` targets that resolve to Setup Agent Actions should update the "Assigned to Active Agent" flag.

4. **Alternative: Flow-based Agent Action** — If you create an Agent Action that references the **Render_Data Flow** (not the Apex) and use `flow://Render_Data` in the agent script, the Flow invocation might register as "Assigned to Active Agent." However, Flow outputs are primitive; Output Rendering with custom Lightning types typically requires Apex class output, so LWC rendering may not work with this approach.

---

## Checklist for LWC Rendering

- [ ] Agent Action created in Setup from `GenericRenderAction.renderData`
- [ ] Output Rendering set to `genericRenderOutput` on that Agent Action
- [ ] **Show in conversation** checked for the Result output
- [ ] Agent Skills Agent Runtime permission set assigned to agent user (bot user)
- [ ] Agent Action assigned to the agent (or apex:// target resolves to it)
- [ ] Custom Lightning Type and LWC deployed to org

---

### Enhanced Chat v2: Still Plain Text After Action Succeeds

**Symptom:** Action executes successfully (trace shows `FunctionStep` with `success: true`), but output appears as plain text in Enhanced Chat instead of the LWC (lightning-datatable, card, etc.).

**Verify in Setup:**

1. **Agent Action → Output Rendering**
   - Setup → Quick Find → **Agentforce Assets** → **Agent Actions**
   - Open the Render_Data (or GenericRenderAction) Agent Action
   - Output → Result → **Output Rendering** must be set to **genericRenderOutput** (Custom Lightning Type)
   - Output → Result → Advanced Settings → **Show in conversation** must be checked

2. **Custom Lightning Type deployed**
   - `lightningTypes/genericRenderOutput/` with `schema.json`, `enhancedWebChat/renderer.json`
   - Deploy: `sf project deploy start --source-dir force-app/main/default/lightningTypes`

3. **LWC deployed with correct sourceType**
   - `genericDataRenderer` has `sourceType name="c__genericRenderOutput"` in js-meta.xml
   - Deploy: `sf project deploy start --source-dir force-app/main/default/lwc/genericDataRenderer`

4. **Connection / channel**
   - Ensure the Enhanced Chat connection uses the agent that invokes the action
   - Re-publish the agent after any Setup changes: `sf agent publish authoring-bundle --api-name render_data_test`

**If still plain text:** The platform may not resolve `apex://GenericRenderAction` to the Agent Action's Output Rendering in Enhanced Chat. Try assigning the Render_Data Agent Action explicitly to the agent in Agentforce Builder (add from Asset Library to the topic).
