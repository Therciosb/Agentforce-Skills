@IsTest
private class CreateCase_Test {
    private static CreateCase.Response run(String subject) {
        CreateCase.Request req = new CreateCase.Request();
        req.subject = subject;
        return CreateCase.execute(new List<CreateCase.Request>{ req })[0];
    }

    @IsTest
    static void createsCaseForValidSubject() {
        CreateCase.Response res = run('Order 00055555 arrived damaged');
        Assert.isNotNull(res.case_number, 'A valid subject should create a case');
        Assert.isNull(res.error_message, 'No error expected');
    }

    @IsTest
    static void rejectsBlankSubject() {
        for (String subject : new List<String>{ null, '', '   ', '\u0000\u0007' }) {
            CreateCase.Response res = run(subject);
            Assert.isNull(res.case_number, 'Blank subject must not create a case: ' + subject);
            Assert.isNotNull(res.error_message, 'Blank subject must return an error');
        }
    }

    @IsTest
    static void cleanStripsControlCharactersAndCapsLength() {
        Assert.areEqual('a b', CreateCase.clean('  a\u0000\n b\u0007 ', 255), 'Control characters and extra spaces should be removed');
        Assert.areEqual(255, CreateCase.clean('x'.repeat(5000), CreateCase.MAX_SUBJECT_LENGTH).length(), 'Long values should be capped');
    }

    @IsTest
    static void handlesBulkRequests() {
        List<CreateCase.Request> reqs = new List<CreateCase.Request>();
        for (Integer i = 0; i < 251; i++) {
            CreateCase.Request req = new CreateCase.Request();
            req.subject = 'Subject ' + i;
            reqs.add(req);
        }
        List<CreateCase.Response> responses = CreateCase.execute(reqs);
        Assert.areEqual(251, responses.size(), 'One response per request');
    }
}
