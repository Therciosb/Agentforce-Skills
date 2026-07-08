@IsTest
private class AgentRewardHandlerTest {

    private static final String AGENT_NAME = 'TestAgent';
    private static final String SESSION_ID = 'session-001';

    @IsTest
    static void testGoalSuccessOutcome() {
        AgentRewardConfig__c config = new AgentRewardConfig__c(
            agent_api_name__c = AGENT_NAME,
            action_name__c = 'goal_success',
            topic_area__c = null,
            points__c = 10,
            is_active__c = true
        );
        insert config;

        AgentReward__e evt = new AgentReward__e(
            Session_Id__c = SESSION_ID,
            Action_Name__c = 'goal_success',
            Topic_Area__c = null,
            Outcome__c = 'success',
            Agent_Api_Name__c = AGENT_NAME
        );

        Test.startTest();
        EventBus.publish(evt);
        Test.getEventBus().deliver();
        Test.stopTest();

        List<AgentActionOutcome__c> outcomes = [
            SELECT reward_points__c, action_name__c, session_id__c
            FROM AgentActionOutcome__c
            WHERE session_id__c = :SESSION_ID
        ];
        Assert.areEqual(1, outcomes.size(), 'Expected one outcome record');
        Assert.areEqual(10, outcomes[0].reward_points__c, 'Expected 10 reward points');
    }

    @IsTest
    static void testLessonConfidenceIncreasesOnSuccess() {
        AgentLessonLearned__c lesson = new AgentLessonLearned__c(
            agent_api_name__c = AGENT_NAME,
            topic_area__c = 'password_reset',
            outcome_type__c = 'Success',
            times_referenced__c = 5,
            times_successful__c = 4,
            confidence_score__c = 0.80,
            is_promoted__c = false,
            is_archived__c = false
        );
        insert lesson;

        AgentRewardConfig__c config = new AgentRewardConfig__c(
            agent_api_name__c = AGENT_NAME,
            action_name__c = 'use_lesson',
            points__c = 5,
            is_active__c = true
        );
        insert config;

        AgentReward__e evt = new AgentReward__e(
            Session_Id__c = SESSION_ID,
            Action_Name__c = 'use_lesson',
            Outcome__c = 'success',
            Agent_Api_Name__c = AGENT_NAME,
            Lesson_Id__c = String.valueOf(lesson.Id),
            Lesson_Was_Helpful__c = true
        );

        Test.startTest();
        EventBus.publish(evt);
        Test.getEventBus().deliver();
        Test.stopTest();

        AgentLessonLearned__c updated = [
            SELECT times_referenced__c, times_successful__c, confidence_score__c
            FROM AgentLessonLearned__c
            WHERE Id = :lesson.Id
        ];
        Assert.areEqual(6, updated.times_referenced__c, 'Expected times_referenced to be 6');
        Assert.areEqual(5, updated.times_successful__c, 'Expected times_successful to be 5');
        // Step-based model: helpful use adds +0.05 (0.80 -> 0.85)
        Assert.areEqual(0.85, updated.confidence_score__c, 'Expected confidence 0.80 + 0.05 = 0.85');
    }

