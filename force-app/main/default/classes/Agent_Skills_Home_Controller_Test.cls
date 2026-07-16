@IsTest
private class Agent_Skills_Home_Controller_Test {
    @TestSetup
    static void setup() {
        insert new List<Agent_Skills_Repo__c>{
            new Agent_Skills_Repo__c(Name='role-support', Type__c='Role',
                ExternalId__c='role-support:v1:en-US', WhenToUse__c='Use always.',
                InstructionBody__c='b', Status__c='active', Version__c='v1', Locale__c='en-US'),
            new Agent_Skills_Repo__c(Name='skill-alpha', Type__c='Skill',
                ExternalId__c='skill-alpha:v1:en-US', WhenToUse__c='Use for alpha.',
                InstructionBody__c='b', Status__c='active', Version__c='v1', Locale__c='en-US'),
            new Agent_Skills_Repo__c(Name='skill-beta', Type__c='Skill',
                ExternalId__c='skill-beta:v1:en-US', WhenToUse__c='Use for beta.',
                InstructionBody__c='b', Status__c='Draft', Version__c='v1', Locale__c='en-US'),
            new Agent_Skills_Repo__c(Name='workflow-x', Type__c='Workflow',
                ExternalId__c='workflow-x:v1:en-US', WhenToUse__c='Use for x.',
                InstructionBody__c='b', Status__c='active', Version__c='v1', Locale__c='en-US')
        };
    }

    @IsTest
    static void summarizesCountsAndRecent() {
        Test.startTest();
        Agent_Skills_Home_Controller.HomeSummary s = Agent_Skills_Home_Controller.getSummary();
        Test.stopTest();

        System.assertEquals(4, s.total, 'total count');
        System.assertEquals(3, s.activeTotal, '3 active');
        System.assertEquals(1, s.draftTotal, '1 draft');
        System.assertEquals(4, s.byType.size(), 'four taxonomy buckets always present');

        Map<String, Agent_Skills_Home_Controller.TypeStat> byType =
            new Map<String, Agent_Skills_Home_Controller.TypeStat>();
        for (Agent_Skills_Home_Controller.TypeStat t : s.byType) {
            byType.put(t.type, t);
        }
        System.assertEquals(2, byType.get('Skill').total, 'two skills');
        System.assertEquals(1, byType.get('Skill').active, 'one active skill');
        System.assertEquals(0, byType.get('Core_Skill').total, 'zero core skills still present as a bucket');
        // taxonomy order preserved
        System.assertEquals('Role', s.byType[0].type);
        System.assertEquals('Workflow', s.byType[3].type);

        System.assert(!s.recent.isEmpty(), 'recent populated');
        System.assert(s.recent.size() <= 6, 'recent capped at 6');
        System.assertNotEquals(null, s.recent[0].recordId);
    }

    @IsTest
    static void handlesEmptyRepo() {
        delete [SELECT Id FROM Agent_Skills_Repo__c];
        Test.startTest();
        Agent_Skills_Home_Controller.HomeSummary s = Agent_Skills_Home_Controller.getSummary();
        Test.stopTest();
        System.assertEquals(0, s.total);
        System.assertEquals(4, s.byType.size(), 'buckets always present even when empty');
        System.assert(s.recent.isEmpty());
    }
}
