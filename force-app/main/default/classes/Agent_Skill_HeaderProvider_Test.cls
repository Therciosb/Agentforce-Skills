@IsTest
private class Agent_Skill_HeaderProvider_Test {
    @TestSetup
    static void setupData() {
        insert new List<Agent_Skills_Repo__c>{
            new Agent_Skills_Repo__c(
                Name = 'skill-product-information-qa',
                Type__c = 'Skill',
                ExternalId__c = 'skill-product-information-qa:v1:en-US',
                WhenToUse__c = 'Use when user asks about product features or comparisons.',
                InstructionBody__c = 'Body A',
                Status__c = 'active',
                Version__c = 'v1',
                Locale__c = 'en-US'
            ),
            new Agent_Skills_Repo__c(
                Name = 'skill-troubleshooting-support',
                Type__c = 'Skill',
                ExternalId__c = 'skill-troubleshooting-support:v1:en-US',
                WhenToUse__c = 'Use for any product troubleshooting need.',
                InstructionBody__c = 'Body B',
                Status__c = 'active',
                Version__c = 'v1',
                Locale__c = 'en-US'
            ),
            new Agent_Skills_Repo__c(
                Name = 'skill-blank-header',
                Type__c = 'Skill',
                ExternalId__c = 'skill-blank-header:v1:en-US',
                WhenToUse__c = '',
                InstructionBody__c = 'Body C',
                Status__c = 'active',
                Version__c = 'v1',
                Locale__c = 'en-US'
            ),
            new Agent_Skills_Repo__c(
                Name = 'skill-inactive',
                Type__c = 'Skill',
                ExternalId__c = 'skill-inactive:v1:en-US',
                WhenToUse__c = 'Use for inactive scenario.',
                InstructionBody__c = 'Body D',
                Status__c = 'deprecated',
                Version__c = 'v1',
                Locale__c = 'en-US'
            )
        };
    }

    @IsTest
    static void shouldReturnHeadersForActiveSkills() {
        Agent_Skill_HeaderProvider.HeaderRequest req = new Agent_Skill_HeaderProvider.HeaderRequest();
        req.skillNames = 'skill-product-information-qa,skill-troubleshooting-support';

        Test.startTest();
        List<Agent_Skill_HeaderProvider.HeaderResponse> res =
            Agent_Skill_HeaderProvider.getHeaders(
                new List<Agent_Skill_HeaderProvider.HeaderRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size());
        Agent_Skill_HeaderProvider.HeaderResponse r = res[0];
        System.assertEquals(2, r.headersFound, 'Both active skills should be returned');
        System.assert(
            r.skillHeaders.contains('- skill-product-information-qa: Use when user asks about product features or comparisons.'),
            'Header line for product skill expected: ' + r.skillHeaders);
        System.assert(
            r.skillHeaders.contains('- skill-troubleshooting-support: Use for any product troubleshooting need.'),
            'Header line for troubleshooting skill expected');
        System.assertEquals('', r.missingNames, 'No missing names expected');
        System.assertEquals('', r.warnings, 'No warnings expected');
    }

    @IsTest
    static void shouldExcludeBlankHeaderWithNoFallback() {
        Agent_Skill_HeaderProvider.HeaderRequest req = new Agent_Skill_HeaderProvider.HeaderRequest();
        req.skillNames = 'skill-product-information-qa,skill-blank-header';

        Test.startTest();
        Agent_Skill_HeaderProvider.HeaderResponse r =
            Agent_Skill_HeaderProvider.getHeaders(
                new List<Agent_Skill_HeaderProvider.HeaderRequest>{ req })[0];
        Test.stopTest();

        System.assertEquals(1, r.headersFound, 'Blank WhenToUse__c must be excluded');
        System.assertEquals('skill-blank-header', r.missingNames,
            'Blank-header skill reported as missing (no fallback)');
        System.assert(String.isNotBlank(r.warnings), 'A warning must be present for the excluded skill');
        System.assert(!r.skillHeaders.contains('skill-blank-header'),
            'Excluded skill must not appear in headers');
    }

    @IsTest
    static void shouldReportInactiveAndUnknownAsMissing() {
        Agent_Skill_HeaderProvider.HeaderRequest req = new Agent_Skill_HeaderProvider.HeaderRequest();
        req.skillNames = 'skill-inactive,skill-does-not-exist';

        Test.startTest();
        Agent_Skill_HeaderProvider.HeaderResponse r =
            Agent_Skill_HeaderProvider.getHeaders(
                new List<Agent_Skill_HeaderProvider.HeaderRequest>{ req })[0];
        Test.stopTest();

        System.assertEquals(0, r.headersFound);
        System.assert(r.missingNames.contains('skill-inactive'));
        System.assert(r.missingNames.contains('skill-does-not-exist'));
    }

    @IsTest
    static void shouldHandleEmptyInput() {
        Agent_Skill_HeaderProvider.HeaderRequest req = new Agent_Skill_HeaderProvider.HeaderRequest();
        req.skillNames = '';

        Test.startTest();
        Agent_Skill_HeaderProvider.HeaderResponse r =
            Agent_Skill_HeaderProvider.getHeaders(
                new List<Agent_Skill_HeaderProvider.HeaderRequest>{ req })[0];
        Test.stopTest();

        System.assertEquals(0, r.headersFound);
        System.assertEquals('', r.skillHeaders);
    }

    @IsTest
    static void shouldFilterByLocale() {
        Agent_Skill_HeaderProvider.HeaderRequest req = new Agent_Skill_HeaderProvider.HeaderRequest();
        req.skillNames = 'skill-product-information-qa';
        req.locale = 'fr-FR';

        Test.startTest();
        Agent_Skill_HeaderProvider.HeaderResponse r =
            Agent_Skill_HeaderProvider.getHeaders(
                new List<Agent_Skill_HeaderProvider.HeaderRequest>{ req })[0];
        Test.stopTest();

        System.assertEquals(0, r.headersFound, 'No en-US record should match fr-FR');
        System.assertEquals('skill-product-information-qa', r.missingNames);
    }
}