    @IsTest
    static void testLessonConfidenceDecreasesOnFailure() {
        AgentLessonLearned__c lesson = new AgentLessonLearned__c(
            agent_api_name__c = AGENT_NAME,
            topic_area__c = 'password_reset',
            outcome_type__c = 'Success',
            times_referenced__c = 5,
            times_successful__c = 4,
            confidence_score__c = 0.80,
            is_promoted__c = false,
            is_archived__c = false
        );
        insert lesson;

        AgentRewardConfig__c config = new AgentRewardConfig__c(
            agent_api_name__c = AGENT_NAME,
            action_name__c = 'use_lesson',
            points__c = 5,
            is_active__c = true
        );
        insert config;

        AgentReward__e evt = new AgentReward__e(
            Session_Id__c = SESSION_ID,
            Action_Name__c = 'use_lesson',
            Outcome__c = 'success',
            Agent_Api_Name__c = AGENT_NAME,
            Lesson_Id__c = String.valueOf(lesson.Id),
            Lesson_Was_Helpful__c = false
        );

        Test.startTest();
        EventBus.publish(evt);
        Test.getEventBus().deliver();
        Test.stopTest();

        AgentLessonLearned__c updated = [
            SELECT times_referenced__c, times_successful__c, confidence_score__c
            FROM AgentLessonLearned__c
            WHERE Id = :lesson.Id
        ];
        Assert.areEqual(6, updated.times_referenced__c, 'Expected times_referenced to be 6');
        Assert.areEqual(4, updated.times_successful__c, 'Expected times_successful unchanged at 4');
        // Step-based model: unhelpful use subtracts -0.02 (0.80 -> 0.78)
        Assert.areEqual(0.78, updated.confidence_score__c, 'Expected confidence 0.80 - 0.02 = 0.78');
    }

    @IsTest
    static void testLessonPromotesAtThreshold() {
        AgentLessonLearned__c lesson = new AgentLessonLearned__c(
            agent_api_name__c = AGENT_NAME,
            topic_area__c = 'password_reset',
            outcome_type__c = 'Success',
            times_referenced__c = 9,
            times_successful__c = 8,
            confidence_score__c = 0.89,
            is_promoted__c = false,
            is_archived__c = false
        );
        insert lesson;

        AgentImprovementConfig__c impConfig = new AgentImprovementConfig__c(
            agent_api_name__c = AGENT_NAME,
            promotion_confidence__c = 0.80,
            promotion_references__c = 10,
            demotion_confidence__c = 0.10
        );
        insert impConfig;

        AgentRewardConfig__c config = new AgentRewardConfig__c(
            agent_api_name__c = AGENT_NAME,
            action_name__c = 'use_lesson',
            points__c = 5,
            is_active__c = true
        );
        insert config;

        AgentReward__e evt = new AgentReward__e(
            Session_Id__c = SESSION_ID,
            Action_Name__c = 'use_lesson',
            Outcome__c = 'success',
            Agent_Api_Name__c = AGENT_NAME,
            Lesson_Id__c = String.valueOf(lesson.Id),
            Lesson_Was_Helpful__c = true
        );

        Test.startTest();
        EventBus.publish(evt);
        Test.getEventBus().deliver();
        Test.stopTest();

        AgentLessonLearned__c updated = [
            SELECT times_referenced__c, times_successful__c, confidence_score__c, is_promoted__c
            FROM AgentLessonLearned__c
            WHERE Id = :lesson.Id
        ];
        Assert.areEqual(10, updated.times_referenced__c, 'Expected times_referenced to be 10');
        Assert.areEqual(9, updated.times_successful__c, 'Expected times_successful to be 9');
        // Step-based model: helpful use adds +0.05 (0.89 -> 0.94)
        Assert.areEqual(0.94, updated.confidence_score__c, 'Expected confidence 0.89 + 0.05 = 0.94');
        Assert.areEqual(true, updated.is_promoted__c, 'Expected lesson to be promoted (>=0.80 conf, >=10 refs)');
    }

