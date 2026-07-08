@IsTest
private class SiaMetricsControllerTest {

    @TestSetup
    static void setupData() {
        // Create sessions across a 4-week period
        List<AgentSession__c> sessions = new List<AgentSession__c>();
        for (Integer i = 0; i < 8; i++) {
            sessions.add(new AgentSession__c(
                session_id__c = 'METRICS-SESSION-' + i,
                agent_api_name__c = 'MetricsAgent',
                start_time__c = DateTime.now().addDays(-i * 3),
                aes_score__c = 60 + (i * 3),
                lessons_applied__c = (Math.mod(i, 2) == 0) ? 2 : 0,
                primary_topic__c = 'Service'
            ));
        }
        insert sessions;

        // Create lessons
        List<AgentLessonLearned__c> lessons = new List<AgentLessonLearned__c>();
        lessons.add(new AgentLessonLearned__c(
            agent_api_name__c = 'MetricsAgent',
            topic_area__c = 'Service',
            outcome_type__c = 'Success',
            lesson_text__c = 'Promoted lesson',
            confidence_score__c = 0.9,
            is_promoted__c = true,
            is_archived__c = false
        ));
        lessons.add(new AgentLessonLearned__c(
            agent_api_name__c = 'MetricsAgent',
            topic_area__c = 'Service',
            outcome_type__c = 'Success',
            lesson_text__c = 'Active lesson',
            confidence_score__c = 0.5,
            is_promoted__c = false,
            is_archived__c = false
        ));
        insert lessons;

        // Create action outcomes linked to lesson
        AgentActionOutcome__c outcome1 = new AgentActionOutcome__c(
            agent_api_name__c = 'MetricsAgent',
            session_id__c = 'METRICS-SESSION-0',
            action_name__c = 'resolve',
            outcome__c = 'success',
            reward_points__c = 5,
            cumulative_points__c = 5,
            lesson_linked__c = lessons[0].Id,
            lesson_was_helpful__c = true,
            timestamp__c = DateTime.now()
        );
        AgentActionOutcome__c outcome2 = new AgentActionOutcome__c(
            agent_api_name__c = 'MetricsAgent',
            session_id__c = 'METRICS-SESSION-1',
            action_name__c = 'resolve',
            outcome__c = 'failure',
            reward_points__c = -5,
            cumulative_points__c = 0,
            lesson_linked__c = lessons[0].Id,
            lesson_was_helpful__c = false,
            timestamp__c = DateTime.now().addDays(-1)
        );
        insert new List<AgentActionOutcome__c>{ outcome1, outcome2 };
    }

    @IsTest
    static void testGetAgentMetrics() {
        Map<String, Object> metrics = SiaMetricsController.getAgentMetrics('MetricsAgent', 4);
        Assert.isNotNull(metrics.get('aesAvg'));
        Assert.areEqual(8, (Integer) metrics.get('sessionCount'));
        Assert.areEqual(1, (Integer) metrics.get('promotedLessonCount'));
    }

    @IsTest
    static void testGetAgentMetricsInvalidParams() {
        Map<String, Object> metrics = SiaMetricsController.getAgentMetrics('', 4);
        Assert.areEqual(0, metrics.get('sessionCount'));

        metrics = SiaMetricsController.getAgentMetrics('MetricsAgent', 0);
        Assert.areEqual(0, metrics.get('sessionCount'));
    }

    @IsTest
    static void testGetAesTrend() {
        List<Map<String, Object>> trend = SiaMetricsController.getAesTrend('MetricsAgent', 4);
        Assert.isTrue(trend.size() > 0, 'Should have at least one week of data');
        Assert.isNotNull(trend[0].get('week'));
        Assert.isNotNull(trend[0].get('aesAvg'));
    }

    @IsTest
    static void testGetAesTrendEmptyAgent() {
        List<Map<String, Object>> trend = SiaMetricsController.getAesTrend('', 4);
        Assert.areEqual(0, trend.size());
    }

    @IsTest
    static void testGetKnowledgeHealth() {
        Map<String, Decimal> health = SiaMetricsController.getKnowledgeHealth('MetricsAgent');
        Assert.isNotNull(health.get('yield'));
        Assert.isNotNull(health.get('utilization'));
        Assert.isNotNull(health.get('accuracy'));
        // yield = 1 promoted / 2 total = 50% (controller returns a percentage)
        Assert.areEqual(50.0, health.get('yield'));
        // accuracy = 1 helpful / 2 total with lesson = 50% (controller returns a percentage)
        Assert.areEqual(50.0, health.get('accuracy'));
    }

    @IsTest
    static void testGetKnowledgeHealthBlankAgent() {
        Map<String, Decimal> health = SiaMetricsController.getKnowledgeHealth('');
        Assert.areEqual((Decimal) 0, health.get('yield'));
    }

    @IsTest
    static void testGetAgentSummaries() {
        List<Map<String, Object>> summaries = SiaMetricsController.getAgentSummaries(
            new List<String>{ 'MetricsAgent' }
        );
        Assert.areEqual(1, summaries.size());
        Assert.areEqual('MetricsAgent', summaries[0].get('agentApiName'));
    }

    @IsTest
    static void testGetAgentSummariesEmpty() {
        List<Map<String, Object>> summaries = SiaMetricsController.getAgentSummaries(null);
        Assert.areEqual(0, summaries.size());
    }

    @IsTest
    static void testGetAesTrends() {
        Map<String, List<Map<String, Object>>> trends = SiaMetricsController.getAesTrends(
            new List<String>{ 'MetricsAgent' }, 4
        );
        Assert.isTrue(trends.containsKey('MetricsAgent'));
        Assert.isTrue(trends.get('MetricsAgent').size() > 0);
    }
}