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

    @IsTest
    static void shouldRewriteKnownToolIndicatorToPlainCue() {
        insert new Agent_Skills_Repo__c(
            Name = 'skill-tool-cue',
            Type__c = 'Skill',
            ExternalId__c = 'skill-tool-cue:v1:en-US',
            Description__c = 'Tool cue skill',
            WhenToUse__c = 'Use to test tool cue rewriting.',
            InstructionBody__c = 'When the customer approves, create the case with [[tool:CreateCase]].',
            Status__c = 'active',
            Version__c = 'v1',
            Locale__c = 'en-US'
        );

        Agent_Skill_Loader.LoaderRequest loadReq = new Agent_Skill_Loader.LoaderRequest();
        loadReq.instructionNames = 'skill-tool-cue';
        loadReq.includeReferences = false;
        loadReq.version = 'v1';
        loadReq.locale = 'en-US';
        String bundleJson = Agent_Skill_Loader.load(
            new List<Agent_Skill_Loader.LoaderRequest>{ loadReq })[0].loadedInstructionBundle;

        Agent_Skill_PromptComposer.ComposerRequest composeReq = new Agent_Skill_PromptComposer.ComposerRequest();
        composeReq.instructionBundle = bundleJson;
        composeReq.requiredNames = 'skill-tool-cue';
        composeReq.includeReferenceExpansion = false;

        Test.startTest();
        Agent_Skill_PromptComposer.ComposerResponse r = Agent_Skill_PromptComposer.compose(
            new List<Agent_Skill_PromptComposer.ComposerRequest>{ composeReq })[0];
        Test.stopTest();

        System.assert(r.composedInstructions.contains('the "CreateCase" tool'),
            'Indicator should be rewritten to a plain cue: ' + r.composedInstructions);
        System.assert(!r.composedInstructions.contains('[[tool:CreateCase]]'),
            'Raw indicator must not survive in output');
    }

    @IsTest
    static void shouldWarnAndMarkUnknownToolIndicator() {
        insert new Agent_Skills_Repo__c(
            Name = 'skill-bad-tool',
            Type__c = 'Skill',
            ExternalId__c = 'skill-bad-tool:v1:en-US',
            Description__c = 'Bad tool skill',
            WhenToUse__c = 'Use to test unknown tool warnings.',
            InstructionBody__c = 'Escalate with [[tool:Crete_Case]].',
            Status__c = 'active',
            Version__c = 'v1',
            Locale__c = 'en-US'
        );

        Agent_Skill_Loader.LoaderRequest loadReq = new Agent_Skill_Loader.LoaderRequest();
        loadReq.instructionNames = 'skill-bad-tool';
        loadReq.includeReferences = false;
        loadReq.version = 'v1';
        loadReq.locale = 'en-US';
        String bundleJson = Agent_Skill_Loader.load(
            new List<Agent_Skill_Loader.LoaderRequest>{ loadReq })[0].loadedInstructionBundle;

        Agent_Skill_PromptComposer.ComposerRequest composeReq = new Agent_Skill_PromptComposer.ComposerRequest();
        composeReq.instructionBundle = bundleJson;
        composeReq.requiredNames = 'skill-bad-tool';
        composeReq.includeReferenceExpansion = false;

        Test.startTest();
        Agent_Skill_PromptComposer.ComposerResponse r = Agent_Skill_PromptComposer.compose(
            new List<Agent_Skill_PromptComposer.ComposerRequest>{ composeReq })[0];
        Test.stopTest();

        System.assert(r.composedInstructions.contains('[[unknown tool: Crete_Case]]'),
            'Unknown tool should be visibly marked: ' + r.composedInstructions);
        System.assert(r.warnings.contains('Crete_Case'),
            'Unknown tool name should be surfaced in warnings: ' + r.warnings);
    }

    @IsTest
    static void shouldLeaveBodyWithoutIndicatorsUnchanged() {
        insert new Agent_Skills_Repo__c(
            Name = 'skill-no-indicator',
            Type__c = 'Skill',
            ExternalId__c = 'skill-no-indicator:v1:en-US',
            Description__c = 'No indicator skill',
            WhenToUse__c = 'Use to test passthrough.',
            InstructionBody__c = 'Provide a clear, concise answer with no tool reference.',
            Status__c = 'active',
            Version__c = 'v1',
            Locale__c = 'en-US'
        );

        Agent_Skill_Loader.LoaderRequest loadReq = new Agent_Skill_Loader.LoaderRequest();
        loadReq.instructionNames = 'skill-no-indicator';
        loadReq.includeReferences = false;
        loadReq.version = 'v1';
        loadReq.locale = 'en-US';
        String bundleJson = Agent_Skill_Loader.load(
            new List<Agent_Skill_Loader.LoaderRequest>{ loadReq })[0].loadedInstructionBundle;

        Agent_Skill_PromptComposer.ComposerRequest composeReq = new Agent_Skill_PromptComposer.ComposerRequest();
        composeReq.instructionBundle = bundleJson;
        composeReq.requiredNames = 'skill-no-indicator';
        composeReq.includeReferenceExpansion = false;

        Test.startTest();
        Agent_Skill_PromptComposer.ComposerResponse r = Agent_Skill_PromptComposer.compose(
            new List<Agent_Skill_PromptComposer.ComposerRequest>{ composeReq })[0];
        Test.stopTest();

        System.assert(r.composedInstructions.contains('Provide a clear, concise answer with no tool reference.'),
            'Body without indicators must pass through verbatim');
        System.assert(!r.composedInstructions.contains('[[unknown tool:'),
            'No unknown-tool marker should appear');
    }
}
