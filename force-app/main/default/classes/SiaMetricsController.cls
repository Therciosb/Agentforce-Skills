public with sharing class SiaMetricsController {

    @AuraEnabled
    public static Map<String, Object> getAgentMetrics(String agentApiName, Integer periodWeeks) {
        Map<String, Object> result = new Map<String, Object>();
        if (String.isBlank(agentApiName) || periodWeeks == null || periodWeeks <= 0) {
            result.put('aesAvg', 0);
            result.put('improvementRate', 0);
            result.put('sessionCount', 0);
            result.put('promotedLessonCount', 0);
            return result;
        }

        DateTime startDate = DateTime.now().addDays(-periodWeeks * 7);

        List<AggregateResult> sessionAgg = [
            SELECT AVG(aes_score__c) aesAvg, COUNT(Id) sessionCount
            FROM AgentSession__c
            WHERE agent_api_name__c = :agentApiName
              AND start_time__c >= :startDate
            WITH SECURITY_ENFORCED
        ];

        Decimal aesAvg = 0;
        Integer sessionCount = 0;
        if (!sessionAgg.isEmpty()) {
            Object avgVal = sessionAgg[0].get('aesAvg');
            aesAvg = avgVal != null ? (Decimal) avgVal : 0;
            sessionCount = (Integer) sessionAgg[0].get('sessionCount');
        }

        // Improvement rate: split the period's sessions by CHRONOLOGICAL ORDER
        // (first half vs second half), not by a fixed calendar midpoint.
        // The calendar split returned 0 whenever sessions clustered in time
        // (the first half was empty). null signals "not enough data" so the
        // UI can show "—" instead of a misleading 0%.
        Object improvementRate = null;
        if (sessionCount >= 2) {
            List<AgentSession__c> orderedSessions = [
                SELECT aes_score__c
                FROM AgentSession__c
                WHERE agent_api_name__c = :agentApiName
                  AND start_time__c >= :startDate
                  AND aes_score__c != null
                WITH SECURITY_ENFORCED
                ORDER BY start_time__c ASC
            ];
            Integer n = orderedSessions.size();
            if (n >= 2) {
                Integer half = n / 2;            // first `half` vs the remaining `n-half`
                Decimal firstSum = 0, secondSum = 0;
                for (Integer i = 0; i < n; i++) {
                    Decimal s = orderedSessions[i].aes_score__c;
                    if (i < half) { firstSum += s; } else { secondSum += s; }
                }
                Decimal firstAvg = firstSum / half;
                Decimal secondAvg = secondSum / (n - half);
                if (firstAvg > 0) {
                    improvementRate = ((secondAvg - firstAvg) / firstAvg * 100).setScale(1);
                }
            }
        }

        Integer promotedCount = [
            SELECT COUNT()
            FROM AgentLessonLearned__c
            WHERE agent_api_name__c = :agentApiName
              AND is_promoted__c = TRUE
              AND is_archived__c = FALSE
            WITH SECURITY_ENFORCED
        ];

        result.put('aesAvg', aesAvg);
        result.put('improvementRate', improvementRate);
        result.put('sessionCount', sessionCount);
        // AES Breakdown averages
        List<AggregateResult> breakdownAgg = [
            SELECT AVG(aes_goal__c) avgGoal, AVG(aes_efficiency__c) avgEff, AVG(aes_learning__c) avgLearn
            FROM AgentSession__c
            WHERE agent_api_name__c = :agentApiName
              AND start_time__c >= :startDate
            WITH SECURITY_ENFORCED
        ];
        Decimal goalAvg = 0, efficiencyAvg = 0, learningAvg = 0;
        if (!breakdownAgg.isEmpty()) {
            Object g = breakdownAgg[0].get('avgGoal');
            Object e = breakdownAgg[0].get('avgEff');
            Object l = breakdownAgg[0].get('avgLearn');
            goalAvg = g != null ? (Decimal) g : 0;
            efficiencyAvg = e != null ? (Decimal) e : 0;
            learningAvg = l != null ? (Decimal) l : 0;
        }
        result.put('goalScore', goalAvg);
        result.put('efficiencyScore', efficiencyAvg);
        result.put('learningScore', learningAvg);

        result.put('promotedLessonCount', promotedCount);
        return result;
    }

    @AuraEnabled
    public static List<Map<String, Object>> getAesTrend(String agentApiName, Integer periodWeeks) {
        List<Map<String, Object>> trend = new List<Map<String, Object>>();
        if (String.isBlank(agentApiName) || periodWeeks == null || periodWeeks <= 0) {
            return trend;
        }

        DateTime startDate = DateTime.now().addDays(-periodWeeks * 7);

        List<AgentSession__c> sessions = [
            SELECT aes_score__c, start_time__c
            FROM AgentSession__c
            WHERE agent_api_name__c = :agentApiName
              AND start_time__c >= :startDate
              AND aes_score__c != NULL
            WITH SECURITY_ENFORCED
            ORDER BY start_time__c ASC
        ];

        if (sessions.isEmpty()) {
            return trend;
        }

        // Adaptive bucketing: weekly buckets are too coarse when activity is
        // clustered in time (all sessions land in one week -> one point -> no
        // line renders). If the data spans fewer than 2 weeks, bucket by DAY so
        // the trend still has multiple points.
        Date firstDay = sessions[0].start_time__c.date();
        Date lastDay = sessions[sessions.size() - 1].start_time__c.date();
        Integer spanDays = firstDay.daysBetween(lastDay);
        Boolean byDay = spanDays < 14;

        // Preserve chronological bucket order with a parallel key list.
        Map<Integer, List<Decimal>> bucketScores = new Map<Integer, List<Decimal>>();
        Map<Integer, String> bucketLabel = new Map<Integer, String>();
        List<Integer> bucketOrder = new List<Integer>();

        for (AgentSession__c s : sessions) {
            Integer daysFromFirst = firstDay.daysBetween(s.start_time__c.date());
            Integer bucket = byDay ? daysFromFirst : (daysFromFirst / 7);
            if (!bucketScores.containsKey(bucket)) {
                bucketScores.put(bucket, new List<Decimal>());
                bucketOrder.add(bucket);
                Date bucketDate = s.start_time__c.date();
                bucketLabel.put(bucket, byDay
                    ? (bucketDate.month() + '/' + bucketDate.day())
                    : ('W' + (bucket + 1)));
            }
            bucketScores.get(bucket).add(s.aes_score__c);
        }

        bucketOrder.sort();
        for (Integer b : bucketOrder) {
            List<Decimal> scores = bucketScores.get(b);
            Decimal sum = 0;
            for (Decimal sc : scores) {
                sum += sc;
            }
            Map<String, Object> entry = new Map<String, Object>();
            entry.put('week', bucketLabel.get(b));
            entry.put('aesAvg', (sum / scores.size()).setScale(1));
            trend.add(entry);
        }
        return trend;
    }

    @AuraEnabled
    public static Map<String, Decimal> getKnowledgeHealth(String agentApiName) {
        Map<String, Decimal> health = new Map<String, Decimal>();
        health.put('yield', (Decimal) 0);
        health.put('utilization', (Decimal) 0);
        health.put('accuracy', (Decimal) 0);

        if (String.isBlank(agentApiName)) {
            return health;
        }

        // Yield: promoted / total lessons
        Integer totalLessons = [
            SELECT COUNT() FROM AgentLessonLearned__c
            WHERE agent_api_name__c = :agentApiName AND is_archived__c = FALSE
            WITH SECURITY_ENFORCED
        ];
        Integer promotedLessons = [
            SELECT COUNT() FROM AgentLessonLearned__c
            WHERE agent_api_name__c = :agentApiName AND is_promoted__c = TRUE AND is_archived__c = FALSE
            WITH SECURITY_ENFORCED
        ];
        if (totalLessons > 0) {
            health.put('yield', (Decimal.valueOf(promotedLessons) / Decimal.valueOf(totalLessons)) * 100);
        }

        // Utilization: sessions with lessons applied / total sessions
        Integer totalSessions = [
            SELECT COUNT() FROM AgentSession__c
            WHERE agent_api_name__c = :agentApiName
            WITH SECURITY_ENFORCED
        ];
        Integer sessionsWithLessons = [
            SELECT COUNT() FROM AgentSession__c
            WHERE agent_api_name__c = :agentApiName AND lessons_applied__c > 0
            WITH SECURITY_ENFORCED
        ];
        if (totalSessions > 0) {
            health.put('utilization', (Decimal.valueOf(sessionsWithLessons) / Decimal.valueOf(totalSessions)) * 100);
        }

        // Accuracy: outcomes where lesson was helpful / total outcomes with lesson
        Integer totalWithLesson = [
            SELECT COUNT() FROM AgentActionOutcome__c
            WHERE agent_api_name__c = :agentApiName AND lesson_linked__c != NULL
            WITH SECURITY_ENFORCED
        ];
        Integer helpfulWithLesson = [
            SELECT COUNT() FROM AgentActionOutcome__c
            WHERE agent_api_name__c = :agentApiName AND lesson_linked__c != NULL AND lesson_was_helpful__c = TRUE
            WITH SECURITY_ENFORCED
        ];
        if (totalWithLesson > 0) {
            health.put('accuracy', (Decimal.valueOf(helpfulWithLesson) / Decimal.valueOf(totalWithLesson)) * 100);
        }

        return health;
    }

    @AuraEnabled
    public static List<Map<String, Object>> getAgentSummaries(List<String> agentApiNames) {
        List<Map<String, Object>> summaries = new List<Map<String, Object>>();
        if (agentApiNames == null || agentApiNames.isEmpty()) {
            return summaries;
        }

        for (String agentName : agentApiNames) {
            Map<String, Object> metrics = getAgentMetrics(agentName, 4);
            Map<String, Decimal> kh = getKnowledgeHealth(agentName);
            Map<String, Object> summary = new Map<String, Object>();
            summary.put('agentApiName', agentName);
            summary.put('aesAvg', metrics.get('aesAvg'));
            summary.put('improvementRate', metrics.get('improvementRate'));
            summary.put('yield', kh.get('yield'));
            summary.put('utilization', kh.get('utilization'));
            summary.put('accuracy', kh.get('accuracy'));
            summaries.add(summary);
        }
        return summaries;
    }

    @AuraEnabled
    public static Map<String, List<Map<String, Object>>> getAesTrends(List<String> agentApiNames, Integer periodWeeks) {
        Map<String, List<Map<String, Object>>> trends = new Map<String, List<Map<String, Object>>>();
        if (agentApiNames == null || agentApiNames.isEmpty()) {
            return trends;
        }
        for (String agentName : agentApiNames) {
            trends.put(agentName, getAesTrend(agentName, periodWeeks));
        }
        return trends;
    }
}