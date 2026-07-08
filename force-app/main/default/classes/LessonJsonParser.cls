public with sharing class LessonJsonParser {
    
    public class ParseRequest {
        @InvocableVariable(required=true)
        public String jsonResponse;
    }
    
    public class ParseResult {
        @InvocableVariable
        public Boolean shouldRecord;
        @InvocableVariable
        public String lessonText;
        @InvocableVariable
        public String categories;
    }
    
    @InvocableMethod(label='Parse Lesson JSON' description='Parses the PT JSON response to extract lesson_text, categories, and record flag')
    public static List<ParseResult> parseLessonJson(List<ParseRequest> requests) {
        List<ParseResult> results = new List<ParseResult>();
        for (ParseRequest req : requests) {
            ParseResult res = new ParseResult();
            res.shouldRecord = false;
            res.lessonText = '';
            res.categories = '';
            
            if (String.isBlank(req.jsonResponse)) {
                results.add(res);
                continue;
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
                
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(cleaned);
                Object recordVal = parsed.get('record');
                if (recordVal instanceof Boolean) {
                    res.shouldRecord = (Boolean) recordVal;
                } else if (recordVal instanceof String) {
                    res.shouldRecord = ((String) recordVal).equalsIgnoreCase('true');
                }
                res.lessonText = parsed.containsKey('lesson_text') ? String.valueOf(parsed.get('lesson_text')) : '';
                res.categories = parsed.containsKey('categories') ? String.valueOf(parsed.get('categories')) : '';
            } catch (Exception e) {
                res.shouldRecord = true;
                res.lessonText = req.jsonResponse;
                res.categories = '';
            }
            results.add(res);
        }
        return results;
    }
}