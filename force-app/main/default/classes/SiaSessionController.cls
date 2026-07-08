public with sharing class SiaSessionController {

    @AuraEnabled
    public static List<AgentSession__c> getSessions(String agentApiName, Map<String, String> filters) {
        if (String.isBlank(agentApiName)) {
            return new List<AgentSession__c>();
        }

        String query = 'SELECT Id, session_id__c, agent_api_name__c, start_time__c, end_time__c, '
            + 'final_outcome__c, final_points__c, actions_taken__c, lessons_applied__c, '
            + 'lessons_created__c, aes_score__c, aes_goal__c, aes_efficiency__c, aes_learning__c, '
            + 'improvement_group__c, primary_topic__c '
            + 'FROM AgentSession__c '
            + 'WHERE agent_api_name__c = :agentApiName';

        if (filters != null) {
            // Period filter
            if (filters.containsKey('period') && String.isNotBlank(filters.get('period'))) {
                String period = filters.get('period');
                Integer days = 30;
                if (period.endsWith('d')) {
                    try {
                        days = Integer.valueOf(period.removeEnd('d'));
                    } catch (Exception e) {
                        days = 30;
                    }
                }
                DateTime startDate = DateTime.now().addDays(-days);
                query += ' AND start_time__c >= :startDate';
            }

            // Outcome filter
            if (filters.containsKey('outcome') && String.isNotBlank(filters.get('outcome'))) {
                String outcome = String.escapeSingleQuotes(filters.get('outcome'));
                query += ' AND final_outcome__c = \'' + outcome + '\'';
            }

            // Topic area filter
            if (filters.containsKey('topicArea') && String.isNotBlank(filters.get('topicArea'))) {
                String topicArea = String.escapeSingleQuotes(filters.get('topicArea'));
                query += ' AND primary_topic__c = \'' + topicArea + '\'';
            }
        }

        query += ' WITH SECURITY_ENFORCED ORDER BY start_time__c DESC LIMIT 100';

        return Database.query(query);
    }

    @AuraEnabled
    public static List<AgentActionOutcome__c> getSessionActions(String sessionId) {
        if (String.isBlank(sessionId)) {
            return new List<AgentActionOutcome__c>();
        }
        return [
            SELECT Id, agent_api_name__c, session_id__c, action_name__c, topic_area__c,
                   outcome__c, reward_points__c, lesson_linked__c, lesson_was_helpful__c,
                   cumulative_points__c, timestamp__c
            FROM AgentActionOutcome__c
            WHERE session_id__c = :sessionId
            WITH SECURITY_ENFORCED
            ORDER BY timestamp__c ASC
        ];
    }
}