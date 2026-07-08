@IsTest
private class SelectRelevantLessons_Test {

    private static final String AGENT = 'Test_Agent';
    private static final String TOPIC = 'knowledge';

    private static void seedConfig(Integer poolSize, Decimal minConfidence) {
        AgentImprovementConfig__c c = new AgentImprovementConfig__c();
        c.agent_api_name__c = AGENT;
        c.lesson_selection_pool_size__c = poolSize;
        c.lesson_selection_min_confidence__c = minConfidence;
        insert c;
    }

    private static List<AgentLessonLearned__c> seedLessons(Integer count) {
        List<AgentLessonLearned__c> lessons = new List<AgentLessonLearned__c>();
        for (Integer i = 0; i < count; i++) {
            AgentLessonLearned__c l = new AgentLessonLearned__c();
            l.agent_api_name__c = AGENT;
            l.topic_area__c = TOPIC;
            l.lesson_text__c = 'Lesson #' + i + ' about thing ' + i;
            l.confidence_score__c = 0.9;
            l.is_archived__c = false;
            l.outcome_type__c = 'Success';
            lessons.add(l);
        }
        insert lessons;
        return lessons;
    }

    private static SelectRelevantLessons.Request makeReq(Decimal maxLessons) {
        SelectRelevantLessons.Request r = new SelectRelevantLessons.Request();
        r.agent_api_name = AGENT;
        r.topic_area = TOPIC;
        r.user_message = 'Where can I find the W9 form?';
        r.max_lessons = maxLessons;
        return r;
    }

    @IsTest
    static void emptyPool_returnsZero() {
        seedConfig(20, 0.8);
        Test.startTest();
        List<SelectRelevantLessons.Result> out = SelectRelevantLessons.selectLessons(
            new List<SelectRelevantLessons.Request>{ makeReq(3) }
        );
        Test.stopTest();
        Assert.areEqual(1, out.size(), 'one result per request');
        Assert.areEqual(0, out[0].lesson_count, 'no lessons → count 0');
        Assert.areEqual('', out[0].lessons);
        Assert.areEqual('', out[0].lesson_ids);
    }

    @IsTest
    static void poolCappedBySoql_thenFallbackTrimmedToMax() {
        // 32 lessons, pool config = 20, ranker will fail in test (no real PT available)
        // → fallback path should return top-N (max_lessons) by confidence.
        seedConfig(20, 0.8);
        seedLessons(32);

        Test.startTest();
        List<SelectRelevantLessons.Result> out = SelectRelevantLessons.selectLessons(
            new List<SelectRelevantLessons.Request>{ makeReq(3) }
        );
        Test.stopTest();

        SelectRelevantLessons.Result r = out[0];
        Assert.areEqual(3, r.lesson_count, 'fallback hard-caps at max_lessons=3');
        Assert.areEqual(3, r.lesson_ids.split(',').size(), 'returned ids match cap');
        Assert.isTrue(r.lessons.length() > 0, 'formatted text is non-empty');
    }

    @IsTest
    static void honorsMaxLessonsInput() {
        seedConfig(20, 0.8);
        seedLessons(10);

        Test.startTest();
        List<SelectRelevantLessons.Result> out = SelectRelevantLessons.selectLessons(
            new List<SelectRelevantLessons.Request>{ makeReq(5) }
        );
        Test.stopTest();

        Assert.areEqual(5, out[0].lesson_count, 'fallback respects max_lessons=5');
    }

    @IsTest
    static void noConfig_usesDefaults() {
        // no AgentImprovementConfig__c row; defaults: pool_size=20, min_confidence=0.8
        seedLessons(5);

        Test.startTest();
        List<SelectRelevantLessons.Result> out = SelectRelevantLessons.selectLessons(
            new List<SelectRelevantLessons.Request>{ makeReq(3) }
        );
        Test.stopTest();

        Assert.areEqual(3, out[0].lesson_count, 'defaults still cap to max_lessons');
    }

    @IsTest
    static void minConfidenceFiltersLowScored() {
        seedConfig(20, 0.95);
        // seeded lessons all use 0.9 → all filtered out
        seedLessons(5);

        Test.startTest();
        List<SelectRelevantLessons.Result> out = SelectRelevantLessons.selectLessons(
            new List<SelectRelevantLessons.Request>{ makeReq(3) }
        );
        Test.stopTest();

        Assert.areEqual(0, out[0].lesson_count, 'all lessons below min_confidence → empty');
    }

    // ---- Ranker-result semantics: empty "[]" (none relevant) vs failure (null) ----
    // These lock in the fail-closed fix: a successful "none relevant" must NOT be
    // treated as a failure and must surface zero lessons.

    @IsTest
    static void rankerEmptyArray_parsesToEmptyNotNull() {
        // PT legitimately judged nothing relevant -> "[]" must parse to an empty list
        // (a real, non-null answer), which processOne treats as "surface nothing".
        Set<Id> validIds = new Set<Id>();
        List<Id> result = SelectRelevantLessons.parseRankerJson('[]', validIds);
        Assert.areNotEqual(null, result, 'empty array is a successful result, not a failure');
        Assert.areEqual(0, result.size(), 'no ids selected');
    }

    @IsTest
    static void rankerSelectsOnlyValidPoolIds() {
        // Ranker output is filtered to ids actually in the pool.
        List<AgentLessonLearned__c> seeded = seedLessons(2);
        Set<Id> validIds = new Set<Id>{ seeded[0].Id };
        String raw = '[{"id":"' + seeded[0].Id + '","relevance_reason":"match"},'
                   + '{"id":"' + seeded[1].Id + '","relevance_reason":"in pool but not passed as valid"}]';
        List<Id> result = SelectRelevantLessons.parseRankerJson(raw, validIds);
        Assert.areEqual(1, result.size(), 'only ids in validIds are kept');
        Assert.areEqual(seeded[0].Id, result[0], 'kept the valid id');
    }

    @IsTest
    static void rankerFencedJson_isParsed() {
        // Markdown-fenced ```json [...] ``` must still parse.
        List<AgentLessonLearned__c> seeded = seedLessons(1);
        Set<Id> validIds = new Set<Id>{ seeded[0].Id };
        String raw = '```json\n[{"id":"' + seeded[0].Id + '"}]\n```';
        List<Id> result = SelectRelevantLessons.parseRankerJson(raw, validIds);
        Assert.areEqual(1, result.size(), 'fenced json parses');
    }
}