    @IsTest
    static void testLessonArchivesAtLowConfidence() {
        AgentLessonLearned__c lesson = new AgentLessonLearned__c(
            agent_api_name__c = AGENT_NAME,
            topic_area__c = 'password_reset',
            outcome_type__c = 'Success',
            times_referenced__c = 9,
            times_successful__c = 0,
            confidence_score__c = 0.00,
            is_promoted__c = false,
            is_archived__c = false
        );
        insert lesson;

        AgentImprovementConfig__c impConfig = new AgentImprovementConfig__c(
            agent_api_name__c = AGENT_NAME,
            promotion_confidence__c = 0.80,
            promotion_references__c = 10,
            demotion_confidence__c = 0.10
        );
        insert impConfig;

        AgentRewardConfig__c config = new AgentRewardConfig__c(
            agent_api_name__c = AGENT_NAME,
            action_name__c = 'use_lesson',
            points__c = 5,
            is_active__c = true
        );
        insert config;

        AgentReward__e evt = new AgentReward__e(
            Session_Id__c = SESSION_ID,
            Action_Name__c = 'use_lesson',
            Outcome__c = 'success',
            Agent_Api_Name__c = AGENT_NAME,
            Lesson_Id__c = String.valueOf(lesson.Id),
            Lesson_Was_Helpful__c = false
        );

        Test.startTest();
        EventBus.publish(evt);
        Test.getEventBus().deliver();
        Test.stopTest();

        AgentLessonLearned__c updated = [
            SELECT times_referenced__c, confidence_score__c, is_archived__c
            FROM AgentLessonLearned__c
            WHERE Id = :lesson.Id
        ];
        Assert.areEqual(10, updated.times_referenced__c, 'Expected times_referenced to be 10');
        Assert.areEqual(true, updated.is_archived__c, 'Expected lesson to be archived');
    }

    @IsTest
    static void testGlobalConfigFallback() {
        AgentRewardConfig__c globalConfig = new AgentRewardConfig__c(
            agent_api_name__c = AGENT_NAME,
            action_name__c = 'ask_question',
            topic_area__c = null,
            points__c = 3,
            is_active__c = true
        );
        insert globalConfig;

        AgentReward__e evt = new AgentReward__e(
            Session_Id__c = SESSION_ID,
            Action_Name__c = 'ask_question',
            Topic_Area__c = 'billing',
            Outcome__c = 'partial',
            Agent_Api_Name__c = AGENT_NAME
        );

        Test.startTest();
        EventBus.publish(evt);
        Test.getEventBus().deliver();
        Test.stopTest();

        List<AgentActionOutcome__c> outcomes = [
            SELECT reward_points__c, topic_area__c
            FROM AgentActionOutcome__c
            WHERE session_id__c = :SESSION_ID
        ];
        Assert.areEqual(1, outcomes.size(), 'Expected one outcome record');
        Assert.areEqual(3, outcomes[0].reward_points__c, 'Expected 3 points from global config fallback');
        Assert.areEqual('billing', outcomes[0].topic_area__c, 'Expected topic_area preserved from event');
    }

    @IsTest
    static void testBulkProcessing() {
        AgentRewardConfig__c config = new AgentRewardConfig__c(
            agent_api_name__c = AGENT_NAME,
            action_name__c = 'bulk_action',
            topic_area__c = null,
            points__c = 1,
            is_active__c = true
        );
        insert config;

        List<AgentReward__e> events = new List<AgentReward__e>();
        for (Integer i = 0; i < 200; i++) {
            events.add(new AgentReward__e(
                Session_Id__c = 'bulk-session-' + i,
                Action_Name__c = 'bulk_action',
                Outcome__c = 'success',
                Agent_Api_Name__c = AGENT_NAME
            ));
        }

        Test.startTest();
        EventBus.publish(events);
        Test.getEventBus().deliver();
        Test.stopTest();

        Integer outcomeCount = [SELECT COUNT() FROM AgentActionOutcome__c WHERE action_name__c = 'bulk_action'];
        Assert.areEqual(200, outcomeCount, 'Expected 200 outcome records');
    }

