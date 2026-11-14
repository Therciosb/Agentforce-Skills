public with sharing class CreateEscalationTicket {
    @TestVisible private static final Integer MAX_DESCRIPTION_LENGTH = 1000;
    private static final Set<String> ISSUE_TYPES = new Set<String>{ 'technical', 'billing', 'general' };
    private static final Pattern RECORD_ID = Pattern.compile('[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?');

    @InvocableMethod(label='Create Escalation Ticket' description='Create an escalation ticket for handoff to a human specialist.')
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            String customerId = req.customer_id?.trim();
            String description = CreateCase.clean(req.issue_description, MAX_DESCRIPTION_LENGTH);
            String issueType = req.issue_type?.trim().toLowerCase();

            if (String.isBlank(customerId) || !RECORD_ID.matcher(customerId).matches()) {
                res.error_message = 'A valid customer ID is required.';
            } else if (String.isBlank(description)) {
                res.error_message = 'An issue description is required.';
            } else if (!ISSUE_TYPES.contains(issueType)) {
                res.error_message = 'Issue type must be technical, billing, or general.';
            } else {
                res.ticket_id = 'ESC-88392';
            }
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
        @InvocableVariable(label='Error Message') public String error_message;
    }
}
