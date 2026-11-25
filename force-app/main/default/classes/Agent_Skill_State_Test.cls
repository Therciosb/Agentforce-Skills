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
        Agent_Skill_State.Request req = new Agent_Skill_State.Request();
        req.agentName = agentName;
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
    static void inactiveBindingIsIgnored() {
        Agent_Skill_Binding__c binding = [SELECT Id FROM Agent_Skill_Binding__c LIMIT 1];
        binding.Status__c = 'Inactive';
        update binding;

        Agent_Skill_State.Response res = run(AGENT, '');

        Assert.areEqual('', res.activeSkills);
        Assert.isTrue(res.skillState.skill_warnings.contains('No skill wiring found'));
    }

    @IsTest
    static void unknownAgentReturnsEmptyStateWithWarning() {
        Agent_Skill_State.Response res = run('no_such_agent', 'skill-troubleshooting-support');

        Assert.areEqual('', res.activeSkills);
        Assert.areEqual('', res.skillState.skill_instructions);
        Assert.isTrue(res.skillState.skill_warnings.contains('No skill wiring found for agent: no_such_agent'));
    }
}
