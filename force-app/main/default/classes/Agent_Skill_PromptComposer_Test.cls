@IsTest
private class Agent_Skill_PromptComposer_Test {
    @TestSetup
    static void setupData() {
        insert new Agent_Skills_Repo__c(
            Name = 'role-customer-support-agent',
            Type__c = 'Role',
            ExternalId__c = 'role-customer-support-agent:v1:en-US',
            Description__c = 'Customer support role',
            WhenToUse__c = 'Use for customer support sessions.',
            InstructionBody__c = 'Be empathetic, concise, and accurate.',
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
            InstructionBody__c = 'Authenticate users with OTP before account updates.',
            Status__c = 'active',
            Version__c = 'v1',
            Locale__c = 'en-US'
        );

        insert new Agent_Skills_Repo__c(
            Name = 'skill-troubleshooting-support',
            Type__c = 'Skill',
            ExternalId__c = 'skill-troubleshooting-support:v1:en-US',
            Description__c = 'Generic product troubleshooting',
            WhenToUse__c = 'Use for any product troubleshooting.',
            InstructionBody__c = 'Identify product and apply product-specific workflow.',
            References__c = 'workflow-troubleshooting-wifi-modem,workflow-escalate-to-human',
            Status__c = 'active',
            Version__c = 'v1',
            Locale__c = 'en-US'
        );

        insert new Agent_Skills_Repo__c(
            Name = 'workflow-troubleshooting-wifi-modem',
            Type__c = 'Workflow',
            ExternalId__c = 'workflow-troubleshooting-wifi-modem:v1:en-US',
            Description__c = 'Wi-Fi modem troubleshooting',
            WhenToUse__c = 'Use for modem connectivity issues.',
            InstructionBody__c = 'Collect model, lights status, and recent outage context.',
            References__c = 'workflow-escalate-to-human',
            Status__c = 'active',
            Version__c = 'v1',
            Locale__c = 'en-US'
        );

        insert new Agent_Skills_Repo__c(
            Name = 'workflow-escalate-to-human',
            Type__c = 'Workflow',
            ExternalId__c = 'workflow-escalate-to-human:v1:en-US',
            Description__c = 'Escalation workflow',
            WhenToUse__c = 'Use when customer requests human handoff or issue is unresolved.',
            InstructionBody__c = 'Summarize issue, transfer ownership, and confirm ticket ID.',
            Status__c = 'active',
            Version__c = 'v1',
            Locale__c = 'en-US'
        );
    }

    @IsTest
    static void shouldComposeWithReferenceExpansion() {
        Agent_Skill_Loader.LoaderRequest loadReq = new Agent_Skill_Loader.LoaderRequest();
        loadReq.instructionNames = 'role-customer-support-agent,core-skill-user-otp-authentication,skill-troubleshooting-support';
        loadReq.includeReferences = true;
        loadReq.version = 'v1';
        loadReq.locale = 'en-US';

        String bundleJson = Agent_Skill_Loader.load(new List<Agent_Skill_Loader.LoaderRequest>{ loadReq })[0].loadedInstructionBundle;

        Agent_Skill_PromptComposer.ComposerRequest composeReq = new Agent_Skill_PromptComposer.ComposerRequest();
        composeReq.instructionBundle = bundleJson;
        composeReq.requiredNames = 'skill-troubleshooting-support';
        composeReq.includeReferenceExpansion = true;
        composeReq.maxReferenceDepth = 4;
        composeReq.includeDeprecated = false;

        Test.startTest();
        List<Agent_Skill_PromptComposer.ComposerResponse> responses = Agent_Skill_PromptComposer.compose(
            new List<Agent_Skill_PromptComposer.ComposerRequest>{ composeReq }
        );
        Test.stopTest();

        System.assertEquals(1, responses.size());
        String composed = responses[0].composedInstructions;
        System.assert(composed.contains('role-customer-support-agent'));
        System.assert(composed.contains('core-skill-user-otp-authentication'));
        System.assert(composed.contains('skill-troubleshooting-support'));
        System.assert(composed.contains('workflow-troubleshooting-wifi-modem'));
        System.assert(composed.contains('workflow-escalate-to-human'));
        System.assertEquals('', responses[0].missingNames, 'All required items should resolve');
    }
}
