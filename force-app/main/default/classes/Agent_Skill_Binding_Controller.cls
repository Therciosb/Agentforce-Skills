public with sharing class Agent_Skill_Binding_Controller {
    private static final Set<String> MODES = new Set<String>{ 'Always', 'Selectable', 'Default' };
    private static final Set<String> WIREABLE_TYPES = new Set<String>{ 'Role', 'Core_Skill', 'Skill' };

    public class BindingSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String agentName;
        @AuraEnabled public String status;
        @AuraEnabled public Integer alwaysCount = 0;
        @AuraEnabled public Integer selectableCount = 0;
    }

    public class BindingItem {
        @AuraEnabled public String skillName { get; set; }
        @AuraEnabled public String mode { get; set; }
        @AuraEnabled public Integer order { get; set; }
    }

    public class BindingDetail {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String agentName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String locale { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Boolean requireApproval { get; set; }
        @AuraEnabled public String agentTools { get; set; }
        @AuraEnabled public List<BindingItem> items { get; set; }
    }

    public class WireableSkill {
        @AuraEnabled public String name;
        @AuraEnabled public String type;
        @AuraEnabled public String whenToUse;
    }

    public class OrgAgent {
        @AuraEnabled public String developerName;
        @AuraEnabled public String label;
    }

    @AuraEnabled(cacheable=true)
    public static List<BindingSummary> listBindings() {
        List<BindingSummary> rows = new List<BindingSummary>();
        for (Agent_Skill_Binding__c b : [
            SELECT Id, Name, Agent_Developer_Name__c, Status__c, (SELECT Mode__c FROM Items__r)
            FROM Agent_Skill_Binding__c
            WITH USER_MODE
            ORDER BY Name
            LIMIT 500
        ]) {
            BindingSummary row = new BindingSummary();
            row.id = b.Id;
            row.name = b.Name;
            row.agentName = b.Agent_Developer_Name__c;
            row.status = b.Status__c;
            for (Agent_Skill_Binding_Item__c item : b.Items__r) {
                if (item.Mode__c == 'Always') {
                    row.alwaysCount++;
                } else {
                    row.selectableCount++;
                }
            }
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static BindingDetail getBinding(Id bindingId) {
        List<Agent_Skill_Binding__c> found = [
            SELECT Id, Name, Agent_Developer_Name__c, Status__c, Locale__c, Description__c, Require_Approval__c, Agent_Tools__c,
                (SELECT Skill_Name__c, Mode__c, Order__c FROM Items__r ORDER BY Order__c NULLS LAST, Skill_Name__c)
            FROM Agent_Skill_Binding__c
            WHERE Id = :bindingId
            WITH USER_MODE
        ];
        if (found.isEmpty()) {
            throw new AuraHandledException('Binding not found.');
        }
        Agent_Skill_Binding__c b = found[0];
        BindingDetail detail = new BindingDetail();
        detail.id = b.Id;
        detail.name = b.Name;
        detail.agentName = b.Agent_Developer_Name__c;
        detail.status = b.Status__c;
        detail.locale = b.Locale__c;
        detail.description = b.Description__c;
        detail.requireApproval = b.Require_Approval__c;
        detail.agentTools = b.Agent_Tools__c;
        detail.items = new List<BindingItem>();
        for (Agent_Skill_Binding_Item__c item : b.Items__r) {
            BindingItem bi = new BindingItem();
            bi.skillName = item.Skill_Name__c;
            bi.mode = item.Mode__c;
            bi.order = item.Order__c == null ? null : item.Order__c.intValue();
            detail.items.add(bi);
        }
        return detail;
    }

    @AuraEnabled(cacheable=true)
    public static List<WireableSkill> listWireableSkills(String locale) {
        String effectiveLocale = String.isBlank(locale) ? 'en-US' : locale;
        Map<String, WireableSkill> byName = new Map<String, WireableSkill>();
        for (Agent_Skills_Repo__c rec : [
            SELECT Name, Type__c, WhenToUse__c
            FROM Agent_Skills_Repo__c
            WHERE Status__c = 'active' AND Locale__c = :effectiveLocale AND Type__c IN :WIREABLE_TYPES
            WITH USER_MODE
            ORDER BY Type__c, Name
            LIMIT 2000
        ]) {
            if (byName.containsKey(rec.Name)) {
                continue;
            }
            WireableSkill s = new WireableSkill();
            s.name = rec.Name;
            s.type = rec.Type__c;
            s.whenToUse = rec.WhenToUse__c;
            byName.put(rec.Name, s);
        }
        return byName.values();
    }

    @AuraEnabled(cacheable=true)
    public static List<OrgAgent> listOrgAgents() {
        List<OrgAgent> agents = new List<OrgAgent>();
        try {
            for (BotDefinition bot : [SELECT DeveloperName, MasterLabel FROM BotDefinition ORDER BY MasterLabel LIMIT 500]) {
                OrgAgent a = new OrgAgent();
                a.developerName = bot.DeveloperName;
                a.label = bot.MasterLabel;
                agents.add(a);
            }
        } catch (Exception ex) {
            // BotDefinition is not queryable without Agentforce/Einstein Bots; the UI falls back to free text.
            return agents;
        }
        return agents;
    }

    @AuraEnabled
    public static Id saveBinding(String payloadJson) {
        BindingDetail input;
        try {
            input = (BindingDetail) JSON.deserialize(payloadJson, BindingDetail.class);
        } catch (Exception ex) {
            throw new AuraHandledException('Invalid binding payload.');
        }
        List<String> errors = validate(input);
        if (!errors.isEmpty()) {
            throw new AuraHandledException(String.join(errors, ' '));
        }

        Agent_Skill_Binding__c binding = new Agent_Skill_Binding__c(
            Id = input.id,
            Name = String.isBlank(input.name) ? input.agentName.trim() : input.name.trim(),
            Agent_Developer_Name__c = input.agentName.trim(),
            Status__c = String.isBlank(input.status) ? 'Active' : input.status,
            Locale__c = String.isBlank(input.locale) ? 'en-US' : input.locale.trim(),
            Description__c = input.description,
            Require_Approval__c = input.requireApproval == true,
            Agent_Tools__c = String.isBlank(input.agentTools) ? null : input.agentTools.deleteWhitespace()
        );

        Savepoint sp = Database.setSavepoint();
        try {
            Database.upsert(binding, AccessLevel.USER_MODE);
            if (input.id != null) {
                Database.delete([SELECT Id FROM Agent_Skill_Binding_Item__c WHERE Binding__c = :binding.Id WITH USER_MODE], AccessLevel.USER_MODE);
            }
            List<Agent_Skill_Binding_Item__c> items = new List<Agent_Skill_Binding_Item__c>();
            Integer position = 1;
            for (BindingItem bi : input.items) {
                items.add(new Agent_Skill_Binding_Item__c(
                    Binding__c = binding.Id,
                    Skill_Name__c = bi.skillName.trim(),
                    Mode__c = bi.mode,
                    Order__c = bi.order == null ? position : bi.order
                ));
                position++;
            }
            Database.insert(items, AccessLevel.USER_MODE);
        } catch (DmlException ex) {
            Database.rollback(sp);
            throw new AuraHandledException(ex.getDmlMessage(0));
        } catch (Exception ex) {
            Database.rollback(sp);
            throw new AuraHandledException(ex.getMessage());
        }
        return binding.Id;
    }

    @AuraEnabled
    public static void deleteBinding(Id bindingId) {
        try {
            Database.delete(new Agent_Skill_Binding__c(Id = bindingId), AccessLevel.USER_MODE);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static Agent_Skill_State.SkillState previewState(String agentName, String requestedSkills) {
        Agent_Skill_State.Request req = new Agent_Skill_State.Request();
        req.agentName = agentName;
        req.requestedSkills = requestedSkills;
        Agent_Skill_State.recordUsage = false;
        return Agent_Skill_State.resolve(new List<Agent_Skill_State.Request>{ req })[0].skillState;
    }

    @AuraEnabled
    public static String getScriptSnippet(String agentName) {
        String name = String.isBlank(agentName) ? 'my_agent' : agentName.trim();
        String snippet = SNIPPET.replace('{AGENT_NAME}', name);
        Agent_Skill_State.Wiring wiring = Agent_Skill_State.loadWiring(name);
        if (wiring == null || String.isBlank(wiring.agentTools)) {
            return snippet;
        }
        List<String> gated = new List<String>();
        for (String tool : wiring.agentTools.split(',')) {
            if (String.isNotBlank(tool)) {
                gated.add('            ' + tool + ': @actions.' + tool);
                gated.add('                available when @variables.skill_state.tools.' + tool + ' == True');
            }
        }
        return snippet + '\n' + String.join(gated, '\n');
    }

    @TestVisible
    private static List<String> validate(BindingDetail input) {
        List<String> errors = new List<String>();
        if (input == null || String.isBlank(input.agentName)) {
            errors.add('Agent developer name is required.');
            return errors;
        }
        if (!Pattern.matches('[A-Za-z][A-Za-z0-9_]*', input.agentName.trim())) {
            errors.add('Agent developer name may contain only letters, numbers, and underscores, and must start with a letter.');
        }
        if (String.isNotBlank(input.agentTools)) {
            for (String tool : input.agentTools.deleteWhitespace().split(',')) {
                if (String.isNotBlank(tool) && !Pattern.matches('[a-z][a-z0-9_]*', tool)) {
                    errors.add('Agent tool names must be snake_case action names as declared in the agent script: ' + tool + '.');
                }
            }
        }
        if (input.items == null || input.items.isEmpty()) {
            errors.add('Wire at least one skill.');
            return errors;
        }
        Set<String> seen = new Set<String>();
        Integer selectable = 0;
        Integer defaults = 0;
        for (BindingItem bi : input.items) {
            if (bi == null || String.isBlank(bi.skillName)) {
                errors.add('Every wired skill needs a name.');
                continue;
            }
            String name = bi.skillName.trim();
            if (!seen.add(name)) {
                errors.add('Skill wired twice: ' + name + '.');
            }
            if (!MODES.contains(bi.mode)) {
                errors.add('Invalid mode for ' + name + ': ' + bi.mode + '.');
            } else if (bi.mode != 'Always') {
                selectable++;
                if (bi.mode == 'Default') {
                    defaults++;
                }
            }
            if (name.startsWith('workflow-')) {
                errors.add(name + ' is a workflow; workflows load through the References of the skills that use them.');
            }
        }
        if (selectable > 0 && defaults == 0) {
            errors.add('Mark at least one selectable skill as Default.');
        }
        return errors;
    }

    private static final String SNIPPET = String.join(new List<String>{
        'variables:',
        '    agent_name: mutable string = "{AGENT_NAME}"',
        '        description: "Developer name used to look up this agent\'s skill wiring."',
        '    skill_state: mutable object = {"active_skills": "unloaded"}',
        '        description: "Skill menu, active skills, composed instructions, and warnings from Agent_Skill_State."',
        '    requested_skills: mutable string = ""',
        '        description: "CSV of skills the model asked for. A change triggers a reload."',
        '',
        'start_agent agent_router:',
        '    description: "Hand off to the skill host."',
        '    reasoning:',
        '        instructions: ->',
        '            transition to @subagent.skill_host',
        '',
        'subagent skill_host:',
        '    description: "Single host subagent. Behavior and tool use are driven by the active skills."',
        '    actions:',
        '        load_skill_state:',
        '            description: "Resolve requested skills against this agent\'s wiring and return the skill state."',
        '            inputs:',
        '                agentName: string',
        '                    description: "Developer name of the calling agent."',
        '                requestedSkills: string',
        '                    description: "CSV of skill names to activate."',
        '            outputs:',
        '                skillState: object',
        '                    description: "Skill menu, active skills, composed instructions, and warnings."',
        '                    complex_data_type_name: "@apexClassType/c__Agent_Skill_State$SkillState"',
        '                    filter_from_agent: True',
        '                activeSkills: string',
        '                    description: "CSV of the skills actually activated."',
        '                    filter_from_agent: True',
        '            target: "apex://Agent_Skill_State"',
        '        # Add the tools your skills use here.',
        '    reasoning:',
        '        instructions: ->',
        '            if @variables.requested_skills != @variables.skill_state.active_skills:',
        '                run @actions.load_skill_state',
        '                    with agentName=@variables.agent_name',
        '                    with requestedSkills=@variables.requested_skills',
        '                    set @variables.skill_state=@outputs.skillState',
        '                    set @variables.requested_skills=@outputs.activeSkills',
        '            | Skills available to this agent:',
        '            | {!@variables.skill_state.skill_menu}',
        '            |',
        '            | Active skills: {!@variables.skill_state.active_skills}',
        '            | Before answering, check the request against the skills above. If it needs a skill that is not active, call {!@actions.switch_skills} with the complete CSV of skill names to use (no spaces after commas), then answer using the reloaded instructions.',
        '            |',
        '            | Follow these instructions. They determine what to do and which tools to use:',
        '            | {!@variables.skill_state.skill_instructions}',
        '        actions:',
        '            switch_skills: @utils.setVariables',
        '                description: "Change which skills are active for this request. Pass the complete CSV of skill names from the skill menu."',
        '                with requested_skills=...'
    }, '\n');
}
