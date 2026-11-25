@IsTest
private class Agent_Skill_StateSpike_Test {
    @TestSetup
    static void setup() {
        insert new List<Agent_Skills_Repo__c>{
            skill('role-customer-support-agent', 'Role', 'Use in all sessions.'),
            skill('skill-product-information-qa', 'Skill', 'Use for product questions.'),
            skill('skill-troubleshooting-support', 'Skill', 'Use for device problems.')
        };
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

    private static Agent_Skill_StateSpike.Response run(String requested) {
        Agent_Skill_StateSpike.Request req = new Agent_Skill_StateSpike.Request();
        req.agentName = 'skill_state_spike';
        req.requestedSkills = requested;
        return Agent_Skill_StateSpike.resolve(new List<Agent_Skill_StateSpike.Request>{ req })[0];
    }

    @IsTest
    static void blankRequestLoadsDefaults() {
        Agent_Skill_StateSpike.Response res = run('');

        Assert.areEqual('skill-product-information-qa', res.activeSkills);
        Assert.areEqual(res.activeSkills, res.skillState.active_skills);
        Assert.isTrue(res.skillState.skill_instructions.contains('Body of skill-product-information-qa'));
        Assert.isTrue(res.skillState.skill_instructions.contains('Body of role-customer-support-agent'));
        Assert.isTrue(res.skillState.skill_menu.contains('- skill-troubleshooting-support: Use for device problems.'));
    }

    @IsTest
    static void unwiredNamesAreDroppedAndReported() {
        Agent_Skill_StateSpike.Response res = run('skill-troubleshooting-support, skill-made-up');

        Assert.areEqual('skill-troubleshooting-support', res.activeSkills);
        Assert.isTrue(res.skillState.skill_warnings.contains('Not wired to this agent: skill-made-up'));
        Assert.isFalse(res.skillState.skill_instructions.contains('Body of skill-product-information-qa'));
    }
}