    @IsTest
    static void testMultipleLessonIdsAllCredited() {
        // Two lessons surfaced together — both must be credited, not just the first.
        List<AgentLessonLearned__c> lessons = new List<AgentLessonLearned__c>{
            new AgentLessonLearned__c(
                agent_api_name__c = AGENT_NAME,
                topic_area__c = 'password_reset',
                outcome_type__c = 'Success',
                times_referenced__c = 1,
                times_successful__c = 1,
                confidence_score__c = 0.80,
                is_promoted__c = false,
                is_archived__c = false
            ),
            new AgentLessonLearned__c(
                agent_api_name__c = AGENT_NAME,
                topic_area__c = 'password_reset',
                outcome_type__c = 'Success',
                times_referenced__c = 1,
                times_successful__c = 1,
                confidence_score__c = 0.80,
                is_promoted__c = false,
                is_archived__c = false
            )
        };
        insert lessons;

        insert new AgentRewardConfig__c(
            agent_api_name__c = AGENT_NAME,
            action_name__c = 'lesson_applied_success',
            points__c = 3,
            is_active__c = true
        );

        AgentReward__e evt = new AgentReward__e(
            Session_Id__c = SESSION_ID,
            Action_Name__c = 'lesson_applied_success',
            Topic_Area__c = 'password_reset',
            Outcome__c = 'success',
            Agent_Api_Name__c = AGENT_NAME,
            Lesson_Id__c = lessons[0].Id + ',' + lessons[1].Id,
            Lesson_Was_Helpful__c = true
        );

        Test.startTest();
        EventBus.publish(evt);
        Test.getEventBus().deliver();
        Test.stopTest();

        Map<Id, AgentLessonLearned__c> updated = new Map<Id, AgentLessonLearned__c>([
            SELECT times_referenced__c, times_successful__c, confidence_score__c
            FROM AgentLessonLearned__c WHERE Id IN :lessons
        ]);
        // Both lessons credited: refs 1 -> 2, confidence 0.80 -> 0.85
        for (AgentLessonLearned__c l : updated.values()) {
            Assert.areEqual(2, l.times_referenced__c, 'Both surfaced lessons should be referenced');
            Assert.areEqual(2, l.times_successful__c, 'Both should count as successful');
            Assert.areEqual(0.85, l.confidence_score__c, 'Both confidence 0.80 + 0.05 = 0.85');
        }

        // Session should count both lessons applied
        AgentSession__c sess = [
            SELECT lessons_applied__c FROM AgentSession__c WHERE session_id__c = :SESSION_ID
        ];
        Assert.areEqual(2, sess.lessons_applied__c, 'Both surfaced lessons should count as applied');
    }

    @IsTest
    static void testMetaEventsDoNotInflateActionsTaken() {
        // Regression: framework meta-events (goal/lesson/knowledge rewards) must NOT count
        // toward actions_taken__c. Only true business actions should. Counting meta-events
        // corrupted the AES efficiency sub-score and made the improvement rate go negative
        // for learning-heavy sessions.
        for (String an : new List<String>{'goal_success', 'knowledge_creation', 'lesson_applied_success', 'lesson_applied_failure'}) {
            insert new AgentRewardConfig__c(
                agent_api_name__c = AGENT_NAME, action_name__c = an, points__c = 5, is_active__c = true
            );
        }
        // A non-meta (business) action for contrast.
        insert new AgentRewardConfig__c(
            agent_api_name__c = AGENT_NAME, action_name__c = 'lookup_record', points__c = 1, is_active__c = true
        );

        List<AgentReward__e> evts = new List<AgentReward__e>{
            new AgentReward__e(Session_Id__c = SESSION_ID, Action_Name__c = 'goal_success', Outcome__c = 'success', Agent_Api_Name__c = AGENT_NAME),
            new AgentReward__e(Session_Id__c = SESSION_ID, Action_Name__c = 'knowledge_creation', Outcome__c = 'success', Agent_Api_Name__c = AGENT_NAME),
            new AgentReward__e(Session_Id__c = SESSION_ID, Action_Name__c = 'lesson_applied_success', Outcome__c = 'success', Agent_Api_Name__c = AGENT_NAME),
            new AgentReward__e(Session_Id__c = SESSION_ID, Action_Name__c = 'lesson_applied_failure', Outcome__c = 'failure', Agent_Api_Name__c = AGENT_NAME),
            new AgentReward__e(Session_Id__c = SESSION_ID, Action_Name__c = 'lookup_record', Outcome__c = 'success', Agent_Api_Name__c = AGENT_NAME)
        };

        Test.startTest();
        EventBus.publish(evts);
        Test.getEventBus().deliver();
        Test.stopTest();

        AgentSession__c sess = [
            SELECT actions_taken__c FROM AgentSession__c WHERE session_id__c = :SESSION_ID
        ];
        // 5 events delivered, but only the 1 business action ('lookup_record') counts.
        Assert.areEqual(1, sess.actions_taken__c,
            'Only business actions should count toward actions_taken__c; meta-events must be excluded');
    }

