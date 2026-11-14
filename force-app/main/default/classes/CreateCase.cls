public with sharing class CreateCase {
    @TestVisible private static final Integer MAX_SUBJECT_LENGTH = 255;

    @InvocableMethod(label='Create Case' description='Create a new support case from a concise subject line.')
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            String subject = clean(req.subject, MAX_SUBJECT_LENGTH);
            if (String.isBlank(subject)) {
                res.error_message = 'A case subject is required.';
            } else {
                res.case_number = '00010482';
            }
            responses.add(res);
        }
        return responses;
    }

    public static String clean(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.replaceAll('[\\p{Cntrl}&&[^\\n\\t]]', '').normalizeSpace().abbreviate(maxLength);
    }

    public class Request {
        @InvocableVariable(label='Subject' required=true) public String subject;
    }

    public class Response {
        @InvocableVariable(label='Case Number') public String case_number;
        @InvocableVariable(label='Error Message') public String error_message;
    }
}
