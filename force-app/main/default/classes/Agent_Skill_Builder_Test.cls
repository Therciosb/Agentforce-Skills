@IsTest
private class Agent_Skill_Builder_Test {
    @TestSetup
    static void seedCatalog() {
        // Referenceable active records so generated references resolve against the catalog.
        insert new List<Agent_Skills_Repo__c>{
            new Agent_Skills_Repo__c(Name='workflow-escalate', Type__c='Workflow',
                ExternalId__c='workflow-escalate:v1:en-US', WhenToUse__c='Use to escalate.',
                InstructionBody__c='b', Status__c='active', Version__c='v1', Locale__c='en-US'),
            new Agent_Skills_Repo__c(Name='core-skill-otp', Type__c='Core_Skill',
                ExternalId__c='core-skill-otp:v1:en-US', WhenToUse__c='Use for OTP.',
                InstructionBody__c='b', Status__c='active', Version__c='v1', Locale__c='en-US')
        };
    }

    @IsTest
    static void createsDraftFromValidJson() {
        Agent_Skill_Builder.rawOverride =
            '{"name":"product qa","type":"Skill","description":"Answer product questions",' +
            '"whenToUse":"Use when the user asks about product specs or pricing.",' +
            '"instructionBody":"# PRODUCT QA\\nAnswer clearly.","references":["workflow-escalate"],"priority":5}';
        Test.startTest();
        Agent_Skill_Builder.BuilderResult res =
            Agent_Skill_Builder.generateSkill('answer product questions', 'Skill', null);
        Test.stopTest();

        System.assert(res.success, 'should succeed: ' + res.warnings);
        Agent_Skills_Repo__c rec = [SELECT Name, Type__c, Status__c, Version__c, Locale__c,
            References__c, WhenToUse__c, ExternalId__c FROM Agent_Skills_Repo__c WHERE Id = :res.recordId];
        System.assert(rec.Name.startsWith('skill-'), 'name gets skill- prefix: ' + rec.Name);
        System.assertEquals('Draft', rec.Status__c);
        System.assertEquals('v1', rec.Version__c);
        System.assertEquals('en-US', rec.Locale__c);
        System.assertEquals('workflow-escalate', rec.References__c, 'no-spaces CSV');
        System.assertEquals(rec.Name + ':v1:en-US', rec.ExternalId__c);
    }

    @IsTest
    static void enforcesPrefixPerType() {
        Agent_Skill_Builder.rawOverride =
            '{"name":"escalate to human","type":"Workflow","description":"d","whenToUse":"w",' +
            '"instructionBody":"b","references":[],"priority":3}';
        Test.startTest();
        Agent_Skill_Builder.BuilderResult res =
            Agent_Skill_Builder.generateSkill('escalate', 'Workflow', null);
        Test.stopTest();
        Agent_Skills_Repo__c rec = [SELECT Name FROM Agent_Skills_Repo__c WHERE Id = :res.recordId];
        System.assert(rec.Name.startsWith('workflow-'), 'workflow prefix enforced: ' + rec.Name);
    }

    @IsTest
    static void normalizesReferencesCsvNoSpaces() {
        Agent_Skill_Builder.rawOverride =
            '{"name":"case mgmt","type":"Skill","description":"d","whenToUse":"w","instructionBody":"b",' +
            '"references":["core-skill-otp"," workflow-escalate ",""],"priority":5}';
        Test.startTest();
        Agent_Skill_Builder.BuilderResult res =
            Agent_Skill_Builder.generateSkill('cases', 'Skill', null);
        Test.stopTest();
        Agent_Skills_Repo__c rec = [SELECT References__c FROM Agent_Skills_Repo__c WHERE Id = :res.recordId];
        System.assertEquals('core-skill-otp,workflow-escalate', rec.References__c);
    }

    @IsTest
    static void dropsUnknownReferencesWithWarning() {
        Agent_Skill_Builder.rawOverride =
            '{"name":"x","type":"Skill","description":"d","whenToUse":"w","instructionBody":"b",' +
            '"references":["workflow-escalate","workflow-does-not-exist"],"priority":5}';
        Test.startTest();
        Agent_Skill_Builder.BuilderResult res =
            Agent_Skill_Builder.generateSkill('x', 'Skill', null);
        Test.stopTest();

        System.assert(res.success);
        Agent_Skills_Repo__c rec = [SELECT References__c FROM Agent_Skills_Repo__c WHERE Id = :res.recordId];
        System.assertEquals('workflow-escalate', rec.References__c, 'unknown ref dropped, valid kept');
        System.assert(res.warnings != null && res.warnings.contains('workflow-does-not-exist'),
            'dropped ref surfaced in warnings: ' + res.warnings);
    }

    @IsTest
    static void malformedJsonReturnsErrorNotException() {
        Agent_Skill_Builder.rawOverride = 'sorry, here is your skill: {not valid json';
        Test.startTest();
        Agent_Skill_Builder.BuilderResult res =
            Agent_Skill_Builder.generateSkill('x', 'Skill', null);
        Test.stopTest();
        System.assertEquals(false, res.success);
        System.assert(String.isNotBlank(res.warnings));
        // No skill was inserted (only the two seeded active catalog records exist; no Draft).
        System.assertEquals(0, [SELECT COUNT() FROM Agent_Skills_Repo__c WHERE Status__c = 'Draft']);
    }

    @IsTest
    static void extractsTextFromContentVersion() {
        ContentVersion cv = new ContentVersion(Title='policy', PathOnClient='policy.md',
            VersionData=Blob.valueOf('# Policy\nEscalate after 3 failed steps.'));
        insert cv;
        Id cvId = [SELECT Id FROM ContentVersion WHERE Title='policy' LIMIT 1].Id;
        Agent_Skill_Builder.rawOverride =
            '{"name":"p","type":"Skill","description":"d","whenToUse":"w","instructionBody":"b","references":[],"priority":5}';
        Test.startTest();
        Agent_Skill_Builder.BuilderResult res =
            Agent_Skill_Builder.generateSkill('policy skill', 'Skill', cvId);
        Test.stopTest();
        System.assert(res.success);
        // referenceText was extracted (no unsupported-file warning)
        System.assert(res.warnings == null || !res.warnings.contains('Unsupported'), res.warnings);
    }
}
