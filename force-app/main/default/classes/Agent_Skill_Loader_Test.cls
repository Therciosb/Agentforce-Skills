@IsTest
private class Agent_Skill_Loader_Test {
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
            Name = 'skill-legacy-deprecated',
            Type__c = 'Skill',
            ExternalId__c = 'skill-legacy-deprecated:v1:en-US',
            Description__c = 'Legacy skill',
            WhenToUse__c = 'Never for active sessions.',
            InstructionBody__c = 'Deprecated legacy skill.',
            Status__c = 'deprecated',
            Version__c = 'v1',
            Locale__c = 'en-US'
        );
    }

    @IsTest
    static void shouldLoadOnlyActiveInstructions() {
        Agent_Skill_Loader.LoaderRequest req = new Agent_Skill_Loader.LoaderRequest();
        req.instructionNames = 'role-customer-support-agent,core-skill-user-otp-authentication,skill-legacy-deprecated';
        req.includeReferences = false;
        req.version = 'v1';
        req.locale = 'en-US';

        Test.startTest();
        List<Agent_Skill_Loader.LoaderResponse> res = Agent_Skill_Loader.load(
            new List<Agent_Skill_Loader.LoaderRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, res.size(), 'One response expected');
        System.assertEquals(2, res[0].skillsLoadedCount, 'Deprecated skill should be filtered out');
        System.assert(res[0].loadedInstructionBundle.contains('role-customer-support-agent'));
        System.assert(res[0].loadedInstructionBundle.contains('core-skill-user-otp-authentication'));
        System.assert(!res[0].loadedInstructionBundle.contains('skill-legacy-deprecated'));
        System.assert(res[0].missingNames.contains('skill-legacy-deprecated'));
    }

    @IsTest
    static void shouldMergeTopicSkillsWithExistingBundle() {
        Agent_Skill_Loader.LoaderRequest baseReq = new Agent_Skill_Loader.LoaderRequest();
        baseReq.instructionNames = 'role-customer-support-agent,core-skill-user-otp-authentication';
        baseReq.includeReferences = false;
        baseReq.version = 'v1';
        baseReq.locale = 'en-US';

        List<Agent_Skill_Loader.LoaderResponse> baseRes = Agent_Skill_Loader.load(
            new List<Agent_Skill_Loader.LoaderRequest>{ baseReq }
        );
        String existingBundle = baseRes[0].loadedInstructionBundle;

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

        Agent_Skill_Loader.LoaderRequest mergeReq = new Agent_Skill_Loader.LoaderRequest();
        mergeReq.instructionNames = 'skill-product-information-qa';
        mergeReq.existingInstructionBundle = existingBundle;
        mergeReq.includeReferences = false;
        mergeReq.version = 'v1';
        mergeReq.locale = 'en-US';

        Test.startTest();
        List<Agent_Skill_Loader.LoaderResponse> mergeRes = Agent_Skill_Loader.load(
            new List<Agent_Skill_Loader.LoaderRequest>{ mergeReq }
        );
        Test.stopTest();

        System.assertEquals(1, mergeRes.size());
        System.assertEquals(3, mergeRes[0].skillsLoadedCount, 'Should have role + core + topic skill');
        System.assert(mergeRes[0].loadedInstructionBundle.contains('role-customer-support-agent'));
        System.assert(mergeRes[0].loadedInstructionBundle.contains('core-skill-user-otp-authentication'));
        System.assert(mergeRes[0].loadedInstructionBundle.contains('skill-product-information-qa'));
    }
}
