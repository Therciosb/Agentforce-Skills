@IsTest
private class Agent_Skill_Test_Runner_Test {
    private static final String AGENT = 'runner_test_agent';

    @TestSetup
    static void setup() {
        List<Agent_Skills_Repo__c> repo = new List<Agent_Skills_Repo__c>();
        for (String name : new List<String>{ 'role-runner', 'skill-faq', 'skill-orders' }) {
            repo.add(new Agent_Skills_Repo__c(
                Name = name,
                Type__c = name.startsWith('role-') ? 'Role' : 'Skill',
                Status__c = 'active',
                Version__c = 'v1',
                Locale__c = 'en-US',
                ExternalId__c = name + ':v1:en-US',
                WhenToUse__c = 'Use for ' + name,
                InstructionBody__c = name == 'skill-orders' ? 'Look up orders with [[tool:GetOrderStatus]].' : 'Body of ' + name
            ));
        }
        insert repo;

        Agent_Skill_Binding__c binding = new Agent_Skill_Binding__c(Name = 'Runner', Agent_Developer_Name__c = AGENT, Status__c = 'Active', Locale__c = 'en-US');
        insert binding;
        insert new List<Agent_Skill_Binding_Item__c>{
            new Agent_Skill_Binding_Item__c(Binding__c = binding.Id, Skill_Name__c = 'role-runner', Mode__c = 'Always', Order__c = 1),
            new Agent_Skill_Binding_Item__c(Binding__c = binding.Id, Skill_Name__c = 'skill-faq', Mode__c = 'Default', Order__c = 2),
            new Agent_Skill_Binding_Item__c(Binding__c = binding.Id, Skill_Name__c = 'skill-orders', Mode__c = 'Selectable', Order__c = 3)
        };

        insert new Agent_Skill_Test_Case__c(
            Name = 'Order lookup',
            Agent_Developer_Name__c = AGENT,
            Utterance__c = 'Where is my "order" 123?',
            Expected_Skills__c = 'skill-orders',
            Expected_Tools__c = 'get_order_status',
            Expected_Outcome__c = 'Agent reports the order status.'
        );
    }

    private static User author() {
        User u = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            LastName = 'Tester',
            Email = 'tester@agentskills.test',
            Username = 'tester' + Datetime.now().getTime() + '@agentskills.test',
            Alias = 'asktest',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;
        insert new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Agent_Skills_Author' LIMIT 1].Id
        );
        return u;
    }

    private static Agent_Skill_Test_Runner.CaseResult runAsAuthor(String route, String runId) {
        Agent_Skill_Test_Runner.routeOverride = route;
        Id caseId = testCase().Id;
        Agent_Skill_Test_Runner.CaseResult r;
        System.runAs(author()) {
            r = Agent_Skill_Test_Runner.runCase(caseId, runId);
        }
        return r;
    }

    private static Agent_Skill_Test_Case__c testCase() {
        return [SELECT Id FROM Agent_Skill_Test_Case__c LIMIT 1];
    }

    @IsTest
    static void passingRouteRecordsResult() {
        Agent_Skill_Test_Runner.CaseResult r = runAsAuthor('{"skills": ["skill-orders"], "reason": "Order question."}', 'run-1');

        Assert.isTrue(r.passed, String.valueOf(r));
        Assert.areEqual('skill-orders', r.selectedSkills);
        Assert.isTrue(r.enabledTools.contains('get_order_status'));
        Agent_Skill_Test_Result__c rec = [SELECT Passed__c, Run_Id__c, Reason__c FROM Agent_Skill_Test_Result__c];
        Assert.isTrue(rec.Passed__c);
        Assert.areEqual('run-1', rec.Run_Id__c);
        Assert.areEqual('Pass', [SELECT Last_Status__c FROM Agent_Skill_Test_Case__c].Last_Status__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Agent_Skill_Usage_Log__c], 'Test runs must not log usage');
    }

    @IsTest
    static void wrongRouteFailsWithMissingTools() {
        Agent_Skill_Test_Runner.CaseResult r = runAsAuthor('Sure! {"skills": ["skill-faq"], "reason": "General question."}', 'run-2');

        Assert.isFalse(r.passed);
        Assert.areEqual('skill-faq', r.selectedSkills);
        Assert.areEqual('get_order_status', r.missingTools);
    }

    @IsTest
    static void unparseableRouteFails() {
        Agent_Skill_Test_Runner.CaseResult r = runAsAuthor('no json here', 'run-3');

        Assert.isFalse(r.passed);
        Assert.isTrue(r.warnings.contains('not JSON'));
    }

    @IsTest
    static void exportsTestingCenterSpec() {
        String yaml;
        Integer caseCount;
        System.runAs(author()) {
            yaml = Agent_Skill_Test_Runner.exportTestSpec(AGENT);
            caseCount = Agent_Skill_Test_Runner.listCases(AGENT).size();
        }

        Assert.isTrue(yaml.contains('subjectName: ' + AGENT));
        Assert.isTrue(yaml.contains('utterance: "Where is my \\"order\\" 123?"'), yaml);
        Assert.isTrue(yaml.contains('expectedTopic: skill_host'));
        Assert.isTrue(yaml.contains('      - get_order_status'));
        Assert.isTrue(yaml.contains('expectedOutcome: "Agent reports the order status."'), yaml);
        Assert.areEqual(1, caseCount);
    }
}
