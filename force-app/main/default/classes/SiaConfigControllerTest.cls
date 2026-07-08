@IsTest
private class SiaConfigControllerTest {

    @TestSetup
    static void setupData() {
        AgentSession__c session = new AgentSession__c(
            session_id__c = 'TEST-SESSION-001',
            agent_api_name__c = 'TestAgent',
            start_time__c = DateTime.now().addDays(-1),
            aes_score__c = 75
        );
        insert session;

        AgentRewardConfig__c rewardConfig = new AgentRewardConfig__c(
            agent_api_name__c = 'TestAgent',
            action_name__c = 'resolve_case',
            topic_area__c = 'Service',
            points__c = 10,
            is_active__c = true
        );
        insert rewardConfig;

        AgentSubagentConfig__c subConfig = new AgentSubagentConfig__c(
            agent_api_name__c = 'TestAgent',
            topic_area__c = 'Service',
            optimal_actions__c = 3
        );
        insert subConfig;

        AgentImprovementConfig__c impConfig = new AgentImprovementConfig__c(
            agent_api_name__c = 'TestAgent',
            promotion_confidence__c = 0.8,
            promotion_references__c = 5,
            max_lessons_per_topic__c = 20
        );
        insert impConfig;
    }

    @IsTest
    static void testGetRewardConfigs() {
        List<AgentRewardConfig__c> configs = SiaConfigController.getRewardConfigs('TestAgent');
        Assert.isTrue(configs.size() >= 1, 'Should return at least one reward config');
        Assert.areEqual('resolve_case', configs[0].action_name__c);
    }

    @IsTest
    static void testGetRewardConfigsBlankAgent() {
        List<AgentRewardConfig__c> configs = SiaConfigController.getRewardConfigs('');
        Assert.areEqual(0, configs.size(), 'Blank agent should return empty list');
    }

    @IsTest
    static void testUpsertRewardConfigs() {
        AgentRewardConfig__c newConfig = new AgentRewardConfig__c(
            agent_api_name__c = 'TestAgent',
            action_name__c = 'escalate',
            points__c = -5,
            is_active__c = true
        );
        SiaConfigController.upsertRewardConfigs(new List<AgentRewardConfig__c>{ newConfig });
        List<AgentRewardConfig__c> configs = [SELECT Id FROM AgentRewardConfig__c WHERE action_name__c = 'escalate'];
        Assert.areEqual(1, configs.size());
    }

    @IsTest
    static void testUpsertRewardConfigsNull() {
        // Should not throw
        SiaConfigController.upsertRewardConfigs(null);
        SiaConfigController.upsertRewardConfigs(new List<AgentRewardConfig__c>());
    }

    @IsTest
    static void testGetSubagentConfigs() {
        List<AgentSubagentConfig__c> configs = SiaConfigController.getSubagentConfigs('TestAgent');
        Assert.areEqual(1, configs.size());
        Assert.areEqual('Service', configs[0].topic_area__c);
    }

    @IsTest
    static void testUpsertSubagentConfig() {
        AgentSubagentConfig__c config = new AgentSubagentConfig__c(
            agent_api_name__c = 'TestAgent',
            topic_area__c = 'Sales',
            optimal_actions__c = 5
        );
        SiaConfigController.upsertSubagentConfig(config);
        List<AgentSubagentConfig__c> configs = [SELECT Id FROM AgentSubagentConfig__c WHERE topic_area__c = 'Sales'];
        Assert.areEqual(1, configs.size());
    }

    @IsTest
    static void testGetThresholdConfig() {
        AgentImprovementConfig__c config = SiaConfigController.getThresholdConfig('TestAgent');
        Assert.isNotNull(config);
        Assert.areEqual(0.8, config.promotion_confidence__c);
    }

    @IsTest
    static void testGetThresholdConfigNotFound() {
        AgentImprovementConfig__c config = SiaConfigController.getThresholdConfig('NonExistentAgent');
        Assert.areEqual(null, config);
    }

    @IsTest
    static void testUpsertThresholdConfig() {
        AgentImprovementConfig__c config = new AgentImprovementConfig__c(
            agent_api_name__c = 'NewAgent',
            promotion_confidence__c = 0.9
        );
        SiaConfigController.upsertThresholdConfig(config);
        AgentImprovementConfig__c result = SiaConfigController.getThresholdConfig('NewAgent');
        Assert.isNotNull(result);
    }

    @IsTest
    static void testGetRegisteredAgents() {
        List<String> agents = SiaConfigController.getRegisteredAgents();
        Assert.isTrue(agents.contains('TestAgent'), 'Should contain TestAgent');
    }
}