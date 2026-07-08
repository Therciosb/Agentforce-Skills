public with sharing class SiaKnowledgeController {

    @AuraEnabled
    public static List<AgentLessonLearned__c> getLessons(String agentApiName, String topicArea, String status) {
        if (String.isBlank(agentApiName)) {
            return new List<AgentLessonLearned__c>();
        }

        String query = 'SELECT Id, agent_api_name__c, topic_area__c, action_context__c, '
            + 'lesson_text__c, confidence_score__c, times_referenced__c, times_successful__c, '
            + 'outcome_type__c, is_promoted__c, created_by_session__c, last_validated__c, '
            + 'admin_notes__c, is_archived__c, deprecated_reason__c, last_modified_by_admin__c '
            + 'FROM AgentLessonLearned__c '
            + 'WHERE agent_api_name__c = :agentApiName';

        if (String.isNotBlank(topicArea)) {
            String escapedTopic = String.escapeSingleQuotes(topicArea);
            query += ' AND topic_area__c = \'' + escapedTopic + '\'';
        }

        if (String.isNotBlank(status)) {
            if (status == 'promoted') {
                query += ' AND is_promoted__c = TRUE AND is_archived__c = FALSE';
            } else if (status == 'active') {
                query += ' AND is_promoted__c = FALSE AND confidence_score__c >= 0.30 AND is_archived__c = FALSE';
            } else if (status == 'hidden') {
                query += ' AND confidence_score__c < 0.30 AND is_archived__c = FALSE';
            } else if (status == 'archived') {
                query += ' AND is_archived__c = TRUE';
            }
            // 'all' applies no additional filter
        }

        query += ' WITH SECURITY_ENFORCED ORDER BY confidence_score__c DESC LIMIT 200';

        return Database.query(query);
    }

    @AuraEnabled
    public static AgentLessonLearned__c getLesson(Id lessonId) {
        if (lessonId == null) {
            return null;
        }
        List<AgentLessonLearned__c> lessons = [
            SELECT Id, agent_api_name__c, topic_area__c, action_context__c,
                   lesson_text__c, confidence_score__c, times_referenced__c, times_successful__c,
                   outcome_type__c, is_promoted__c, created_by_session__c, last_validated__c,
                   admin_notes__c, is_archived__c, deprecated_reason__c, last_modified_by_admin__c, categories__c
            FROM AgentLessonLearned__c
            WHERE Id = :lessonId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return lessons.isEmpty() ? null : lessons[0];
    }

    @AuraEnabled
    public static void updateLessonText(Id lessonId, String newText) {
        if (lessonId == null) {
            return;
        }
        AgentLessonLearned__c lesson = new AgentLessonLearned__c(
            Id = lessonId,
            lesson_text__c = newText,
            last_modified_by_admin__c = Datetime.now()
        );
        update lesson;
    }

    @AuraEnabled
    public static void updateAdminNotes(Id lessonId, String newNotes) {
        if (lessonId == null) {
            return;
        }
        AgentLessonLearned__c lesson = new AgentLessonLearned__c(
            Id = lessonId,
            admin_notes__c = newNotes,
            last_modified_by_admin__c = Datetime.now()
        );
        update lesson;
    }

    @AuraEnabled
    public static void deprecateLesson(Id lessonId, String action) {
        if (lessonId == null || String.isBlank(action)) {
            return;
        }
        AgentLessonLearned__c lesson = new AgentLessonLearned__c(Id = lessonId);
        if (action == 'hide') {
            lesson.confidence_score__c = 0;
        } else if (action == 'demote') {
            lesson.is_promoted__c = false;
        } else if (action == 'archive') {
            lesson.is_archived__c = true;
        }
        update lesson;
    }

    @AuraEnabled
    public static void removeLessonPermanently(Id lessonId) {
        if (lessonId == null || String.isBlank(String.valueOf(lessonId))) {
            throw new AuraHandledException('Lesson ID is required. Received: ' + lessonId);
        }
        // Clear references in action outcomes
        List<AgentActionOutcome__c> outcomes = [
            SELECT Id, lesson_linked__c
            FROM AgentActionOutcome__c
            WHERE lesson_linked__c = :lessonId
        ];
        for (AgentActionOutcome__c outcome : outcomes) {
            outcome.lesson_linked__c = null;
        }
        if (!outcomes.isEmpty()) {
            update outcomes;
        }

        // Delete the lesson
        AgentLessonLearned__c lesson = [
            SELECT Id FROM AgentLessonLearned__c WHERE Id = :lessonId LIMIT 1
        ];
        delete lesson;
    }

    @AuraEnabled
    public static List<Map<String, Object>> getLessonConfidenceTrend(Id lessonId) {
        // No snapshot object exists, but the confidence trajectory is fully
        // reconstructable: replay the lesson's outcome history applying the same
        // step model the reward handler uses (+0.05 helpful / -0.02 unhelpful,
        // clamped 0..1) from the new-lesson starting confidence of 0.90.
        List<Map<String, Object>> trend = new List<Map<String, Object>>();
        if (lessonId == null) {
            return trend;
        }
        final Decimal STARTING_CONFIDENCE = 0.90;
        final Decimal STEP_UP = 0.05;
        final Decimal STEP_DOWN = 0.02;

        List<AgentActionOutcome__c> applications = [
            SELECT lesson_was_helpful__c, timestamp__c
            FROM AgentActionOutcome__c
            WHERE lesson_linked__c = :lessonId
            WITH SECURITY_ENFORCED
            ORDER BY timestamp__c ASC
        ];

        Decimal confidence = STARTING_CONFIDENCE;
        // seed point: lesson creation
        trend.add(new Map<String, Object>{
            'point' => 0,
            'confidence' => confidence,
            'event' => 'created'
        });
        Integer i = 1;
        for (AgentActionOutcome__c o : applications) {
            confidence += (o.lesson_was_helpful__c == true) ? STEP_UP : -STEP_DOWN;
            confidence = Math.max(0, Math.min(1.0, confidence));
            trend.add(new Map<String, Object>{
                'point' => i,
                'confidence' => confidence.setScale(2),
                'event' => (o.lesson_was_helpful__c == true) ? 'helpful' : 'unhelpful',
                'timestamp' => o.timestamp__c
            });
            i++;
        }
        return trend;
    }

    @AuraEnabled
    public static List<AgentActionOutcome__c> getLessonUsageHistory(Id lessonId, Integer pageNumber) {
        if (lessonId == null) {
            return new List<AgentActionOutcome__c>();
        }
        Integer pg = (pageNumber == null || pageNumber < 0) ? 0 : pageNumber;
        Integer offsetVal = pg * 10;
        return [
            SELECT Id, agent_api_name__c, session_id__c, action_name__c, topic_area__c,
                   outcome__c, reward_points__c, lesson_linked__c, lesson_was_helpful__c,
                   cumulative_points__c, timestamp__c
            FROM AgentActionOutcome__c
            WHERE lesson_linked__c = :lessonId
            WITH SECURITY_ENFORCED
            ORDER BY timestamp__c DESC
            LIMIT 10
            OFFSET :offsetVal
        ];
    }
}