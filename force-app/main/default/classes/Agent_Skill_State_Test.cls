@IsTest
private class Agent_Skill_State_Test {
    private static final String AGENT = 'customer_support_progressive_pd2';

    @TestSetup
    static void setup() {
        insert new List<Agent_Skills_Repo__c>{
            skill('role-customer-support-agent', 'Role', 'Use in all sessions.'),
            skill('skill-product-information-qa', 'Skill', 'Use for product questions.'),
            skill('skill-troubleshooting-support', 'Skill', 'Use for device problems.')
        };
        Agent_Skills_Repo__c troubleshooting = [SELECT Id FROM Agent_Skills_Repo__c WHERE Name = 'skill-troubleshooting-support'];
        troubleshooting.InstructionBody__c = 'Open a case with [[tool:CreateCase]] when steps fail.';
        update troubleshooting;
        Agent_Skill_Binding__c binding = new Agent_Skill_Binding__c(
            Name = 'Customer Support PD2',
            Agent_Developer_Name__c = AGENT,
            Status__c = 'Active',
            Locale__c = 'en-US'
        );
        insert binding;
        insert new List<Agent_Skill_Binding_Item__c>{
            item(binding.Id, 'role-customer-support-agent', 'Always', 1),
            item(binding.Id, 'skill-product-information-qa', 'Default', 2),
            item(binding.Id, 'skill-troubleshooting-support', 'Selectable', 3)
        };
    }

