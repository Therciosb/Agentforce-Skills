public with sharing class FetchAccountData {
    @InvocableMethod(label='Fetch Account Data' description='Fetch account details for a user.')
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.account_name = 'Acme Corp';
            res.account_tier = 'Gold Partner';
            res.contact_email = 'customer@example.com';
            responses.add(res);
        }
        return responses;
    }

    public class Request {
        @InvocableVariable(label='User ID') public String user_id;
    }

    public class Response {
        @InvocableVariable(label='Account Name') public String account_name;
        @InvocableVariable(label='Account Tier') public String account_tier;
        @InvocableVariable(label='Contact Email') public String contact_email;
    }
}