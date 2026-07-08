public with sharing class LessonRelevanceParser {

    public class ParseRequest {
        @InvocableVariable(required=true)
        public String jsonResponse;

        @InvocableVariable(required=true)
        public String lessonPoolJson;
    }

    public class ParseResult {
        @InvocableVariable
        public String selectedLessonIds;

        @InvocableVariable
        public String selectedLessonsText;

        @InvocableVariable
        public Decimal selectedCount;
    }

    @InvocableMethod(label='Parse Lesson Relevance Response' description='Parses Stage 2 PT response and returns filtered lessons text for agent instructions')
    public static List<ParseResult> parseRelevanceResponse(List<ParseRequest> requests) {
        List<ParseResult> results = new List<ParseResult>();
        for (ParseRequest req : requests) {
            results.add(processRequest(req));
        }
        return results;
    }

    private static ParseResult processRequest(ParseRequest req) {
        ParseResult res = new ParseResult();
        res.selectedLessonIds = '';
        res.selectedLessonsText = '';
        res.selectedCount = 0;

        if (String.isBlank(req.jsonResponse) || String.isBlank(req.lessonPoolJson)) {
            return res;
        }

        try {
            String cleaned = req.jsonResponse.trim();
            if (cleaned.startsWith('```')) {
                cleaned = cleaned.substringAfter('\n');
                if (cleaned.endsWith('```')) {
                    cleaned = cleaned.substringBeforeLast('```');
                }
                cleaned = cleaned.trim();
            }

            Set<String> selectedIds = new Set<String>();
            Object parsed = JSON.deserializeUntyped(cleaned);

            if (parsed instanceof List<Object>) {
                for (Object item : (List<Object>) parsed) {
                    Map<String, Object> entry = (Map<String, Object>) item;
                    String id = String.valueOf(entry.get('id'));
                    if (String.isNotBlank(id)) {
                        selectedIds.add(id);
                    }
                }
            } else if (parsed instanceof Map<String, Object>) {
                Map<String, Object> mapResult = (Map<String, Object>) parsed;
                if (mapResult.containsKey('selected_ids')) {
                    for (Object idObj : (List<Object>) mapResult.get('selected_ids')) {
                        selectedIds.add(String.valueOf(idObj));
                    }
                }
            }

            if (selectedIds.isEmpty()) {
                return res;
            }

            Map<String, Map<String, Object>> poolMap = buildPoolMap(req.lessonPoolJson);

            List<String> idList = new List<String>();
            String lessonsOutput = '';
            for (String id : selectedIds) {
                Map<String, Object> lesson = poolMap.get(id);
                if (lesson != null) {
                    idList.add(id);
                    String text = String.valueOf(lesson.get('text'));
                    String confidence = String.valueOf(lesson.get('confidence'));
                    lessonsOutput += '[' + id + '] ' + text + ' (' + confidence + '); ';
                }
            }

            res.selectedLessonIds = String.join(idList, ',');
            res.selectedLessonsText = lessonsOutput;
            res.selectedCount = idList.size();
        } catch (Exception e) {
            res.selectedLessonsText = '';
            res.selectedCount = 0;
        }

        return res;
    }

    private static Map<String, Map<String, Object>> buildPoolMap(String poolJson) {
        Map<String, Map<String, Object>> poolMap = new Map<String, Map<String, Object>>();
        String cleaned = poolJson.trim();
        if (cleaned.endsWith(',]')) {
            cleaned = cleaned.substring(0, cleaned.length() - 2) + ']';
        }
        try {
            List<Object> pool = (List<Object>) JSON.deserializeUntyped(cleaned);
            for (Object item : pool) {
                Map<String, Object> lesson = (Map<String, Object>) item;
                String id = String.valueOf(lesson.get('id'));
                poolMap.put(id, lesson);
            }
        } catch (Exception e) {
            // Pool parse failure - return empty map
        }
        return poolMap;
    }
}