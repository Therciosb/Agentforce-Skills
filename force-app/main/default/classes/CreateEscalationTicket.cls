public with sharing class CreateEscalationTicket {
    @InvocableMethod(label='Create Escalation Ticket' description='Create an escalation ticket for handoff to a human specialist.')
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.ticket_id = 'ESC-88392';
            responses.add(res);
        }
        return responses;
    }

    public class Request {
        @InvocableVariable(label='Customer ID') public String customer_id;
        @InvocableVariable(label='Issue Description') public String issue_description;
        @InvocableVariable(label='Issue Type') public String issue_type;
    }

    public class Response {
        @InvocableVariable(label='Ticket ID') public String ticket_id;
    }
}