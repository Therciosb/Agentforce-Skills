/**
 * Invocable Apex action for saving Agent_Context__c. Accepts scalar inputs only;
 * queries by contact_id internally and creates or updates the record.
 */
public with sharing class SaveAgentContext {
    @InvocableMethod(
        label='Save Agent Context'
        description='Creates or updates Agent_Context__c by contact ID with extracted memory values.'
    )
    public static List<OutputParameters> saveContext(List<InputParameters> inputs) {
        List<OutputParameters> outputs = new List<OutputParameters>();
        for (InputParameters input : inputs) {
            outputs.add(saveContextForContact(input));
        }
        return outputs;
    }

    private static OutputParameters saveContextForContact(InputParameters input) {
        OutputParameters output = new OutputParameters();
        output.success = false;

        if (String.isBlank(input.contactId)) {
            return output;
        }

        List<Agent_Context__c> existing = [
            SELECT Id, Last_Topic_Summary__c, Pending_Goal__c,
                   Unresolved_Issue__c, Communication_Style__c, User_Tier__c
            FROM Agent_Context__c
            WHERE Contact__c = :input.contactId
            LIMIT 1
        ];

        try {
            if (!existing.isEmpty()) {
                Agent_Context__c ctx = existing[0];
                ctx.Last_Topic_Summary__c = input.newSummary != null ? input.newSummary : '';
                ctx.Pending_Goal__c = input.newGoal != null ? input.newGoal : '';
                ctx.Unresolved_Issue__c = input.hasIssue != null && input.hasIssue;
                ctx.Communication_Style__c = input.newStyle != null ? input.newStyle : '';
                update ctx;
            } else {
                Agent_Context__c ctx = new Agent_Context__c();
                ctx.Contact__c = input.contactId;
                ctx.Last_Topic_Summary__c = input.newSummary != null ? input.newSummary : '';
                ctx.Pending_Goal__c = input.newGoal != null ? input.newGoal : '';
                ctx.Unresolved_Issue__c = input.hasIssue != null && input.hasIssue;
                ctx.Communication_Style__c = input.newStyle != null ? input.newStyle : '';
                insert ctx;
            }
            output.success = true;
        } catch (Exception e) {
            output.success = false;
        }
        return output;
    }

    public class InputParameters {
        @InvocableVariable(label='Contact ID' description='Contact used to find or create Agent_Context__c' required=true)
        public String contactId;

        @InvocableVariable(label='New Summary' description='Concise summary of the current conversation')
        public String newSummary;

        @InvocableVariable(label='New Goal' description='Pending goal to continue in next session')
        public String newGoal;

        @InvocableVariable(label='Has Issue' description='True when unresolved issue should remain open')
        public Boolean hasIssue;

        @InvocableVariable(label='New Style' description='Updated communication style preference')
        public String newStyle;
    }

    public class OutputParameters {
        @InvocableVariable(label='Success' description='Whether the save succeeded')
        public Boolean success;
    }
}