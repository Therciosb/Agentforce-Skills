public with sharing class AgentRewardHandler {

    // Framework "meta" events: bookkeeping signals (goal/lesson/knowledge rewards) that
    // the self-improving framework publishes, NOT business actions the agent performed.
    // These must NOT inflate actions_taken__c, which feeds the AES efficiency sub-score
    // (business actions vs optimal). Counting them penalizes sessions that learn/apply
    // more lessons — the opposite of what the framework is meant to reward.
    private static final Set<String> META_EVENT_ACTIONS = new Set<String>{
        'goal_success', 'goal_partial', 'goal_failure',
        'knowledge_creation', 'lesson_applied_success', 'lesson_applied_failure'
    };

    public static void processRewards(List<AgentReward__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        // Step 0: Resolve the canonical Action_Name__c. When the agent reports a
        // RAW domain event (Domain_Event__c) plus a Reward_Category__c, the
        // PLATFORM decides success/failure from the subagent's configured mapping
        // and composes the action name (e.g. lesson + success -> lesson_applied_success).
        // This makes outcome meaning configurable from the SIA Console instead of
        // being pre-decided by the agent. Events that already carry Action_Name__c
        // (no Domain_Event__c) pass through unchanged for backward compatibility.
        resolveActionNames(events);

        // Step 1: Collect unique identifiers
        Set<String> actionNames = new Set<String>();
        Set<String> topicAreas = new Set<String>();
        Set<String> sessionIds = new Set<String>();
        Set<Id> lessonIds = new Set<Id>();
        Set<String> agentApiNames = new Set<String>();

        for (AgentReward__e evt : events) {
            actionNames.add(evt.Action_Name__c);
            if (evt.Topic_Area__c != null) {
                topicAreas.add(evt.Topic_Area__c);
            }
            sessionIds.add(evt.Session_Id__c);
            lessonIds.addAll(parseLessonIds(evt.Lesson_Id__c));
            if (evt.Agent_Api_Name__c != null) {
                agentApiNames.add(evt.Agent_Api_Name__c);
            }
        }

        // Step 2: Query reward configs
        List<AgentRewardConfig__c> configs = [
            SELECT Id, agent_api_name__c, action_name__c, topic_area__c, points__c
            FROM AgentRewardConfig__c
            WHERE action_name__c IN :actionNames
            AND is_active__c = true
            WITH SECURITY_ENFORCED
        ];

        Map<String, AgentRewardConfig__c> configMap = new Map<String, AgentRewardConfig__c>();
        for (AgentRewardConfig__c cfg : configs) {
            String topicKey = cfg.topic_area__c != null ? cfg.topic_area__c : 'GLOBAL';
            String key = buildConfigKey(cfg.agent_api_name__c, cfg.action_name__c, topicKey);
            configMap.put(key, cfg);
        }

        // Step 3: Query or create AgentSession__c records
        Map<String, AgentSession__c> sessionMap = new Map<String, AgentSession__c>();
        List<AgentSession__c> existingSessions = [
            SELECT Id, session_id__c, agent_api_name__c, actions_taken__c, final_outcome__c,
                   final_points__c, lessons_applied__c, lessons_created__c, primary_topic__c,
                   aes_score__c, aes_goal__c, aes_efficiency__c, aes_learning__c, start_time__c
            FROM AgentSession__c
            WHERE session_id__c IN :sessionIds
            WITH SECURITY_ENFORCED
        ];
        for (AgentSession__c s : existingSessions) {
            sessionMap.put(s.session_id__c, s);
        }

        // Step 4: Query cumulative points (bulkified — one query for all sessions, newest first)
        Map<String, Decimal> sessionCumulativeMap = new Map<String, Decimal>();
        for (String sessionId : sessionIds) {
            sessionCumulativeMap.put(sessionId, 0);
        }
        for (AgentActionOutcome__c o : [
            SELECT session_id__c, cumulative_points__c
            FROM AgentActionOutcome__c
            WHERE session_id__c IN :sessionIds
            WITH SECURITY_ENFORCED
            ORDER BY timestamp__c ASC
        ]) {
            // ASC order means the last write per session wins, leaving the latest cumulative value
            if (o.cumulative_points__c != null) {
                sessionCumulativeMap.put(o.session_id__c, o.cumulative_points__c);
            }
        }

        // Step 5: Query lessons if needed
        Map<Id, AgentLessonLearned__c> lessonsMap = new Map<Id, AgentLessonLearned__c>();
        if (!lessonIds.isEmpty()) {
            lessonsMap = new Map<Id, AgentLessonLearned__c>([
                SELECT Id, confidence_score__c, times_referenced__c, times_successful__c,
                       is_promoted__c, is_archived__c, agent_api_name__c
                FROM AgentLessonLearned__c
                WHERE Id IN :lessonIds
                WITH SECURITY_ENFORCED
            ]);
        }

        // Query improvement configs
        Map<String, AgentImprovementConfig__c> improvementConfigs = new Map<String, AgentImprovementConfig__c>();
        if (!agentApiNames.isEmpty()) {
            List<AgentImprovementConfig__c> impConfigs = [
                SELECT agent_api_name__c, promotion_confidence__c, promotion_references__c, demotion_confidence__c
                FROM AgentImprovementConfig__c
                WHERE agent_api_name__c IN :agentApiNames
                WITH SECURITY_ENFORCED
            ];
            for (AgentImprovementConfig__c ic : impConfigs) {
                improvementConfigs.put(ic.agent_api_name__c, ic);
            }
        }

        // Query subagent configs for optimal_actions
        Map<String, Integer> optimalActionsMap = new Map<String, Integer>();
        if (!agentApiNames.isEmpty()) {
            List<AgentSubagentConfig__c> subConfigs = [
                SELECT agent_api_name__c, topic_area__c, optimal_actions__c
                FROM AgentSubagentConfig__c
                WHERE agent_api_name__c IN :agentApiNames
                WITH SECURITY_ENFORCED
            ];
            for (AgentSubagentConfig__c sc : subConfigs) {
                optimalActionsMap.put(sc.agent_api_name__c + '|' + sc.topic_area__c,
                    sc.optimal_actions__c != null ? Integer.valueOf(sc.optimal_actions__c) : 3);
            }
        }

        // Step 6: Process each event
        List<AgentActionOutcome__c> outcomesToInsert = new List<AgentActionOutcome__c>();
        Set<Id> lessonsToUpdate = new Set<Id>();
        Set<String> sessionsToUpsert = new Set<String>();

        for (AgentReward__e evt : events) {
            // Find matching config (priority: agent+topic > agent+global > global)
            AgentRewardConfig__c matchedConfig = null;
            if (evt.Topic_Area__c != null) {
                String specificKey = buildConfigKey(evt.Agent_Api_Name__c, evt.Action_Name__c, evt.Topic_Area__c);
                matchedConfig = configMap.get(specificKey);
            }
            if (matchedConfig == null) {
                String globalKey = buildConfigKey(evt.Agent_Api_Name__c, evt.Action_Name__c, 'GLOBAL');
                matchedConfig = configMap.get(globalKey);
            }
            if (matchedConfig == null) {
                String universalKey = buildConfigKey('', evt.Action_Name__c, 'GLOBAL');
                matchedConfig = configMap.get(universalKey);
            }

            Decimal points = matchedConfig != null ? matchedConfig.points__c : 0;
            Decimal previousCumulative = sessionCumulativeMap.get(evt.Session_Id__c);
            if (previousCumulative == null) {
                previousCumulative = 0;
            }
            Decimal newCumulative = previousCumulative + points;
            sessionCumulativeMap.put(evt.Session_Id__c, newCumulative);

            AgentActionOutcome__c outcome = new AgentActionOutcome__c(
                agent_api_name__c = evt.Agent_Api_Name__c,
                session_id__c = evt.Session_Id__c,
                action_name__c = evt.Action_Name__c,
                topic_area__c = evt.Topic_Area__c,
                outcome__c = evt.Outcome__c,
                reward_points__c = points,
                cumulative_points__c = newCumulative,
                timestamp__c = Datetime.now()
            );

            // Handle lesson linking — step-based confidence model.
            // Lesson_Id__c may carry multiple comma-separated IDs (all lessons surfaced
            // for the turn). Credit EVERY valid ID, not just the first.
            List<Id> creditedLessonIds = parseLessonIds(evt.Lesson_Id__c);
            if (!creditedLessonIds.isEmpty()) {
                // The outcome record links to the first lesson (single lookup field)
                outcome.lesson_linked__c = creditedLessonIds[0];
                outcome.lesson_was_helpful__c = evt.Lesson_Was_Helpful__c;

                // Resolve thresholds once per event
                Decimal promotionConfidence = 0.80;
                Decimal promotionReferences = 10;
                Decimal demotionConfidence = 0.10;
                AgentImprovementConfig__c impConfig = improvementConfigs.get(evt.Agent_Api_Name__c);
                if (impConfig != null) {
                    if (impConfig.promotion_confidence__c != null) promotionConfidence = impConfig.promotion_confidence__c;
                    if (impConfig.promotion_references__c != null) promotionReferences = impConfig.promotion_references__c;
                    if (impConfig.demotion_confidence__c != null) demotionConfidence = impConfig.demotion_confidence__c;
                }

                for (Id lessonId : creditedLessonIds) {
                    AgentLessonLearned__c lesson = lessonsMap.get(lessonId);
                    if (lesson == null) continue;

                    Decimal timesReferenced = lesson.times_referenced__c != null ? lesson.times_referenced__c : 0;
                    Decimal timesSuccessful = lesson.times_successful__c != null ? lesson.times_successful__c : 0;
                    Decimal confidence = lesson.confidence_score__c != null ? lesson.confidence_score__c : 0.90;

                    timesReferenced += 1;
                    if (evt.Lesson_Was_Helpful__c == true) {
                        timesSuccessful += 1;
                        confidence += 0.05;
                    } else {
                        confidence -= 0.02;
                    }

                    confidence = Math.max(0, Math.min(1.0, confidence));

                    lesson.times_referenced__c = timesReferenced;
                    lesson.times_successful__c = timesSuccessful;
                    lesson.confidence_score__c = confidence;

                    if (confidence >= promotionConfidence && timesReferenced >= promotionReferences) {
                        lesson.is_promoted__c = true;
                    }
                    if (confidence < demotionConfidence) {
                        lesson.is_archived__c = true;
                    }

                    lessonsToUpdate.add(lessonId);
                }
            }

            outcomesToInsert.add(outcome);

            // Step 7: Update session tracking
            AgentSession__c session = sessionMap.get(evt.Session_Id__c);
            if (session == null) {
                session = new AgentSession__c(
                    session_id__c = evt.Session_Id__c,
                    agent_api_name__c = evt.Agent_Api_Name__c,
                    start_time__c = Datetime.now(),
                    actions_taken__c = 0,
                    lessons_applied__c = 0,
                    lessons_created__c = 0,
                    final_points__c = 0
                );
                sessionMap.put(evt.Session_Id__c, session);
            }

            // Update session fields.
            // Only count BUSINESS actions toward actions_taken__c (the AES efficiency input).
            // Framework meta-events (goal/lesson/knowledge rewards) are bookkeeping and must
            // not inflate the count, or learning-heavy sessions would score worse on efficiency.
            if (!META_EVENT_ACTIONS.contains(evt.Action_Name__c)) {
                session.actions_taken__c = (session.actions_taken__c != null ? session.actions_taken__c : 0) + 1;
            } else if (session.actions_taken__c == null) {
                session.actions_taken__c = 0;
            }
            session.final_points__c = newCumulative;
            if (evt.Topic_Area__c != null) {
                session.primary_topic__c = evt.Topic_Area__c;
            }

            // Track final outcome (last outcome wins)
            if (evt.Outcome__c == 'success') {
                session.final_outcome__c = 'success';
            } else if (evt.Outcome__c == 'failure' && session.final_outcome__c != 'success') {
                session.final_outcome__c = 'failure';
            } else if (session.final_outcome__c == null) {
                session.final_outcome__c = 'partial';
            }

            // Track lesson usage — count every lesson credited this event
            if (!creditedLessonIds.isEmpty()) {
                session.lessons_applied__c = (session.lessons_applied__c != null ? session.lessons_applied__c : 0) + creditedLessonIds.size();
            }

            // Detect lesson creation (knowledge_creation reward, or legacy Extract_And_Record action name)
            if (evt.Action_Name__c != null &&
                (evt.Action_Name__c == 'knowledge_creation' || evt.Action_Name__c.contains('Extract_And_Record'))) {
                session.lessons_created__c = (session.lessons_created__c != null ? session.lessons_created__c : 0) + 1;
            }

            sessionsToUpsert.add(evt.Session_Id__c);
        }

        // Step 8: Compute per-session breakdown (informational) and collect affected agents.
        // The headline aes_score__c is CUMULATIVE and is set in Step 10b after the chain is
        // re-summed in chronological order — it is NOT goal+efficiency+learning per session.
        Set<String> affectedAgents = new Set<String>();
        for (String sessionId : sessionsToUpsert) {
            AgentSession__c session = sessionMap.get(sessionId);
            if (session != null) {
                Integer optimalActions = 3;
                if (session.primary_topic__c != null && session.agent_api_name__c != null) {
                    String optKey = session.agent_api_name__c + '|' + session.primary_topic__c;
                    if (optimalActionsMap.containsKey(optKey)) {
                        optimalActions = optimalActionsMap.get(optKey);
                    }
                }

                Boolean lessonApplied = session.lessons_applied__c != null && session.lessons_applied__c > 0;
                Boolean lessonSuccessful = lessonApplied && session.final_outcome__c == 'success';
                Boolean lessonCreated = session.lessons_created__c != null && session.lessons_created__c > 0;

                Map<String, Decimal> aes = AesCalculator.calculateAes(
                    session.final_outcome__c,
                    session.actions_taken__c != null ? Integer.valueOf(session.actions_taken__c) : 0,
                    optimalActions,
                    lessonApplied,
                    lessonSuccessful,
                    lessonCreated
                );

                // Informational per-session breakdown (drives the console's AES Breakdown widget).
                session.aes_goal__c = aes.get('aes_goal');
                session.aes_efficiency__c = aes.get('aes_efficiency');
                session.aes_learning__c = aes.get('aes_learning');

                if (session.agent_api_name__c != null) {
                    affectedAgents.add(session.agent_api_name__c);
                }
            }
        }

        // Step 9: Bulk insert outcomes
        if (!outcomesToInsert.isEmpty()) {
            insert outcomesToInsert;
        }

        // Step 10: Bulk upsert sessions (persists this run's lessons_applied / outcome / breakdown)
        if (!sessionsToUpsert.isEmpty()) {
            List<AgentSession__c> sessionsToSave = new List<AgentSession__c>();
            for (String sessionId : sessionsToUpsert) {
                sessionsToSave.add(sessionMap.get(sessionId));
            }
            upsert sessionsToSave session_id__c;
        }

        // Step 10b: Recompute the CUMULATIVE AES for every affected agent.
        // aes_score__c on each session = running total (in chronological order) of each
        // session's lesson-application contribution. So AES only rises as the agent is used
        // and successfully applies lessons — a single, cross-agent-comparable effectiveness curve.
        recomputeCumulativeAes(affectedAgents);

        // Step 11: Bulk update lessons
        if (!lessonsToUpdate.isEmpty()) {
            List<AgentLessonLearned__c> lessonsToSave = new List<AgentLessonLearned__c>();
            for (Id lessonId : lessonsToUpdate) {
                lessonsToSave.add(lessonsMap.get(lessonId));
            }
            update lessonsToSave;
        }
    }

    private static String buildConfigKey(String agentApiName, String actionName, String topicArea) {
        return (agentApiName != null ? agentApiName : '') + '|' + actionName + '|' + topicArea;
    }

    /**
     * @description Recomputes the cumulative AES curve for the given agents. For each agent,
     *              its sessions are walked in chronological order and aes_score__c is set to
     *              the running total of each session's lesson-application contribution
     *              (applied+successful +15, applied+unsuccessful +5, none 0). Only sessions
     *              whose cumulative value actually changes are updated.
     */
    private static void recomputeCumulativeAes(Set<String> agentApiNames) {
        if (agentApiNames == null || agentApiNames.isEmpty()) {
            return;
        }
        List<AgentSession__c> ordered = [
            SELECT Id, agent_api_name__c, final_outcome__c, lessons_applied__c, aes_score__c
            FROM AgentSession__c
            WHERE agent_api_name__c IN :agentApiNames
            WITH SECURITY_ENFORCED
            ORDER BY agent_api_name__c ASC, start_time__c ASC, CreatedDate ASC
        ];

        Map<String, Decimal> runningTotal = new Map<String, Decimal>();
        List<AgentSession__c> toUpdate = new List<AgentSession__c>();
        for (AgentSession__c s : ordered) {
            Boolean lessonApplied = s.lessons_applied__c != null && s.lessons_applied__c > 0;
            Boolean lessonSuccessful = lessonApplied && s.final_outcome__c == 'success';
            Decimal prior = runningTotal.containsKey(s.agent_api_name__c) ? runningTotal.get(s.agent_api_name__c) : 0;
            Decimal cumulative = prior + AesCalculator.sessionLessonContribution(lessonApplied, lessonSuccessful);
            runningTotal.put(s.agent_api_name__c, cumulative);

            if (s.aes_score__c != cumulative) {
                s.aes_score__c = cumulative;
                toUpdate.add(s);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    // Parse a comma-separated Lesson_Id__c field into a de-duplicated list of valid SF IDs.
    private static List<Id> parseLessonIds(String rawValue) {
        List<Id> result = new List<Id>();
        if (String.isBlank(rawValue)) {
            return result;
        }
        Set<Id> seen = new Set<Id>();
        for (String idStr : rawValue.split(',')) {
            String trimmed = idStr.trim();
            if (String.isBlank(trimmed) || trimmed.length() < 15) {
                continue;
            }
            try {
                Id parsed = Id.valueOf(trimmed);
                if (!seen.contains(parsed)) {
                    seen.add(parsed);
                    result.add(parsed);
                }
            } catch (System.StringException e) {
                // Not a valid ID — skip
            }
        }
        return result;
    }

    /**
     * Composes the canonical Action_Name__c for events that report a RAW domain
     * event + category, by classifying the domain event through the subagent's
     * AgentSubagentConfig.outcome_mapping_json. The agent reports WHAT happened;
     * the platform decides what it MEANS, configurable from the SIA Console.
     *
     * Composition (category + classified outcome):
     *   lesson   + success  -> lesson_applied_success
     *   lesson   + failure  -> lesson_applied_failure
     *   goal     + success  -> goal_success
     *   goal     + partial  -> goal_partial
     *   goal     + failure  -> goal_failure
     *   creation + (any)    -> knowledge_creation   (creation is not pass/fail)
     *
     * Events with a blank Domain_Event__c are left untouched (pre-classified
     * Action_Name__c passes through) so the change is backward-compatible and
     * each layer can deploy independently.
     */
    private static void resolveActionNames(List<AgentReward__e> events) {
        // Bulk-load subagent mappings for every (agent, topic) that reports a raw event.
        List<ClassifyAgentOutcome.Request> classReqs = new List<ClassifyAgentOutcome.Request>();
        List<AgentReward__e> rawEvents = new List<AgentReward__e>();
        for (AgentReward__e evt : events) {
            if (String.isBlank(evt.Domain_Event__c)) {
                continue; // already carries a literal Action_Name__c
            }
            ClassifyAgentOutcome.Request req = new ClassifyAgentOutcome.Request();
            req.agent_api_name = evt.Agent_Api_Name__c;
            req.topic_area = evt.Topic_Area__c;
            req.domain_event = evt.Domain_Event__c;
            classReqs.add(req);
            rawEvents.add(evt);
        }
        if (rawEvents.isEmpty()) {
            return;
        }

        List<ClassifyAgentOutcome.Result> classResults = ClassifyAgentOutcome.classify(classReqs);

        for (Integer i = 0; i < rawEvents.size(); i++) {
            AgentReward__e evt = rawEvents[i];
            String outcomeClass = (classResults != null && i < classResults.size())
                ? classResults[i].outcome_class : null;
            String category = evt.Reward_Category__c == null
                ? '' : evt.Reward_Category__c.trim().toLowerCase();

            String composed = composeActionName(category, outcomeClass);
            if (String.isNotBlank(composed)) {
                evt.Action_Name__c = composed;
                // Mirror the resolved outcome onto Outcome__c (required on the outcome record).
                if (String.isNotBlank(outcomeClass) && outcomeClass != 'unknown') {
                    evt.Outcome__c = outcomeClass;
                } else if (category == 'creation') {
                    // Creation is a positive bookkeeping event with no pass/fail dimension.
                    evt.Outcome__c = 'success';
                }
                // For applied-lesson reports, DERIVE helpfulness from the classified
                // outcome — the platform decides, not the agent. A single agent action
                // (report_lesson_outcome) reports the raw event; success => helpful.
                if (category == 'lesson') {
                    evt.Lesson_Was_Helpful__c = (outcomeClass == 'success');
                }
            }
            // If we cannot compose (unknown class / unrecognized category), leave
            // the event's existing Action_Name__c as-is.
        }
    }

    private static String composeActionName(String category, String outcomeClass) {
        if (category == 'creation') {
            return 'knowledge_creation';
        }
        if (String.isBlank(outcomeClass) || outcomeClass == 'unknown') {
            return null;
        }
        if (category == 'lesson') {
            if (outcomeClass == 'success') return 'lesson_applied_success';
            if (outcomeClass == 'failure') return 'lesson_applied_failure';
            return null;
        }
        if (category == 'goal') {
            if (outcomeClass == 'success') return 'goal_success';
            if (outcomeClass == 'partial') return 'goal_partial';
            if (outcomeClass == 'failure') return 'goal_failure';
            return null;
        }
        return null;
    }
}