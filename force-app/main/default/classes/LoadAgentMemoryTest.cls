/**
 * Test class for LoadAgentMemory invocable action.
 */
@IsTest
private class LoadAgentMemoryTest {
    @TestSetup
    static void setup() {
        Contact c = new Contact(LastName = 'TestContact');
        insert c;

        Agent_Context__c ctx = new Agent_Context__c(
            Contact__c = c.Id,
            Last_Topic_Summary__c = 'Previous conversation summary.',
            Pending_Goal__c = 'Upgrade plan',
            Unresolved_Issue__c = true,
            Communication_Style__c = 'Detailed',
            User_Tier__c = 'VIP'
        );
        insert ctx;
    }

    @IsTest
    static void testLoadMemory_withRecord() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        LoadAgentMemory.InputParameters input = new LoadAgentMemory.InputParameters();
        input.contactId = c.Id;

        Test.startTest();
        List<LoadAgentMemory.OutputParameters> outputs = LoadAgentMemory.loadMemory(
            new List<LoadAgentMemory.InputParameters>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, outputs.size(), 'Should return one output');
        LoadAgentMemory.OutputParameters output = outputs[0];
        System.assertNotEquals(null, output.agentMemory, 'agentMemory should not be null');
        System.assert(output.agentMemory.contains('Previous conversation summary.'), 'Should contain summary');
        System.assert(output.agentMemory.contains('Upgrade plan'), 'Should contain goal');
        System.assert(output.agentMemory.contains('Unresolved Issue: Yes'), 'Should contain issue');
        System.assert(output.agentMemory.contains('Detailed'), 'Should contain style');
        System.assert(output.agentMemory.contains('VIP'), 'Should contain tier');
        System.assertEquals('Previous conversation summary.', output.memorySummary);
        System.assertEquals('Upgrade plan', output.memoryGoal);
        System.assertEquals(true, output.hasIssue);
        System.assertEquals('Detailed', output.memoryStyle);
    }

    @IsTest
    static void testLoadMemory_noRecord() {
        LoadAgentMemory.InputParameters input = new LoadAgentMemory.InputParameters();
        input.contactId = '003000000000000AAA'; // Non-existent contact

        Test.startTest();
        List<LoadAgentMemory.OutputParameters> outputs = LoadAgentMemory.loadMemory(
            new List<LoadAgentMemory.InputParameters>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, outputs.size());
        LoadAgentMemory.OutputParameters output = outputs[0];
        System.assertEquals('', output.agentMemory);
        System.assertEquals('', output.memorySummary);
        System.assertEquals('', output.memoryGoal);
        System.assertEquals(false, output.hasIssue);
        System.assertEquals('', output.memoryStyle);
    }

    @IsTest
    static void testLoadMemory_blankContactId() {
        LoadAgentMemory.InputParameters input = new LoadAgentMemory.InputParameters();
        input.contactId = '';

        Test.startTest();
        List<LoadAgentMemory.OutputParameters> outputs = LoadAgentMemory.loadMemory(
            new List<LoadAgentMemory.InputParameters>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, outputs.size());
        System.assertEquals('', outputs[0].agentMemory);
    }
}