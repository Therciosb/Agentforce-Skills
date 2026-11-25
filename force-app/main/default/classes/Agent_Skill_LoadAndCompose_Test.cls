@IsTest
private class Agent_Skill_LoadAndCompose_Test {
    @TestSetup
    static void setupData() {
        insert new Agent_Skills_Repo__c(
            Name = 'role-customer-support-agent',
            Type__c = 'Role',
            ExternalId__c = 'role-customer-support-agent:v1:en-US',
            Description__c = 'Customer support role',
            WhenToUse__c = 'Use for customer support sessions.',
            InstructionBody__c = 'Act as a customer support specialist.',
            Status__c = 'active',
            Version__c = 'v1',
            Locale__c = 'en-US'
        );

        insert new Agent_Skills_Repo__c(
            Name = 'core-skill-user-otp-authentication',
            Type__c = 'Core_Skill',
            ExternalId__c = 'core-skill-user-otp-authentication:v1:en-US',
            Description__c = 'Core authentication skill',
            WhenToUse__c = 'Use before account actions.',
            InstructionBody__c = 'Validate user with OTP before sensitive actions.',
            Status__c = 'active',
            Version__c = 'v1',
            Locale__c = 'en-US'
        );

        insert new Agent_Skills_Repo__c(
            Name = 'skill-product-information-qa',
            Type__c = 'Skill',
            ExternalId__c = 'skill-product-information-qa:v1:en-US',
            Description__c = 'Product Q&A',
            WhenToUse__c = 'Use for product questions.',
            InstructionBody__c = 'Answer product questions accurately.',
            Status__c = 'active',
            Version__c = 'v1',
            Locale__c = 'en-US'
        );

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

    @IsTest
    static void shouldLoadAndComposeWhenBundleLoaded() {
        Agent_Skill_LoadAndCompose.LoadAndComposeRequest req = new Agent_Skill_LoadAndCompose.LoadAndComposeRequest();
        req.instructionNames = 'role-customer-support-agent,core-skill-user-otp-authentication,skill-product-information-qa';

        Test.startTest();
        List<Agent_Skill_LoadAndCompose.LoadAndComposeResponse> res = Agent_Skill_LoadAndCompose.loadAndCompose(
            new List<Agent_Skill_LoadAndCompose.LoadAndComposeRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assert(res[0].composeRan, 'Composer should run when load succeeds');
        System.assertEquals(3, res[0].skillsLoadedCount);
        System.assert(String.isNotBlank(res[0].loadedInstructionBundle), 'Should have raw JSON');
        System.assert(String.isNotBlank(res[0].instructionsBundle), 'Should have formatted prompt');
        System.assert(res[0].instructionsBundle.contains('skill-product-information-qa'));
        System.assert(res[0].instructionsBundle.contains('role-customer-support-agent'));
    }

    @IsTest
    static void shouldNotComposeWhenLoadReturnsEmpty() {
        Agent_Skill_LoadAndCompose.LoadAndComposeRequest req = new Agent_Skill_LoadAndCompose.LoadAndComposeRequest();
        req.instructionNames = 'skill-nonexistent-xyz';

        Test.startTest();
        List<Agent_Skill_LoadAndCompose.LoadAndComposeResponse> res = Agent_Skill_LoadAndCompose.loadAndCompose(
            new List<Agent_Skill_LoadAndCompose.LoadAndComposeRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assert(!res[0].composeRan, 'Composer should not run when load returns empty');
        System.assertEquals(0, res[0].skillsLoadedCount);
        System.assertEquals('', res[0].instructionsBundle);
        System.assert(String.isNotBlank(res[0].warnings), 'Should have load warnings');
    }

    @IsTest
    static void shouldMergeExistingBundleAndCompose() {
        Agent_Skill_Loader.LoaderRequest baseReq = new Agent_Skill_Loader.LoaderRequest();
        baseReq.instructionNames = 'role-customer-support-agent,core-skill-user-otp-authentication';
        baseReq.includeReferences = false;
        String existingBundle = Agent_Skill_Loader.load(new List<Agent_Skill_Loader.LoaderRequest>{ baseReq })[0].loadedInstructionBundle;

        Agent_Skill_LoadAndCompose.LoadAndComposeRequest req = new Agent_Skill_LoadAndCompose.LoadAndComposeRequest();
        req.instructionNames = 'skill-product-information-qa';
        req.existingInstructionBundle = existingBundle;

        Test.startTest();
        List<Agent_Skill_LoadAndCompose.LoadAndComposeResponse> res = Agent_Skill_LoadAndCompose.loadAndCompose(
            new List<Agent_Skill_LoadAndCompose.LoadAndComposeRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assertEquals(3, res[0].skillsLoadedCount);
        System.assert(res[0].instructionsBundle.contains('role-customer-support-agent'));
        System.assert(res[0].instructionsBundle.contains('skill-product-information-qa'));
    }

    private static Agent_Skill_LoadAndCompose.LoadAndComposeResponse run(String names, String locale) {
        Agent_Skill_LoadAndCompose.LoadAndComposeRequest req = new Agent_Skill_LoadAndCompose.LoadAndComposeRequest();
        req.instructionNames = names;
        req.locale = locale;
        return Agent_Skill_LoadAndCompose.loadAndCompose(new List<Agent_Skill_LoadAndCompose.LoadAndComposeRequest>{ req })[0];
    }

    @IsTest
    static void composesSkillWithReferencedWorkflow() {
        Agent_Skill_LoadAndCompose.LoadAndComposeResponse res = run(' skill-alpha , ', null);

        Assert.isTrue(res.composeRan);
        Assert.isTrue(res.instructionsBundle.contains('Alpha body'));
        Assert.isTrue(res.instructionsBundle.contains('Alpha steps'));
    }

    @IsTest
    static void localeSelectsMatchingRecord() {
        Agent_Skill_LoadAndCompose.LoadAndComposeResponse res = run('skill-alpha', 'pt-BR');

        Assert.isTrue(res.instructionsBundle.contains('Corpo alfa'));
        Assert.isFalse(res.instructionsBundle.contains('Alpha body'));
    }

    @IsTest
    static void unknownNamesProduceWarningAndNoCompose() {
        Agent_Skill_LoadAndCompose.LoadAndComposeResponse res = run('skill-missing', null);

        Assert.isFalse(res.composeRan);
        Assert.areEqual('', res.instructionsBundle);
        Assert.isTrue(String.isNotBlank(res.warnings));
    }

    @IsTest
    static void emptyRequestListReturnsEmpty() {
        Assert.areEqual(0, Agent_Skill_LoadAndCompose.loadAndCompose(new List<Agent_Skill_LoadAndCompose.LoadAndComposeRequest>()).size());
    }
}
