# Agent Skills Admin App Setup

## Agent bot user (Load And Compose)

For agents that invoke `apex://Agent_Skill_LoadAndCompose` (or `flow://Load_And_Compose_Agent_Skills`), assign the **Agent Skills Agent Runtime** permission set to the bot user (e.g. `default_agent_user` in the agent config). This grants:

- Apex class access: `Agent_Skill_LoadAndCompose`, `Agent_Skill_Loader`, `Agent_Skill_PromptComposer`, `GenericRenderAction`
- Flow access: `Load_And_Compose_Agent_Skills`, `Compose_Agent_Skills_Prompt`, `Render_Data` (optional; agents use Apex directly)
- Read access to `Agent_Skills_Repo__c`

**Setup:** Users → select the bot user → Permission Set Assignments → Add Assignments → Agent Skills Agent Runtime.

## Data not showing in list views

If you see the tabs but no records:

1. **Select the "All" list view** – Use the list view dropdown (top of the list) and choose **All** instead of "Recently Viewed" or "My Records".
2. **Refresh the page** – Hard refresh (Ctrl+Shift+R or Cmd+Shift+R).

The seed script creates 1 role, 4 core skills, 3 skills, 8 workflows, and 3 Agent_Context__c demo records. Records are owned by the user who ran the seed.

## Instruction Body not showing on record page

If you only see metadata (Name, ExternalId__c, Status__c, etc.) but not Description__c, WhenToUse__c, or InstructionBody__c:

1. **Log out and log back in** – Layout and field permission changes require a new session.
2. **Confirm your profile** – Layout assignments were added to the Admin profile. If you use a different profile (e.g. Modified Admin User), go to **Setup → Object Manager → Agent_Skills_Repo__c → Page Layouts** and assign "Agent Skills Repo Layout" to your profile.
3. **Check field-level security** – Go to **Setup → Object Manager → Agent_Skills_Repo__c → Fields and Relationships**. For InstructionBody__c, Description__c, and WhenToUse__c, ensure your profile has Read and Edit access.

## Tab visibility

If you only see the **Home** tab in the Agent Skills Admin app, your profile may not have tab visibility for the custom objects.

### Fix: Add tab visibility to your profile

1. Go to **Setup** → **Users** → **Profiles**
2. Open your profile (e.g. **System Administrator** or **Admin**)
3. Find **Tab Settings** (or **Object Settings** → **Tab Settings**)
4. Click **Edit**
5. For **Agent Skills Repo**, set visibility to **Default On**
6. Save

### Alternative: Use direct URLs

You can open the object list views directly:

- Agent Skills Repo: `/lightning/o/Agent_Skills_Repo__c/list`

Append these to your org URL, e.g.:
`https://your-org.lightning.force.com/lightning/o/Agent_Skills_Repo__c/list`
