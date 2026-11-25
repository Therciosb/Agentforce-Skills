@IsTest
private class Agent_Skill_Binding_Controller_Test {
    @TestSetup
    static void setup() {
        insert new List<Agent_Skills_Repo__c>{
            skill('role-test-agent', 'Role', 'Always on.'),
            skill('skill-alpha', 'Skill', 'Use for alpha requests.'),
            skill('skill-beta', 'Skill', 'Use for beta requests.'),
            skill('workflow-alpha-steps', 'Workflow', 'Steps for alpha.')
        };
    }

    private static User author() {
        User u = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            LastName = 'Author',
            Email = 'author@agentskills.test',
            Username = 'author' + DateTime.now().getTime() + '@agentskills.test',
            Alias = 'askauth',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;
        insert new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Agent_Skills_Author' LIMIT 1].Id
        );
        return u;
    }

    private static Agent_Skills_Repo__c skill(String name, String type, String whenToUse) {
        return new Agent_Skills_Repo__c(
            Name = name,
            Type__c = type,
            Status__c = 'active',
            Version__c = 'v1',
            Locale__c = 'en-US',
            ExternalId__c = name + ':v1:en-US',
            WhenToUse__c = whenToUse,
            InstructionBody__c = 'Body of ' + name
        );
    }

    private static Agent_Skill_Binding_Controller.BindingItem item(String name, String mode) {
        Agent_Skill_Binding_Controller.BindingItem bi = new Agent_Skill_Binding_Controller.BindingItem();
        bi.skillName = name;
        bi.mode = mode;
        return bi;
    }

    private static Agent_Skill_Binding_Controller.BindingDetail payload(List<Agent_Skill_Binding_Controller.BindingItem> items) {
        Agent_Skill_Binding_Controller.BindingDetail d = new Agent_Skill_Binding_Controller.BindingDetail();
        d.agentName = 'test_agent';
        d.name = 'Test Agent';
        d.items = items;
        return d;
    }

    @IsTest
    static void saveLoadUpdateAndPreview() {
        System.runAs(author()) {
            saveLoadUpdateAndPreviewAsAuthor();
        }
    }

    private static void saveLoadUpdateAndPreviewAsAuthor() {
        Id bindingId = Agent_Skill_Binding_Controller.saveBinding(JSON.serialize(payload(new List<Agent_Skill_Binding_Controller.BindingItem>{
            item('role-test-agent', 'Always'),
            item('skill-alpha', 'Default'),
            item('skill-beta', 'Selectable')
        })));

        Agent_Skill_Binding_Controller.BindingDetail loaded = Agent_Skill_Binding_Controller.getBinding(bindingId);
        Assert.areEqual('test_agent', loaded.agentName);
        Assert.areEqual('Active', loaded.status);
        Assert.areEqual(3, loaded.items.size());
        Assert.areEqual('role-test-agent', loaded.items[0].skillName);

        List<Agent_Skill_Binding_Controller.BindingSummary> summaries = Agent_Skill_Binding_Controller.listBindings();
        Assert.areEqual(1, summaries.size());
        Assert.areEqual(1, summaries[0].alwaysCount);
        Assert.areEqual(2, summaries[0].selectableCount);

        loaded.items.remove(2);
        Agent_Skill_Binding_Controller.saveBinding(JSON.serialize(loaded));
        Assert.areEqual(2, [SELECT COUNT() FROM Agent_Skill_Binding_Item__c WHERE Binding__c = :bindingId]);

        Agent_Skill_State.SkillState state = Agent_Skill_Binding_Controller.previewState('test_agent', null, '');
        Assert.areEqual('skill-alpha', state.active_skills);
        Assert.isTrue(state.skill_instructions.contains('Body of role-test-agent'));

        Agent_Skill_Binding_Controller.deleteBinding(bindingId);
        Assert.areEqual(0, [SELECT COUNT() FROM Agent_Skill_Binding_Item__c]);
    }

    @IsTest
    static void validationRejectsBadWiring() {
        List<String> errors = Agent_Skill_Binding_Controller.validate(payload(new List<Agent_Skill_Binding_Controller.BindingItem>{
            item('skill-alpha', 'Selectable'),
            item('skill-alpha', 'Selectable'),
            item('workflow-alpha-steps', 'Bogus')
        }));
        String joined = String.join(errors, ' ');
        Assert.isTrue(joined.contains('Skill wired twice: skill-alpha'));
        Assert.isTrue(joined.contains('Invalid mode for workflow-alpha-steps'));
        Assert.isTrue(joined.contains('is a workflow'));
        Assert.isTrue(joined.contains('Mark at least one selectable skill as Default'));

        try {
            Agent_Skill_Binding_Controller.saveBinding(JSON.serialize(payload(new List<Agent_Skill_Binding_Controller.BindingItem>())));
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex);
        }
    }

    @IsTest
    static void wireableSkillsExcludeWorkflowsAndSnippetNamesAgent() {
        List<Agent_Skill_Binding_Controller.WireableSkill> skills;
        System.runAs(author()) {
            skills = Agent_Skill_Binding_Controller.listWireableSkills(null);
        }
        Set<String> names = new Set<String>();
        for (Agent_Skill_Binding_Controller.WireableSkill s : skills) {
            names.add(s.name);
        }
        Assert.isTrue(names.contains('skill-alpha'));
        Assert.isFalse(names.contains('workflow-alpha-steps'));

        String snippet = Agent_Skill_Binding_Controller.getScriptSnippet('my_support_agent', 'billing_host');
        Assert.isTrue(snippet.contains('agent_name: mutable string = "my_support_agent"'));
        Assert.isTrue(snippet.contains('subagent billing_host:'));
        Assert.isTrue(snippet.contains('with subagentName="billing_host"'));
        Assert.isFalse(snippet.contains('available when'));
        Assert.isNotNull(Agent_Skill_Binding_Controller.listOrgAgents());
    }

    @IsTest
    static void runtimeRulesSaveAndDriveSnippet() {
        Agent_Skill_Binding_Controller.BindingDetail d = payload(new List<Agent_Skill_Binding_Controller.BindingItem>{
            item('role-test-agent', 'Always'),
            item('skill-alpha', 'Default')
        });
        d.requireApproval = true;
        d.agentTools = 'create_case, get_order_status';

        Agent_Skill_Binding_Controller.BindingDetail loaded;
        String snippet;
        System.runAs(author()) {
            loaded = Agent_Skill_Binding_Controller.getBinding(Agent_Skill_Binding_Controller.saveBinding(JSON.serialize(d)));
            snippet = Agent_Skill_Binding_Controller.getScriptSnippet('test_agent', null);
        }

        Assert.isTrue(loaded.requireApproval);
        Assert.areEqual('create_case,get_order_status', loaded.agentTools);
        Assert.isTrue(snippet.contains('get_order_status: @actions.get_order_status'));
        Assert.isTrue(snippet.contains('available when @variables.skill_state.tools.create_case == True'));
    }

    @IsTest
    static void subagentsHaveSeparateWiring() {
        Agent_Skill_Binding_Controller.BindingDetail billing = payload(new List<Agent_Skill_Binding_Controller.BindingItem>{
            item('role-test-agent', 'Always'),
            item('skill-alpha', 'Default')
        });
        billing.subagent = 'billing_host';
        Agent_Skill_Binding_Controller.BindingDetail support = payload(new List<Agent_Skill_Binding_Controller.BindingItem>{
            item('skill-beta', 'Default')
        });
        support.subagent = 'support_host';

        Agent_Skill_Binding_Controller.WiringSummary summary;
        Agent_Skill_State.SkillState supportState;
        List<String> subagents;
        String duplicateError;
        System.runAs(author()) {
            Agent_Skill_Binding_Controller.saveBinding(JSON.serialize(billing));
            Agent_Skill_Binding_Controller.saveBinding(JSON.serialize(support));
            try {
                Agent_Skill_Binding_Controller.saveBinding(JSON.serialize(support));
            } catch (AuraHandledException ex) {
                duplicateError = ex.getMessage();
            }
            summary = Agent_Skill_Binding_Controller.getWiringSummary('test_agent', 'billing_host');
            supportState = Agent_Skill_Binding_Controller.previewState('test_agent', 'support_host', '');
            subagents = Agent_Skill_Binding_Controller.listAgentSubagents('test_agent');
        }

        Assert.areEqual(2, [SELECT COUNT() FROM Agent_Skill_Binding__c WHERE Agent_Developer_Name__c = 'test_agent']);
        Assert.areEqual('test_agent:billing_host', [SELECT Binding_Key__c FROM Agent_Skill_Binding__c WHERE Subagent__c = 'billing_host'].Binding_Key__c);
        Assert.isNotNull(duplicateError, 'Saving a second wiring for the same subagent must fail');
        Assert.isTrue(summary.found);
        Assert.areEqual('billing_host', summary.bindingSubagent);
        Assert.areEqual(new List<String>{ 'role-test-agent' }, summary.always);
        Assert.areEqual(new List<String>{ 'skill-alpha' }, summary.defaults);
        Assert.areEqual('skill-beta', supportState.active_skills);
        Assert.isTrue(subagents.contains('billing_host') && subagents.contains('support_host'));
        Assert.isFalse(Agent_Skill_Binding_Controller.getWiringSummary('test_agent', 'unknown_host').found);
    }

    @IsTest
    static void validationRejectsBadSubagentName() {
        Agent_Skill_Binding_Controller.BindingDetail d = payload(new List<Agent_Skill_Binding_Controller.BindingItem>{ item('role-test-agent', 'Always') });
        d.subagent = 'billing host';

        Assert.isTrue(String.join(Agent_Skill_Binding_Controller.validate(d), ' ').contains('Subagent name'));
    }

    @IsTest
    static void validationRejectsNonActionToolNames() {
        Agent_Skill_Binding_Controller.BindingDetail d = payload(new List<Agent_Skill_Binding_Controller.BindingItem>{ item('role-test-agent', 'Always') });
        d.agentTools = 'create_case,CreateCase';

        String joined = String.join(Agent_Skill_Binding_Controller.validate(d), ' ');

        Assert.isTrue(joined.contains('CreateCase'));
        Assert.isFalse(joined.contains('create_case.'));
    }
}