    @IsTest
    static void testSessionLessonContribution() {
        Assert.areEqual(15, AesCalculator.sessionLessonContribution(true, true), 'applied+successful = +15');
        Assert.areEqual(5, AesCalculator.sessionLessonContribution(true, false), 'applied+unsuccessful = +5');
        Assert.areEqual(0, AesCalculator.sessionLessonContribution(false, false), 'no lesson applied = 0');
        Assert.areEqual(0, AesCalculator.sessionLessonContribution(null, null), 'nulls = 0');
    }

    @IsTest
    static void testCumulativeAesAccumulatesAcrossSessions() {
        // AES is cumulative: each session adds its lesson-application contribution to the
        // agent's running total, in chronological order. The curve must only rise.
        insert new AgentLessonLearned__c(
            agent_api_name__c = AGENT_NAME, topic_area__c = 'knowledge', outcome_type__c = 'Success',
            times_referenced__c = 1, times_successful__c = 1, confidence_score__c = 0.90,
            is_promoted__c = false, is_archived__c = false
        );
        AgentLessonLearned__c lesson = [SELECT Id FROM AgentLessonLearned__c LIMIT 1];
        insert new AgentRewardConfig__c(
            agent_api_name__c = AGENT_NAME, action_name__c = 'lesson_applied_success', points__c = 3, is_active__c = true
        );

        // Three sessions, each applying a lesson successfully (+15 each) -> cumulative 15, 30, 45.
        List<AgentReward__e> evts = new List<AgentReward__e>();
        for (Integer i = 1; i <= 3; i++) {
            evts.add(new AgentReward__e(
                Session_Id__c = 'cum-' + i,
                Action_Name__c = 'lesson_applied_success',
                Topic_Area__c = 'knowledge',
                Outcome__c = 'success',
                Agent_Api_Name__c = AGENT_NAME,
                Lesson_Id__c = String.valueOf(lesson.Id),
                Lesson_Was_Helpful__c = true
            ));
        }

        Test.startTest();
        EventBus.publish(evts);
        Test.getEventBus().deliver();
        Test.stopTest();

        // Order by start_time then CreatedDate (same as the handler) — all created "now",
        // so CreatedDate ASC preserves insertion order cum-1, cum-2, cum-3.
        List<AgentSession__c> sessions = [
            SELECT session_id__c, aes_score__c
            FROM AgentSession__c
            WHERE agent_api_name__c = :AGENT_NAME
            ORDER BY start_time__c ASC, CreatedDate ASC
        ];
        Assert.areEqual(3, sessions.size(), 'Three sessions expected');
        Assert.areEqual(15, sessions[0].aes_score__c, 'First session cumulative = 15');
        Assert.areEqual(30, sessions[1].aes_score__c, 'Second session cumulative = 30');
        Assert.areEqual(45, sessions[2].aes_score__c, 'Third session cumulative = 45');
    }

    // ---- Config-driven outcome classification (raw domain_event + category) ----
    // The agent reports WHAT happened (domain_event) + category; the platform
    // composes the canonical Action_Name__c from the subagent's outcome mapping.

