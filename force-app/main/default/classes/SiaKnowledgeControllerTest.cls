@IsTest
private class SiaKnowledgeControllerTest {

    private static AgentLessonLearned__c promotedLesson;
    private static AgentLessonLearned__c activeLesson;
    private static AgentLessonLearned__c hiddenLesson;
    private static AgentLessonLearned__c archivedLesson;

    @TestSetup
    static void setupData() {
        List<AgentLessonLearned__c> lessons = new List<AgentLessonLearned__c>();
        lessons.add(new AgentLessonLearned__c(
            agent_api_name__c = 'KnowledgeAgent',
            topic_area__c = 'Service',
            outcome_type__c = 'Success',
            lesson_text__c = 'Promoted lesson text',
            action_context__c = 'promoted_ctx',
            confidence_score__c = 0.95,
            is_promoted__c = true,
            is_archived__c = false,
            times_referenced__c = 10,
            times_successful__c = 8
        ));
        lessons.add(new AgentLessonLearned__c(
            agent_api_name__c = 'KnowledgeAgent',
            topic_area__c = 'Service',
            outcome_type__c = 'Success',
            lesson_text__c = 'Active lesson text',
            action_context__c = 'active_ctx',
            confidence_score__c = 0.55,
            is_promoted__c = false,
            is_archived__c = false,
            times_referenced__c = 3,
            times_successful__c = 2
        ));
        lessons.add(new AgentLessonLearned__c(
            agent_api_name__c = 'KnowledgeAgent',
            topic_area__c = 'Sales',
            outcome_type__c = 'Failure',
            lesson_text__c = 'Hidden lesson text',
            action_context__c = 'hidden_ctx',
            confidence_score__c = 0.1,
            is_promoted__c = false,
            is_archived__c = false
        ));
        lessons.add(new AgentLessonLearned__c(
            agent_api_name__c = 'KnowledgeAgent',
            topic_area__c = 'Service',
            outcome_type__c = 'Optimization',
            lesson_text__c = 'Archived lesson text',
            action_context__c = 'archived_ctx',
            confidence_score__c = 0.7,
            is_promoted__c = false,
            is_archived__c = true
        ));
        insert lessons;

        // Create outcome linked to the promoted lesson
        AgentActionOutcome__c outcome = new AgentActionOutcome__c(
            agent_api_name__c = 'KnowledgeAgent',
            session_id__c = 'KNOW-SESS-001',
            action_name__c = 'apply_lesson',
            outcome__c = 'success',
            reward_points__c = 3,
            cumulative_points__c = 3,
            lesson_linked__c = lessons[0].Id,
            lesson_was_helpful__c = true,
            timestamp__c = DateTime.now()
        );
        insert outcome;
    }

    @IsTest
    static void testGetLessonsAll() {
        List<AgentLessonLearned__c> lessons = SiaKnowledgeController.getLessons('KnowledgeAgent', null, 'all');
        Assert.areEqual(4, lessons.size());
    }

    @IsTest
    static void testGetLessonsPromoted() {
        List<AgentLessonLearned__c> lessons = SiaKnowledgeController.getLessons('KnowledgeAgent', null, 'promoted');
        Assert.areEqual(1, lessons.size());
        Assert.areEqual('Promoted lesson text', lessons[0].lesson_text__c);
    }

    @IsTest
    static void testGetLessonsActive() {
        List<AgentLessonLearned__c> lessons = SiaKnowledgeController.getLessons('KnowledgeAgent', null, 'active');
        Assert.areEqual(1, lessons.size());
        Assert.areEqual('Active lesson text', lessons[0].lesson_text__c);
    }

    @IsTest
    static void testGetLessonsHidden() {
        List<AgentLessonLearned__c> lessons = SiaKnowledgeController.getLessons('KnowledgeAgent', null, 'hidden');
        Assert.areEqual(1, lessons.size());
        Assert.areEqual('Hidden lesson text', lessons[0].lesson_text__c);
    }

    @IsTest
    static void testGetLessonsArchived() {
        List<AgentLessonLearned__c> lessons = SiaKnowledgeController.getLessons('KnowledgeAgent', null, 'archived');
        Assert.areEqual(1, lessons.size());
    }

    @IsTest
    static void testGetLessonsByTopic() {
        List<AgentLessonLearned__c> lessons = SiaKnowledgeController.getLessons('KnowledgeAgent', 'Sales', 'all');
        Assert.areEqual(1, lessons.size());
    }

    @IsTest
    static void testGetLessonsBlankAgent() {
        List<AgentLessonLearned__c> lessons = SiaKnowledgeController.getLessons('', null, 'all');
        Assert.areEqual(0, lessons.size());
    }

    @IsTest
    static void testGetLesson() {
        AgentLessonLearned__c lesson = [SELECT Id FROM AgentLessonLearned__c WHERE action_context__c = 'promoted_ctx' LIMIT 1];
        AgentLessonLearned__c result = SiaKnowledgeController.getLesson(lesson.Id);
        Assert.isNotNull(result);
        Assert.areEqual('Promoted lesson text', result.lesson_text__c);
    }

    @IsTest
    static void testGetLessonNull() {
        AgentLessonLearned__c result = SiaKnowledgeController.getLesson(null);
        Assert.areEqual(null, result);
    }

    @IsTest
    static void testUpdateLessonText() {
        AgentLessonLearned__c lesson = [SELECT Id FROM AgentLessonLearned__c WHERE action_context__c = 'active_ctx' LIMIT 1];
        SiaKnowledgeController.updateLessonText(lesson.Id, 'Updated text');
        AgentLessonLearned__c updated = [SELECT lesson_text__c, last_modified_by_admin__c FROM AgentLessonLearned__c WHERE Id = :lesson.Id];
        Assert.areEqual('Updated text', updated.lesson_text__c);
        Assert.isNotNull(updated.last_modified_by_admin__c);
    }

