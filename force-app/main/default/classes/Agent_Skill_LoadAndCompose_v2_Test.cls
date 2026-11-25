@IsTest
private class Agent_Skill_LoadAndCompose_v2_Test {
    @TestSetup
    static void setup() {
        insert new List<Agent_Skills_Repo__c>{
            new Agent_Skills_Repo__c(
                Name = 'skill-alpha', Type__c = 'Skill', Status__c = 'active', Version__c = 'v1',
                Locale__c = 'en-US', ExternalId__c = 'skill-alpha:v1:en-US', InstructionBody__c = 'Alpha body',
                References__c = 'workflow-alpha-steps'
            ),
            new Agent_Skills_Repo__c(
                Name = 'workflow-alpha-steps', Type__c = 'Workflow', Status__c = 'active', Version__c = 'v1',
                Locale__c = 'en-US', ExternalId__c = 'workflow-alpha-steps:v1:en-US', InstructionBody__c = 'Alpha steps'
            ),
            new Agent_Skills_Repo__c(
                Name = 'skill-alpha', Type__c = 'Skill', Status__c = 'active', Version__c = 'v1',
                Locale__c = 'pt-BR', ExternalId__c = 'skill-alpha:v1:pt-BR', InstructionBody__c = 'Corpo alfa'
            )
        };
    }

    private static Agent_Skill_LoadAndCompose_v2.LoadAndComposeResponse run(String names, String locale) {
        Agent_Skill_LoadAndCompose_v2.LoadAndComposeRequest req = new Agent_Skill_LoadAndCompose_v2.LoadAndComposeRequest();
        req.instructionNames = names;
        req.locale = locale;
        return Agent_Skill_LoadAndCompose_v2.loadAndCompose(new List<Agent_Skill_LoadAndCompose_v2.LoadAndComposeRequest>{ req })[0];
    }

    @IsTest
    static void composesSkillWithReferencedWorkflow() {
        Agent_Skill_LoadAndCompose_v2.LoadAndComposeResponse res = run(' skill-alpha , ', null);

        Assert.isTrue(res.composeRan);
        Assert.isTrue(res.instructionsBundle.contains('Alpha body'));
        Assert.isTrue(res.instructionsBundle.contains('Alpha steps'));
    }

    @IsTest
    static void localeSelectsMatchingRecord() {
        Agent_Skill_LoadAndCompose_v2.LoadAndComposeResponse res = run('skill-alpha', 'pt-BR');

        Assert.isTrue(res.instructionsBundle.contains('Corpo alfa'));
        Assert.isFalse(res.instructionsBundle.contains('Alpha body'));
    }

    @IsTest
    static void unknownNamesProduceWarningAndNoCompose() {
        Agent_Skill_LoadAndCompose_v2.LoadAndComposeResponse res = run('skill-missing', null);

        Assert.isFalse(res.composeRan);
        Assert.areEqual('', res.instructionsBundle);
        Assert.isTrue(String.isNotBlank(res.warnings));
    }

    @IsTest
    static void emptyRequestListReturnsEmpty() {
        Assert.areEqual(0, Agent_Skill_LoadAndCompose_v2.loadAndCompose(new List<Agent_Skill_LoadAndCompose_v2.LoadAndComposeRequest>()).size());
    }
}