    private static Agent_Skill_Binding_Item__c item(Id bindingId, String skillName, String mode, Integer order) {
        return new Agent_Skill_Binding_Item__c(Binding__c = bindingId, Skill_Name__c = skillName, Mode__c = mode, Order__c = order);
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

    private static Agent_Skill_State.Response run(String agentName, String requested) {
        return run(agentName, null, requested);
    }

    private static Agent_Skill_State.Response run(String agentName, String subagentName, String requested) {
        Agent_Skill_State.Request req = new Agent_Skill_State.Request();
        req.agentName = agentName;
        req.subagentName = subagentName;
        req.requestedSkills = requested;
        return Agent_Skill_State.resolve(new List<Agent_Skill_State.Request>{ req })[0];
    }

    @IsTest
    static void blankRequestLoadsDefaults() {
        Agent_Skill_State.Response res = run(AGENT, '');

        Assert.areEqual('skill-product-information-qa', res.activeSkills);
        Assert.areEqual(res.activeSkills, res.skillState.active_skills);
        Assert.isTrue(res.skillState.skill_instructions.contains('Body of skill-product-information-qa'));
        Assert.isTrue(res.skillState.skill_instructions.contains('Body of role-customer-support-agent'));
        Assert.isTrue(res.skillState.skill_menu.contains('- skill-troubleshooting-support: Use for device problems.'));
    }

    @IsTest
    static void unwiredNamesAreDroppedAndReported() {
        Agent_Skill_State.Response res = run(AGENT, 'skill-troubleshooting-support, skill-made-up,skill-troubleshooting-support');

        Assert.areEqual('skill-troubleshooting-support', res.activeSkills);
        Assert.isTrue(res.skillState.skill_warnings.contains('Not wired to this agent: skill-made-up'));
        Assert.isFalse(res.skillState.skill_instructions.contains('Body of skill-product-information-qa'));
    }

    @IsTest
    static void toolFlagsFollowActiveSkills() {
        Assert.isFalse(run(AGENT, '').skillState.tools.containsKey('create_case'));

        Agent_Skill_State.Response res = run(AGENT, 'skill-troubleshooting-support');
        Assert.isTrue(res.skillState.tools.get('create_case'));
    }

    @IsTest
    static void agentToolsValidateToolReferences() {
        Agent_Skill_Binding__c binding = [SELECT Id FROM Agent_Skill_Binding__c LIMIT 1];
        binding.Agent_Tools__c = 'get_order_status, track_shipment';
        update binding;

        Agent_Skill_State.Response res = run(AGENT, 'skill-troubleshooting-support');

        Assert.isFalse(res.skillState.tools.containsKey('create_case'));
        Assert.isTrue(res.skillState.skill_warnings.contains('Unknown tool indicator(s): CreateCase'));
    }

    @IsTest
    static void requireApprovalHidesUnapprovedSkills() {
        Agent_Skill_Binding__c binding = [SELECT Id FROM Agent_Skill_Binding__c LIMIT 1];
        binding.Require_Approval__c = true;
        update binding;

        Agent_Skill_State.Response res = run(AGENT, '');

        Assert.isFalse(res.skillState.skill_instructions.contains('Body of skill-product-information-qa'));
        Assert.isTrue(String.isNotBlank(res.skillState.skill_warnings));
    }

    @IsTest
    static void usageIsLogged() {
        Test.startTest();
        run(AGENT, 'skill-troubleshooting-support');
        Test.stopTest();

        Agent_Skill_Usage_Log__c log = [SELECT Agent_Name__c, Active_Skills__c, Instruction_Chars__c FROM Agent_Skill_Usage_Log__c];
        Assert.areEqual(AGENT, log.Agent_Name__c);
        Assert.areEqual('skill-troubleshooting-support', log.Active_Skills__c);
        Assert.isTrue(log.Instruction_Chars__c > 0);
    }

    @IsTest
    static void inactiveBindingIsIgnored() {
        Agent_Skill_Binding__c binding = [SELECT Id FROM Agent_Skill_Binding__c LIMIT 1];
        binding.Status__c = 'Inactive';
        update binding;

        Agent_Skill_State.Response res = run(AGENT, '');

        Assert.areEqual('', res.activeSkills);
        Assert.isTrue(res.skillState.skill_warnings.contains('No skill wiring found'));
    }

    @IsTest
    static void subagentResolution() {
        Agent_Skill_Binding__c agentLevel = [SELECT Id FROM Agent_Skill_Binding__c LIMIT 1];
        Agent_Skill_Binding__c triage = new Agent_Skill_Binding__c(
            Name = 'PD2 triage', Agent_Developer_Name__c = AGENT, Subagent__c = 'triage', Status__c = 'Active', Locale__c = 'en-US'
        );
        insert triage;
        insert item(triage.Id, 'skill-troubleshooting-support', 'Default', 1);

        Assert.areEqual('skill-troubleshooting-support', run(AGENT, 'Triage', '').activeSkills, 'Exact subagent match, case-insensitive');
        Assert.areEqual('skill-product-information-qa', run(AGENT, 'billing', '').activeSkills, 'Falls back to the agent-level binding');
        Assert.areEqual('skill-product-information-qa', run(AGENT, '').activeSkills, 'No subagent uses the agent-level binding');

        agentLevel.Subagent__c = 'skill_host';
        update agentLevel;
        Agent_Skill_State.Response missing = run(AGENT, 'billing', '');
        Assert.areEqual('', missing.activeSkills);
        Assert.isTrue(missing.skillState.skill_warnings.contains('(subagent billing)'));
        Assert.areEqual('', run(AGENT, '').activeSkills, 'Two subagent bindings and no subagent requested is ambiguous');

        delete triage;
        Assert.areEqual('skill-product-information-qa', run(AGENT, '').activeSkills, 'A single binding answers when no subagent is requested');
    }

    @IsTest
    static void bindingKeyIsUniquePerSubagent() {
        Agent_Skill_Binding__c dup = new Agent_Skill_Binding__c(Name = 'Dup', Agent_Developer_Name__c = AGENT.toUpperCase(), Status__c = 'Active');
        Database.SaveResult sr = Database.insert(dup, false);
        Assert.isFalse(sr.isSuccess(), 'Same agent with a blank subagent is a duplicate');
        Assert.areEqual(AGENT + ':', [SELECT Binding_Key__c FROM Agent_Skill_Binding__c LIMIT 1].Binding_Key__c);
    }

    @IsTest
    static void unknownAgentReturnsEmptyStateWithWarning() {
        Agent_Skill_State.Response res = run('no_such_agent', 'skill-troubleshooting-support');

        Assert.areEqual('', res.activeSkills);
        Assert.areEqual('', res.skillState.skill_instructions);
        Assert.isTrue(res.skillState.skill_warnings.contains('No skill wiring found for agent: no_such_agent'));
    }
}
