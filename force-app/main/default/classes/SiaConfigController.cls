public with sharing class SiaConfigController {

    @AuraEnabled
    public static List<AgentRewardConfig__c> getRewardConfigs(String agentApiName) {
        if (String.isBlank(agentApiName)) {
            return new List<AgentRewardConfig__c>();
        }
        return [
            SELECT Id, agent_api_name__c, action_name__c, topic_area__c, points__c, is_active__c
            FROM AgentRewardConfig__c
            WHERE agent_api_name__c = :agentApiName OR agent_api_name__c = NULL
            WITH SECURITY_ENFORCED
        ];
    }

    @AuraEnabled
    public static void upsertRewardConfigs(List<AgentRewardConfig__c> configs) {
        if (configs == null || configs.isEmpty()) {
            return;
        }
        upsert configs;
    }

    @AuraEnabled
    public static List<AgentSubagentConfig__c> getSubagentConfigs(String agentApiName) {
        if (String.isBlank(agentApiName)) {
            return new List<AgentSubagentConfig__c>();
        }
        return [
            SELECT Id, agent_api_name__c, topic_area__c, optimal_actions__c,
                   outcome_mapping_json__c, significant_outcome_triggers__c
            FROM AgentSubagentConfig__c
            WHERE agent_api_name__c = :agentApiName
            WITH SECURITY_ENFORCED
        ];
    }

    @AuraEnabled
    public static void upsertSubagentConfig(AgentSubagentConfig__c config) {
        if (config == null) {
            return;
        }
        upsert config;
    }

    @AuraEnabled
    public static AgentImprovementConfig__c getThresholdConfig(String agentApiName) {
        if (String.isBlank(agentApiName)) {
            return null;
        }
        List<AgentImprovementConfig__c> configs = [
            SELECT Id, agent_api_name__c, promotion_confidence__c, promotion_references__c,
                   demotion_confidence__c, hide_confidence__c, max_lessons_per_topic__c,
                   decay_rate_per_month__c, decay_grace_period_days__c, loop_detection_threshold__c,
                   points_floor__c, ab_mode_enabled__c, ab_treatment_pct__c
            FROM AgentImprovementConfig__c
            WHERE agent_api_name__c = :agentApiName
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return configs.isEmpty() ? null : configs[0];
    }

    @AuraEnabled
    public static void upsertThresholdConfig(AgentImprovementConfig__c config) {
        if (config == null) {
            return;
        }
        upsert config;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getRegisteredAgents() {
        Set<String> agentSet = new Set<String>();
        for (AggregateResult ar : [
            SELECT agent_api_name__c
            FROM AgentImprovementConfig__c
            WITH SECURITY_ENFORCED
            GROUP BY agent_api_name__c
        ]) {
            String name = (String) ar.get('agent_api_name__c');
            if (String.isNotBlank(name)) {
                agentSet.add(name);
            }
        }
        for (AggregateResult ar : [
            SELECT agent_api_name__c
            FROM AgentSubagentConfig__c
            WITH SECURITY_ENFORCED
            GROUP BY agent_api_name__c
        ]) {
            String name = (String) ar.get('agent_api_name__c');
            if (String.isNotBlank(name)) {
                agentSet.add(name);
            }
        }
        for (AggregateResult ar : [
            SELECT agent_api_name__c
            FROM AgentSession__c
            WITH SECURITY_ENFORCED
            GROUP BY agent_api_name__c
        ]) {
            String name = (String) ar.get('agent_api_name__c');
            if (String.isNotBlank(name)) {
                agentSet.add(name);
            }
        }
        List<String> result = new List<String>(agentSet);
        result.sort();
        return result;
    }
}