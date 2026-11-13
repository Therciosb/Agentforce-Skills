public with sharing class FetchSupportHistory {
    @InvocableMethod(label='Fetch Support History' description='Fetch the support/case history for a user.')
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.history_summary = 'Case #00001001 (Closed): Billing inquiry resolved. Case #00001024 (In Progress): Hardware replacement initiated.';
            responses.add(res);
        }
        return responses;
    }

    public class Request {
        @InvocableVariable(label='User ID') public String user_id;
    }

    public class Response {
        @InvocableVariable(label='History Summary') public String history_summary;
    }
}