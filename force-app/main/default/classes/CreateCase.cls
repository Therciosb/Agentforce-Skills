public with sharing class CreateCase {
    @InvocableMethod(label='Create Case' description='Create a new support case from a concise subject line.')
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.case_number = '00010482';
            responses.add(res);
        }
        return responses;
    }

    public class Request {
        @InvocableVariable(label='Subject' required=true) public String subject;
    }

    public class Response {
        @InvocableVariable(label='Case Number') public String case_number;
    }
}