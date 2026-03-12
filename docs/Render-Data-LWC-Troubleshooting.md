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

## Checklist for LWC Rendering

- [ ] Agent Action created in Setup from `GenericRenderAction.renderData`
- [ ] Output Rendering set to `genericRenderOutput` on that Agent Action
- [ ] **Show in conversation** checked for the Result output
- [ ] Agent Skills Agent Runtime permission set assigned to agent user (bot user)
- [ ] Agent Action assigned to the agent (or apex:// target resolves to it)
- [ ] Custom Lightning Type and LWC deployed to org
