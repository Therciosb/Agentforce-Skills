/**
 * Test class for SaveAgentContext invocable action.
 */
@IsTest
private class SaveAgentContextTest {
    @TestSetup
    static void setup() {
        Contact c = new Contact(LastName = 'TestContact');
        insert c;
    }

    @IsTest
    static void testSaveContext_createNew() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        SaveAgentContext.InputParameters input = new SaveAgentContext.InputParameters();
        input.contactId = c.Id;
        input.newSummary = 'New conversation summary.';
        input.newGoal = 'Complete upgrade';
        input.hasIssue = false;
        input.newStyle = 'Concise';

        Test.startTest();
        List<SaveAgentContext.OutputParameters> outputs = SaveAgentContext.saveContext(
            new List<SaveAgentContext.InputParameters>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, outputs.size());
        System.assertEquals(true, outputs[0].success, 'Save should succeed');

        Agent_Context__c ctx = [
            SELECT Last_Topic_Summary__c, Pending_Goal__c, Unresolved_Issue__c, Communication_Style__c
            FROM Agent_Context__c
            WHERE Contact__c = :c.Id
        ];
        System.assertEquals('New conversation summary.', ctx.Last_Topic_Summary__c);
        System.assertEquals('Complete upgrade', ctx.Pending_Goal__c);
        System.assertEquals(false, ctx.Unresolved_Issue__c);
        System.assertEquals('Concise', ctx.Communication_Style__c);
    }

    @IsTest
    static void testSaveContext_updateExisting() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        Agent_Context__c existing = new Agent_Context__c(
            Contact__c = c.Id,
            Last_Topic_Summary__c = 'Old summary',
            Pending_Goal__c = 'Old goal',
            Unresolved_Issue__c = false,
            Communication_Style__c = 'Detailed'
        );
        insert existing;

        SaveAgentContext.InputParameters input = new SaveAgentContext.InputParameters();
        input.contactId = c.Id;
        input.newSummary = 'Updated summary.';
        input.newGoal = 'Updated goal';
        input.hasIssue = true;
        input.newStyle = 'Formal';

        Test.startTest();
        List<SaveAgentContext.OutputParameters> outputs = SaveAgentContext.saveContext(
            new List<SaveAgentContext.InputParameters>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, outputs.size());
        System.assertEquals(true, outputs[0].success);

        Agent_Context__c ctx = [
            SELECT Last_Topic_Summary__c, Pending_Goal__c, Unresolved_Issue__c, Communication_Style__c
            FROM Agent_Context__c
            WHERE Contact__c = :c.Id
        ];
        System.assertEquals('Updated summary.', ctx.Last_Topic_Summary__c);
        System.assertEquals('Updated goal', ctx.Pending_Goal__c);
        System.assertEquals(true, ctx.Unresolved_Issue__c);
        System.assertEquals('Formal', ctx.Communication_Style__c);
    }

    @IsTest
    static void testSaveContext_blankContactId() {
        SaveAgentContext.InputParameters input = new SaveAgentContext.InputParameters();
        input.contactId = '';
        input.newSummary = 'Summary';
        input.newGoal = '';
        input.hasIssue = false;
        input.newStyle = 'Detailed';

        Test.startTest();
        List<SaveAgentContext.OutputParameters> outputs = SaveAgentContext.saveContext(
            new List<SaveAgentContext.InputParameters>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, outputs.size());
        System.assertEquals(false, outputs[0].success);
    }
}