    @IsTest
    static void testUpdateAdminNotes() {
        AgentLessonLearned__c lesson = [SELECT Id FROM AgentLessonLearned__c WHERE action_context__c = 'active_ctx' LIMIT 1];
        SiaKnowledgeController.updateAdminNotes(lesson.Id, 'Admin note here');
        AgentLessonLearned__c updated = [SELECT admin_notes__c FROM AgentLessonLearned__c WHERE Id = :lesson.Id];
        Assert.areEqual('Admin note here', updated.admin_notes__c);
    }

    @IsTest
    static void testDeprecateLessonHide() {
        AgentLessonLearned__c lesson = [SELECT Id FROM AgentLessonLearned__c WHERE action_context__c = 'active_ctx' LIMIT 1];
        SiaKnowledgeController.deprecateLesson(lesson.Id, 'hide');
        AgentLessonLearned__c updated = [SELECT confidence_score__c FROM AgentLessonLearned__c WHERE Id = :lesson.Id];
        Assert.areEqual(0, updated.confidence_score__c);
    }

    @IsTest
    static void testDeprecateLessonDemote() {
        AgentLessonLearned__c lesson = [SELECT Id FROM AgentLessonLearned__c WHERE action_context__c = 'promoted_ctx' LIMIT 1];
        SiaKnowledgeController.deprecateLesson(lesson.Id, 'demote');
        AgentLessonLearned__c updated = [SELECT is_promoted__c FROM AgentLessonLearned__c WHERE Id = :lesson.Id];
        Assert.areEqual(false, updated.is_promoted__c);
    }

    @IsTest
    static void testDeprecateLessonArchive() {
        AgentLessonLearned__c lesson = [SELECT Id FROM AgentLessonLearned__c WHERE action_context__c = 'active_ctx' LIMIT 1];
        SiaKnowledgeController.deprecateLesson(lesson.Id, 'archive');
        AgentLessonLearned__c updated = [SELECT is_archived__c FROM AgentLessonLearned__c WHERE Id = :lesson.Id];
        Assert.areEqual(true, updated.is_archived__c);
    }

    @IsTest
    static void testDeprecateLessonNullParams() {
        // Should not throw
        SiaKnowledgeController.deprecateLesson(null, 'hide');
    }

    @IsTest
    static void testRemoveLessonPermanently() {
        AgentLessonLearned__c lesson = [SELECT Id FROM AgentLessonLearned__c WHERE action_context__c = 'promoted_ctx' LIMIT 1];
        // Verify outcome is linked before removal
        List<AgentActionOutcome__c> beforeOutcomes = [SELECT lesson_linked__c FROM AgentActionOutcome__c WHERE lesson_linked__c = :lesson.Id];
        Assert.areEqual(1, beforeOutcomes.size());

        SiaKnowledgeController.removeLessonPermanently(lesson.Id);

        List<AgentLessonLearned__c> remaining = [SELECT Id FROM AgentLessonLearned__c WHERE Id = :lesson.Id];
        Assert.areEqual(0, remaining.size());
        // Outcome should have null lesson_linked
        List<AgentActionOutcome__c> afterOutcomes = [SELECT lesson_linked__c FROM AgentActionOutcome__c WHERE Id = :beforeOutcomes[0].Id];
        Assert.areEqual(null, afterOutcomes[0].lesson_linked__c);
    }

    @IsTest
    static void testGetLessonConfidenceTrend() {
        // Lesson with no linked outcomes → trend has just the seed "created" point at 0.90.
        AgentLessonLearned__c lesson = [SELECT Id FROM AgentLessonLearned__c WHERE action_context__c = 'active_ctx' LIMIT 1];
        List<Map<String, Object>> trend = SiaKnowledgeController.getLessonConfidenceTrend(lesson.Id);
        Assert.isNotNull(trend);
        Assert.areEqual(1, trend.size(), 'Expected seed point only when no applications exist');
        Assert.areEqual('created', trend[0].get('event'));
        Assert.areEqual(0.90, (Decimal) trend[0].get('confidence'));

        // Null id → empty list.
        Assert.areEqual(0, SiaKnowledgeController.getLessonConfidenceTrend(null).size());

        // Lesson WITH a linked helpful outcome → trend replays the +0.05 step.
        AgentLessonLearned__c promoted = [SELECT Id FROM AgentLessonLearned__c WHERE action_context__c = 'promoted_ctx' LIMIT 1];
        List<Map<String, Object>> promotedTrend = SiaKnowledgeController.getLessonConfidenceTrend(promoted.Id);
        Assert.areEqual(2, promotedTrend.size(), 'Seed + one application');
        Assert.areEqual('helpful', promotedTrend[1].get('event'));
        Assert.areEqual(0.95, (Decimal) promotedTrend[1].get('confidence'), '0.90 + 0.05');
    }

    @IsTest
    static void testGetLessonUsageHistory() {
        AgentLessonLearned__c lesson = [SELECT Id FROM AgentLessonLearned__c WHERE action_context__c = 'promoted_ctx' LIMIT 1];
        List<AgentActionOutcome__c> history = SiaKnowledgeController.getLessonUsageHistory(lesson.Id, 0);
        Assert.areEqual(1, history.size());
    }

    @IsTest
    static void testGetLessonUsageHistoryNullId() {
        List<AgentActionOutcome__c> history = SiaKnowledgeController.getLessonUsageHistory(null, 0);
        Assert.areEqual(0, history.size());
    }
}