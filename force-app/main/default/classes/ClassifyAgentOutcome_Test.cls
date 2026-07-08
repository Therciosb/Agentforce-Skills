@IsTest
private class ClassifyAgentOutcome_Test {

    private static final String AGENT = 'customer_support_skill_demo';
    private static final String TOPIC = 'knowledge';

    private static void seedConfig(String mappingJson, String triggers) {
        insert new AgentSubagentConfig__c(
            agent_api_name__c = AGENT,
            topic_area__c = TOPIC,
            optimal_actions__c = 2,
            outcome_mapping_json__c = mappingJson,
            significant_outcome_triggers__c = triggers
        );
    }

    private static ClassifyAgentOutcome.Request makeReq(String event) {
        ClassifyAgentOutcome.Request r = new ClassifyAgentOutcome.Request();
        r.agent_api_name = AGENT;
        r.topic_area = TOPIC;
        r.domain_event = event;
        return r;
    }

    private static final String STD_MAPPING =
        '[{"domain_event":"resolved","maps_to":"success"},{"domain_event":"unresolved","maps_to":"failure"}]';

    @IsTest
    static void resolvedMapsToSuccess() {
        seedConfig(STD_MAPPING, 'failure;below_optimal');
        Test.startTest();
        List<ClassifyAgentOutcome.Result> out = ClassifyAgentOutcome.classify(
            new List<ClassifyAgentOutcome.Request>{ makeReq('resolved') });
        Test.stopTest();
        Assert.areEqual('success', out[0].outcome_class, 'resolved -> success');
        Assert.isFalse(out[0].is_significant, 'success is not in the significant trigger list');
    }

    @IsTest
    static void unresolvedMapsToFailure_andIsSignificant() {
        seedConfig(STD_MAPPING, 'failure;below_optimal');
        Test.startTest();
        List<ClassifyAgentOutcome.Result> out = ClassifyAgentOutcome.classify(
            new List<ClassifyAgentOutcome.Request>{ makeReq('unresolved') });
        Test.stopTest();
        Assert.areEqual('failure', out[0].outcome_class, 'unresolved -> failure');
        Assert.isTrue(out[0].is_significant, 'failure is in significant_outcome_triggers');
    }

    @IsTest
    static void caseInsensitiveEventMatch() {
        seedConfig(STD_MAPPING, 'failure');
        Test.startTest();
        List<ClassifyAgentOutcome.Result> out = ClassifyAgentOutcome.classify(
            new List<ClassifyAgentOutcome.Request>{ makeReq('RESOLVED') });
        Test.stopTest();
        Assert.areEqual('success', out[0].outcome_class, 'event match is case-insensitive');
    }

    @IsTest
    static void unmappedEventIsUnknown() {
        seedConfig(STD_MAPPING, 'failure');
        Test.startTest();
        List<ClassifyAgentOutcome.Result> out = ClassifyAgentOutcome.classify(
            new List<ClassifyAgentOutcome.Request>{ makeReq('something_else') });
        Test.stopTest();
        Assert.areEqual('unknown', out[0].outcome_class, 'event not in mapping -> unknown');
        Assert.isFalse(out[0].is_significant);
    }

    @IsTest
    static void blankEventIsNeutralEmpty() {
        seedConfig(STD_MAPPING, 'failure');
        Test.startTest();
        List<ClassifyAgentOutcome.Result> out = ClassifyAgentOutcome.classify(
            new List<ClassifyAgentOutcome.Request>{ makeReq('') });
        Test.stopTest();
        Assert.areEqual('', out[0].outcome_class, 'blank event -> neutral empty class (not a failure)');
        Assert.isFalse(out[0].is_significant);
    }

    @IsTest
    static void noConfig_returnsUnknown() {
        // No AgentSubagentConfig__c row at all.
        Test.startTest();
        List<ClassifyAgentOutcome.Result> out = ClassifyAgentOutcome.classify(
            new List<ClassifyAgentOutcome.Request>{ makeReq('resolved') });
        Test.stopTest();
        Assert.areEqual('unknown', out[0].outcome_class, 'no config -> cannot classify -> unknown');
        Assert.isFalse(out[0].is_significant);
    }

    @IsTest
    static void malformedMappingJson_returnsUnknownSafely() {
        seedConfig('{not valid json', 'failure');
        Test.startTest();
        List<ClassifyAgentOutcome.Result> out = ClassifyAgentOutcome.classify(
            new List<ClassifyAgentOutcome.Request>{ makeReq('resolved') });
        Test.stopTest();
        Assert.areEqual('unknown', out[0].outcome_class, 'bad json is swallowed -> unknown, no exception');
    }

    @IsTest
    static void customSubagentMapping_worksGenerically() {
        // A different subagent defines its OWN success/failure events.
        insert new AgentSubagentConfig__c(
            agent_api_name__c = AGENT,
            topic_area__c = 'billing',
            optimal_actions__c = 3,
            outcome_mapping_json__c =
                '[{"domain_event":"case_created","maps_to":"success"},{"domain_event":"blocked","maps_to":"failure"}]',
            significant_outcome_triggers__c = 'failure'
        );
        ClassifyAgentOutcome.Request r = new ClassifyAgentOutcome.Request();
        r.agent_api_name = AGENT; r.topic_area = 'billing'; r.domain_event = 'case_created';
        Test.startTest();
        List<ClassifyAgentOutcome.Result> out = ClassifyAgentOutcome.classify(
            new List<ClassifyAgentOutcome.Request>{ r });
        Test.stopTest();
        Assert.areEqual('success', out[0].outcome_class, 'a different subagent maps its own event names');
    }

    @IsTest
    static void bulk_mixedRequests() {
        seedConfig(STD_MAPPING, 'failure');
        List<ClassifyAgentOutcome.Request> reqs = new List<ClassifyAgentOutcome.Request>();
        for (Integer i = 0; i < 200; i++) {
            reqs.add(makeReq(Math.mod(i, 2) == 0 ? 'resolved' : 'unresolved'));
        }
        Test.startTest();
        List<ClassifyAgentOutcome.Result> out = ClassifyAgentOutcome.classify(reqs);
        Test.stopTest();
        Assert.areEqual(200, out.size(), 'one result per request');
        Assert.areEqual('success', out[0].outcome_class);
        Assert.areEqual('failure', out[1].outcome_class);
    }

    @IsTest
    static void emptyRequestList_returnsEmpty() {
        Test.startTest();
        List<ClassifyAgentOutcome.Result> out =
            ClassifyAgentOutcome.classify(new List<ClassifyAgentOutcome.Request>());
        Test.stopTest();
        Assert.areEqual(0, out.size(), 'no requests -> no results, no query');
    }
}