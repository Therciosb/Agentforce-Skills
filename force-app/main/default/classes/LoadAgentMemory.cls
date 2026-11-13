/**
 * Invocable Apex action for loading Agent_Context__c and formatting it into a string
 * for use as agent_memory in Agentforce. Replaces the Get Records flow logic.
 */
public with sharing class LoadAgentMemory {
    @InvocableMethod(
        label='Load Agent Memory'
        description='Loads Agent_Context__c by contact ID and returns a formatted string for agent personalization.'
    )
    public static List<OutputParameters> loadMemory(List<InputParameters> inputs) {
        List<OutputParameters> outputs = new List<OutputParameters>();
        for (InputParameters input : inputs) {
            outputs.add(loadMemoryForContact(input));
        }
        return outputs;
    }

    private static OutputParameters loadMemoryForContact(InputParameters input) {
        OutputParameters output = new OutputParameters();
        output.agentMemory = '';

        if (String.isBlank(input.contactId)) {
            return output;
        }

        List<Agent_Context__c> records = [
            SELECT Id, Name, Last_Topic_Summary__c, Pending_Goal__c,
                   Unresolved_Issue__c, Communication_Style__c, User_Tier__c
            FROM Agent_Context__c
            WHERE Contact__c = :input.contactId
            LIMIT 1
        ];

        if (records.isEmpty()) {
            output.memorySummary = '';
            output.memoryGoal = '';
            output.hasIssue = false;
            output.memoryStyle = '';
            return output;
        }

        Agent_Context__c ctx = records[0];
        output.agentMemory = formatContext(ctx);
        output.memorySummary = ctx.Last_Topic_Summary__c;
        output.memoryGoal = ctx.Pending_Goal__c;
        output.hasIssue = ctx.Unresolved_Issue__c == true;
        output.memoryStyle = ctx.Communication_Style__c;
        return output;
    }

    private static String formatContext(Agent_Context__c ctx) {
        List<String> parts = new List<String>();

        if (String.isNotBlank(ctx.Name)) {
            parts.add('Name: ' + ctx.Name);
        }
        if (String.isNotBlank(ctx.Last_Topic_Summary__c)) {
            parts.add('Last Topic Summary: ' + ctx.Last_Topic_Summary__c);
        }
        if (String.isNotBlank(ctx.Pending_Goal__c)) {
            parts.add('Pending Goal: ' + ctx.Pending_Goal__c);
        }
        parts.add('Unresolved Issue: ' + (ctx.Unresolved_Issue__c == true ? 'Yes' : 'No'));
        if (String.isNotBlank(ctx.Communication_Style__c)) {
            parts.add('Communication Style: ' + ctx.Communication_Style__c);
        }
        if (String.isNotBlank(ctx.User_Tier__c)) {
            parts.add('User Tier: ' + ctx.User_Tier__c);
        }

        return String.join(parts, '\n');
    }

    public class InputParameters {
        @InvocableVariable(label='Contact ID' description='Contact ID to look up Agent_Context__c' required=true)
        public String contactId;

        @InvocableVariable(label='Variable Name' description='Target variable name for output mapping (default: agent_memory)')
        public String variableName;
    }

    public class OutputParameters {
        @InvocableVariable(label='Agent Memory' description='Formatted merge of all memory fields for agent personalization')
        public String agentMemory;
        @InvocableVariable(label='Memory Summary' description='Last topic summary for checkpoint agents')
        public String memorySummary;
        @InvocableVariable(label='Memory Goal' description='Pending goal for checkpoint agents')
        public String memoryGoal;
        @InvocableVariable(label='Has Issue' description='Unresolved issue flag for checkpoint agents')
        public Boolean hasIssue;
        @InvocableVariable(label='Memory Style' description='Communication style for checkpoint agents')
        public String memoryStyle;
    }
}