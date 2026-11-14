@IsTest
private class CreateEscalationTicket_Test {
    private static final String CONTACT_ID = '003000000000001AAA';

    private static CreateEscalationTicket.Response run(String customerId, String description, String issueType) {
        CreateEscalationTicket.Request req = new CreateEscalationTicket.Request();
        req.customer_id = customerId;
        req.issue_description = description;
        req.issue_type = issueType;
        return CreateEscalationTicket.execute(new List<CreateEscalationTicket.Request>{ req })[0];
    }

    @IsTest
    static void createsTicketForValidInput() {
        CreateEscalationTicket.Response res = run(CONTACT_ID, 'Wi-Fi still drops after a modem reset.', ' Technical ');
        Assert.isNotNull(res.ticket_id, 'Valid input should create a ticket');
        Assert.isNull(res.error_message, 'No error expected');
    }

    @IsTest
    static void rejectsInvalidCustomerId() {
        for (String customerId : new List<String>{ null, '', 'unknown', '003000000000001AAA; DROP' }) {
            CreateEscalationTicket.Response res = run(customerId, 'Issue', 'technical');
            Assert.isNull(res.ticket_id, 'Invalid customer ID must not create a ticket: ' + customerId);
            Assert.areEqual('A valid customer ID is required.', res.error_message, 'Expected customer ID error');
        }
    }

    @IsTest
    static void rejectsBlankDescription() {
        CreateEscalationTicket.Response res = run(CONTACT_ID, '  ', 'billing');
        Assert.isNull(res.ticket_id, 'Blank description must not create a ticket');
        Assert.areEqual('An issue description is required.', res.error_message, 'Expected description error');
    }

    @IsTest
    static void rejectsUnknownIssueType() {
        for (String issueType : new List<String>{ null, '', 'urgent' }) {
            CreateEscalationTicket.Response res = run(CONTACT_ID, 'Issue', issueType);
            Assert.isNull(res.ticket_id, 'Unknown issue type must not create a ticket: ' + issueType);
            Assert.areEqual('Issue type must be technical, billing, or general.', res.error_message, 'Expected issue type error');
        }
    }

    @IsTest
    static void acceptsLongDescription() {
        CreateEscalationTicket.Response res = run(CONTACT_ID, 'x'.repeat(5000), 'general');
        Assert.isNotNull(res.ticket_id, 'Long descriptions are capped, not rejected');
    }

    @IsTest
    static void handlesBulkRequests() {
        List<CreateEscalationTicket.Request> reqs = new List<CreateEscalationTicket.Request>();
        for (Integer i = 0; i < 251; i++) {
            CreateEscalationTicket.Request req = new CreateEscalationTicket.Request();
            req.customer_id = CONTACT_ID;
            req.issue_description = 'Issue ' + i;
            req.issue_type = 'general';
            reqs.add(req);
        }
        Assert.areEqual(251, CreateEscalationTicket.execute(reqs).size(), 'One response per request');
    }
}
