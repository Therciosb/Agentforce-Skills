@IsTest
private class SiaSessionControllerTest {

    @TestSetup
    static void setupData() {
        List<AgentSession__c> sessions = new List<AgentSession__c>();
        sessions.add(new AgentSession__c(
            session_id__c = 'SESS-001',
            agent_api_name__c = 'SessionAgent',
            start_time__c = DateTime.now().addDays(-2),
            final_outcome__c = 'success',
            primary_topic__c = 'Service',
            aes_score__c = 80
        ));
        sessions.add(new AgentSession__c(
            session_id__c = 'SESS-002',
            agent_api_name__c = 'SessionAgent',
            start_time__c = DateTime.now().addDays(-10),
            final_outcome__c = 'failure',
            primary_topic__c = 'Sales',
            aes_score__c = 40
        ));
        sessions.add(new AgentSession__c(
            session_id__c = 'SESS-003',
            agent_api_name__c = 'SessionAgent',
            start_time__c = DateTime.now().addDays(-60),
            final_outcome__c = 'partial',
            primary_topic__c = 'Service',
            aes_score__c = 55
        ));
        insert sessions;

        List<AgentActionOutcome__c> actions = new List<AgentActionOutcome__c>();
        actions.add(new AgentActionOutcome__c(
            agent_api_name__c = 'SessionAgent',
            session_id__c = 'SESS-001',
            action_name__c = 'greet',
            outcome__c = 'success',
            reward_points__c = 5,
            cumulative_points__c = 5,
            timestamp__c = DateTime.now().addDays(-2).addHours(1)
        ));
        actions.add(new AgentActionOutcome__c(
            agent_api_name__c = 'SessionAgent',
            session_id__c = 'SESS-001',
            action_name__c = 'resolve',
            outcome__c = 'success',
            reward_points__c = 10,
            cumulative_points__c = 15,
            timestamp__c = DateTime.now().addDays(-2).addHours(2)
        ));
        insert actions;
    }

    @IsTest
    static void testGetSessionsNoFilters() {
        List<AgentSession__c> sessions = SiaSessionController.getSessions('SessionAgent', null);
        Assert.areEqual(3, sessions.size());
    }

    @IsTest
    static void testGetSessionsWithPeriodFilter() {
        Map<String, String> filters = new Map<String, String>{ 'period' => '7d' };
        List<AgentSession__c> sessions = SiaSessionController.getSessions('SessionAgent', filters);
        Assert.areEqual(1, sessions.size());
        Assert.areEqual('SESS-001', sessions[0].session_id__c);
    }

    @IsTest
    static void testGetSessionsWithOutcomeFilter() {
        Map<String, String> filters = new Map<String, String>{ 'outcome' => 'failure' };
        List<AgentSession__c> sessions = SiaSessionController.getSessions('SessionAgent', filters);
        Assert.areEqual(1, sessions.size());
        Assert.areEqual('SESS-002', sessions[0].session_id__c);
    }

    @IsTest
    static void testGetSessionsWithTopicFilter() {
        Map<String, String> filters = new Map<String, String>{ 'topicArea' => 'Service' };
        List<AgentSession__c> sessions = SiaSessionController.getSessions('SessionAgent', filters);
        Assert.areEqual(2, sessions.size());
    }

    @IsTest
    static void testGetSessionsBlankAgent() {
        List<AgentSession__c> sessions = SiaSessionController.getSessions('', null);
        Assert.areEqual(0, sessions.size());
    }

    @IsTest
    static void testGetSessionActions() {
        List<AgentActionOutcome__c> actions = SiaSessionController.getSessionActions('SESS-001');
        Assert.areEqual(2, actions.size());
        // Should be ordered by timestamp ASC
        Assert.areEqual('greet', actions[0].action_name__c);
        Assert.areEqual('resolve', actions[1].action_name__c);
    }

    @IsTest
    static void testGetSessionActionsBlankId() {
        List<AgentActionOutcome__c> actions = SiaSessionController.getSessionActions('');
        Assert.areEqual(0, actions.size());
    }
}