/**
 * Single-step replacement for the Check_Lessons_Learned flow's two-stage
 * pool-then-rank logic. Returns the formatted top-N lesson context for the
 * agent's reasoning prompt.
 *
 * Stage 1 — pool: SOQL AgentLessonLearned__c by agent + topic + min_confidence,
 *                 sorted DESC by confidence_score__c, capped at pool_size from
 *                 AgentImprovementConfig__c.
 * Stage 2 — rank: invokes prompt template Select_Relevant_Lessons with the pool;
 *                 hard-caps the returned id list at max_lessons.
 * Fallback: when the prompt template returns null/empty/unparsable, returns the
 *           top-max_lessons of the pool by confidence (graceful degradation).
 */
public with sharing class SelectRelevantLessons {

    private static final String PT_NAME = 'Select_Relevant_Lessons';
    private static final Integer DEFAULT_POOL_SIZE = 20;
    private static final Decimal DEFAULT_MIN_CONFIDENCE = 0.8;
    private static final Integer DEFAULT_MAX_LESSONS = 3;

    public class Request {
        @InvocableVariable(required=true)
        public String agent_api_name;

        @InvocableVariable(required=true)
        public String topic_area;

        @InvocableVariable(required=true)
        public String user_message;

        @InvocableVariable
        public Decimal max_lessons;
    }

    public class Result {
        @InvocableVariable
        public String lessons;

        @InvocableVariable
        public String lesson_ids;

        @InvocableVariable
        public Decimal lesson_count;
    }

    @InvocableMethod(label='Select Relevant Lessons' description='Loads lesson pool, ranks via prompt template, returns top-N formatted context')
    public static List<Result> selectLessons(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request req : requests) {
            out.add(processOne(req));
        }
        return out;
    }

    private static Result processOne(Request req) {
        Result res = new Result();
        res.lessons = '';
        res.lesson_ids = '';
        res.lesson_count = 0;

        Integer maxLessons = (req.max_lessons != null && req.max_lessons > 0)
            ? Integer.valueOf(req.max_lessons)
            : DEFAULT_MAX_LESSONS;

        // Resolve config (pool size + min confidence) with safe defaults.
        Integer poolSize = DEFAULT_POOL_SIZE;
        Decimal minConfidence = DEFAULT_MIN_CONFIDENCE;
        for (AgentImprovementConfig__c cfg : [
            SELECT lesson_selection_pool_size__c, lesson_selection_min_confidence__c
            FROM AgentImprovementConfig__c
            WHERE agent_api_name__c = :req.agent_api_name
            LIMIT 1
        ]) {
            if (cfg.lesson_selection_pool_size__c != null && cfg.lesson_selection_pool_size__c > 0) {
                poolSize = Integer.valueOf(cfg.lesson_selection_pool_size__c);
            }
            if (cfg.lesson_selection_min_confidence__c != null) {
                minConfidence = cfg.lesson_selection_min_confidence__c;
            }
        }

        // Stage 1 — pool capped by SOQL LIMIT.
        List<AgentLessonLearned__c> pool = [
            SELECT Id, lesson_text__c, confidence_score__c, categories__c
            FROM AgentLessonLearned__c
            WHERE agent_api_name__c = :req.agent_api_name
              AND topic_area__c = :req.topic_area
              AND confidence_score__c >= :minConfidence
              AND is_archived__c = false
            ORDER BY confidence_score__c DESC
            LIMIT :poolSize
        ];

        if (pool.isEmpty()) {
            return res;
        }

        Map<Id, AgentLessonLearned__c> poolById = new Map<Id, AgentLessonLearned__c>(pool);
        String poolJson = buildPoolJson(pool);

        // Stage 2 — ask the prompt template to semantically rank the pool.
        //   null        => the ranker genuinely FAILED (exception / blank / unparseable)
        //   empty list  => the ranker SUCCEEDED and judged NO lesson relevant ("[]")
        //   non-empty   => the relevant lesson ids
        List<Id> selectedIds = invokeRanker(req.user_message, poolJson, poolById.keySet());

        // Fail CLOSED: a successful "none relevant" ([]) must surface nothing — do NOT
        // re-add lessons the ranker rejected. Only fall back to confidence ranking when
        // the ranker hard-failed (null), so a transient PT error still degrades gracefully.
        if (selectedIds == null) {
            selectedIds = new List<Id>();
            for (Integer i = 0; i < pool.size() && i < maxLessons; i++) {
                selectedIds.add(pool[i].Id);
            }
        }
        if (selectedIds.isEmpty()) {
            // Ranker succeeded and found nothing relevant — return empty result.
            return res;
        }

        // Hard-cap at max_lessons regardless of what the LLM returned.
        if (selectedIds.size() > maxLessons) {
            selectedIds = new List<Id>(selectedIds);
            List<Id> trimmed = new List<Id>();
            for (Integer i = 0; i < maxLessons; i++) trimmed.add(selectedIds[i]);
            selectedIds = trimmed;
        }

        // Format the agent-facing string.
        List<String> idStrings = new List<String>();
        String formatted = '';
        for (Id lessonId : selectedIds) {
            AgentLessonLearned__c l = poolById.get(lessonId);
            if (l == null) continue;
            idStrings.add(String.valueOf(lessonId));
            formatted += '[' + lessonId + '] ' + l.lesson_text__c + ' (' + l.confidence_score__c + '); ';
        }
        res.lesson_ids = String.join(idStrings, ',');
        res.lessons = formatted;
        res.lesson_count = idStrings.size();
        return res;
    }

    private static String buildPoolJson(List<AgentLessonLearned__c> pool) {
        List<Map<String, Object>> entries = new List<Map<String, Object>>();
        for (AgentLessonLearned__c l : pool) {
            entries.add(new Map<String, Object>{
                'id' => String.valueOf(l.Id),
                'text' => l.lesson_text__c,
                'categories' => l.categories__c,
                'confidence' => String.valueOf(l.confidence_score__c)
            });
        }
        return JSON.serialize(entries);
    }

    /**
     * Calls the prompt template and parses its response into a list of lesson Ids
     * that exist in the pool. Returns null on any failure.
     */
    private static List<Id> invokeRanker(String userMessage, String poolJson, Set<Id> validIds) {
        try {
            ConnectApi.WrappedValue userMsgWrap = new ConnectApi.WrappedValue();
            userMsgWrap.value = userMessage;
            ConnectApi.WrappedValue poolWrap = new ConnectApi.WrappedValue();
            poolWrap.value = poolJson;

            ConnectApi.EinsteinPromptTemplateGenerationsInput body =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            body.inputParams = new Map<String, ConnectApi.WrappedValue>{
                'Input:user_message' => userMsgWrap,
                'Input:lesson_pool_json' => poolWrap
            };
            body.isPreview = false;
            body.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            body.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation resp =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(PT_NAME, body);

            if (resp?.generations == null || resp.generations.isEmpty()) return null;
            String raw = resp.generations[0].text;
            if (String.isBlank(raw)) return null;
            return parseRankerJson(raw, validIds);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'SelectRelevantLessons|ranker failed: ' + e.getTypeName() + ': ' + e.getMessage());
            return null;
        }
    }

    /**
     * Parses the prompt template response. Accepts either:
     *   [{"id":"...", "relevance_reason":"..."}, ...]
     *   {"selected_ids": ["...", "..."]}
     *   ```json ... ``` fenced versions of either
     * Returns only ids that exist in validIds.
     */
    @TestVisible
    private static List<Id> parseRankerJson(String raw, Set<Id> validIds) {
        String cleaned = raw.trim();
        if (cleaned.startsWith('```')) {
            cleaned = cleaned.substringAfter('\n');
            if (cleaned.endsWith('```')) cleaned = cleaned.substringBeforeLast('```');
            cleaned = cleaned.trim();
        }
        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(cleaned);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'SelectRelevantLessons|parse failed: ' + e.getMessage());
            return null;
        }
        List<Id> ids = new List<Id>();
        if (parsed instanceof List<Object>) {
            for (Object o : (List<Object>) parsed) {
                if (!(o instanceof Map<String, Object>)) continue;
                String idStr = String.valueOf(((Map<String, Object>) o).get('id'));
                addIfValid(idStr, validIds, ids);
            }
        } else if (parsed instanceof Map<String, Object>) {
            Object selObj = ((Map<String, Object>) parsed).get('selected_ids');
            if (selObj instanceof List<Object>) {
                for (Object o : (List<Object>) selObj) addIfValid(String.valueOf(o), validIds, ids);
            }
        }
        return ids;
    }

    private static void addIfValid(String idStr, Set<Id> validIds, List<Id> out) {
        if (String.isBlank(idStr)) return;
        try {
            Id i = Id.valueOf(idStr);
            if (validIds.contains(i) && !out.contains(i)) out.add(i);
        } catch (Exception e) { /* not a valid Id, ignore */ }
    }
}