    @IsTest
    static void domainEvent_composesLessonAppliedSuccess() {
        insert new AgentSubagentConfig__c(
            agent_api_name__c = AGENT_NAME, topic_area__c = 'knowledge', optimal_actions__c = 2,
            outcome_mapping_json__c = '[{"domain_event":"resolved","maps_to":"success"},{"domain_event":"unresolved","maps_to":"failure"}]',
            significant_outcome_triggers__c = 'failure');
        insert new AgentRewardConfig__c(
            agent_api_name__c = AGENT_NAME, action_name__c = 'lesson_applied_success',
            topic_area__c = 'knowledge', points__c = 3, is_active__c = true);

        // Event carries the RAW event + category, NOT a pre-classified Action_Name__c.
        // Call processRewards directly: Test.getEventBus().deliver() does NOT round-trip
        // newly-added platform-event fields (Domain_Event__c/Reward_Category__c), so the
        // direct call is the reliable way to unit-test the config-driven composition.
        AgentReward__e evt = new AgentReward__e(
            Session_Id__c = SESSION_ID, Agent_Api_Name__c = AGENT_NAME,
            Topic_Area__c = 'knowledge', Reward_Category__c = 'lesson', Domain_Event__c = 'resolved');

        Test.startTest();
        AgentRewardHandler.processRewards(new List<AgentReward__e>{ evt });
        Test.stopTest();

        List<AgentActionOutcome__c> outcomes = [
            SELECT reward_points__c, action_name__c FROM AgentActionOutcome__c WHERE session_id__c = :SESSION_ID];
        Assert.areEqual(1, outcomes.size(), 'one outcome');
        Assert.areEqual('lesson_applied_success', outcomes[0].action_name__c, 'resolved -> lesson_applied_success via config');
        Assert.areEqual(3, outcomes[0].reward_points__c, 'points resolved from composed action');
    }

    @IsTest
    static void domainEvent_classificationFollowsConfig_notEventName() {
        // Flip the mapping: "resolved" now means FAILURE. The composed action must follow config.
        insert new AgentSubagentConfig__c(
            agent_api_name__c = AGENT_NAME, topic_area__c = 'knowledge', optimal_actions__c = 2,
            outcome_mapping_json__c = '[{"domain_event":"resolved","maps_to":"failure"}]',
            significant_outcome_triggers__c = 'failure');
        insert new AgentRewardConfig__c(
            agent_api_name__c = AGENT_NAME, action_name__c = 'lesson_applied_failure',
            topic_area__c = 'knowledge', points__c = -2, is_active__c = true);

        AgentReward__e evt = new AgentReward__e(
            Session_Id__c = SESSION_ID, Agent_Api_Name__c = AGENT_NAME,
            Topic_Area__c = 'knowledge', Reward_Category__c = 'lesson', Domain_Event__c = 'resolved');

        Test.startTest();
        AgentRewardHandler.processRewards(new List<AgentReward__e>{ evt });
        Test.stopTest();

        List<AgentActionOutcome__c> outcomes = [
            SELECT reward_points__c, action_name__c FROM AgentActionOutcome__c WHERE session_id__c = :SESSION_ID];
        Assert.areEqual('lesson_applied_failure', outcomes[0].action_name__c, 'config-driven: resolved mapped to failure');
        Assert.areEqual(-2, outcomes[0].reward_points__c, 'points follow the config-composed action');
    }

    @IsTest
    static void domainEvent_creationCategory_composesKnowledgeCreation() {
        insert new AgentRewardConfig__c(
            agent_api_name__c = AGENT_NAME, action_name__c = 'knowledge_creation',
            topic_area__c = 'knowledge', points__c = 10, is_active__c = true);

        AgentReward__e evt = new AgentReward__e(
            Session_Id__c = SESSION_ID, Agent_Api_Name__c = AGENT_NAME,
            Topic_Area__c = 'knowledge', Reward_Category__c = 'creation', Domain_Event__c = 'created');

        Test.startTest();
        AgentRewardHandler.processRewards(new List<AgentReward__e>{ evt });
        Test.stopTest();

        List<AgentActionOutcome__c> outcomes = [
            SELECT reward_points__c, action_name__c FROM AgentActionOutcome__c WHERE session_id__c = :SESSION_ID];
        Assert.areEqual('knowledge_creation', outcomes[0].action_name__c, 'creation category -> knowledge_creation (no pass/fail)');
        Assert.areEqual(10, outcomes[0].reward_points__c);
    }
}