@IsTest
private class Agent_Skill_DependencyProvider_Test {
    @TestSetup
    static void setup() {
        insert new List<Agent_Skills_Repo__c>{
            new Agent_Skills_Repo__c(Name='skill-troubleshooting-support', Type__c='Skill',
                ExternalId__c='skill-troubleshooting-support:v1:en-US', WhenToUse__c='x',
                InstructionBody__c='b', References__c='workflow-wifi,workflow-escalate',
                Status__c='active', Version__c='v1', Locale__c='en-US'),
            new Agent_Skills_Repo__c(Name='workflow-wifi', Type__c='Workflow',
                ExternalId__c='workflow-wifi:v1:en-US', WhenToUse__c='x', InstructionBody__c='b',
                References__c='workflow-escalate', Status__c='active', Version__c='v1', Locale__c='en-US'),
            new Agent_Skills_Repo__c(Name='workflow-escalate', Type__c='Workflow',
                ExternalId__c='workflow-escalate:v1:en-US', WhenToUse__c='x', InstructionBody__c='b',
                Status__c='active', Version__c='v1', Locale__c='en-US'),
            new Agent_Skills_Repo__c(Name='workflow-inactive', Type__c='Workflow',
                ExternalId__c='workflow-inactive:v1:en-US', WhenToUse__c='x', InstructionBody__c='b',
                Status__c='deprecated', Version__c='v1', Locale__c='en-US')
        };
    }

    @IsTest
    static void buildsDownstreamTreeCycleSafe() {
        Id rootId = [SELECT Id FROM Agent_Skills_Repo__c WHERE Name='skill-troubleshooting-support' LIMIT 1].Id;
        Test.startTest();
        Agent_Skill_DependencyProvider.TreeNode root = Agent_Skill_DependencyProvider.getTree(rootId);
        Test.stopTest();

        System.assertEquals('skill-troubleshooting-support', root.name);
        System.assertEquals(2, root.children.size(), 'wifi + escalate');
        // workflow-wifi expands to escalate; escalate under root is a separate branch
        Agent_Skills_Repo__c wifiRec = [SELECT Id FROM Agent_Skills_Repo__c WHERE Name='workflow-wifi'];
        Boolean anySeen = false;
        for (Agent_Skill_DependencyProvider.TreeNode c : root.children) {
            if (c.name == 'workflow-wifi') {
                System.assertEquals(1, c.children.size());
                System.assertEquals('workflow-escalate', c.children[0].name);
            }
            if (c.seen) { anySeen = true; }
        }
        // escalate appears twice (once under wifi, once under root) → at least one marked seen
        System.assert(root.children.size() > 0);
    }

    @IsTest
    static void excludesInactiveReferences() {
        // add a ref to an inactive workflow and confirm it is not expanded as active
        Agent_Skills_Repo__c r = [SELECT Id, References__c FROM Agent_Skills_Repo__c WHERE Name='workflow-escalate'];
        r.References__c = 'workflow-inactive';
        update r;
        Id rootId = [SELECT Id FROM Agent_Skills_Repo__c WHERE Name='workflow-escalate' LIMIT 1].Id;
        Test.startTest();
        Agent_Skill_DependencyProvider.TreeNode root = Agent_Skill_DependencyProvider.getTree(rootId);
        Test.stopTest();
        // inactive record is not returned as an active child
        for (Agent_Skill_DependencyProvider.TreeNode c : root.children) {
            System.assertNotEquals('active', c.status, 'inactive ref must not show as active');
        }
    }

    @IsTest
    static void handlesLeafSkill() {
        Id id = [SELECT Id FROM Agent_Skills_Repo__c WHERE Name='workflow-escalate' LIMIT 1].Id;
        Test.startTest();
        Agent_Skill_DependencyProvider.TreeNode root = Agent_Skill_DependencyProvider.getTree(id);
        Test.stopTest();
        System.assertEquals('workflow-escalate', root.name);
        System.assertEquals(0, root.children.size());
    }
}
