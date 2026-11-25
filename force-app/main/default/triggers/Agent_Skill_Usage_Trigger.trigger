trigger Agent_Skill_Usage_Trigger on Agent_Skill_Usage__e (after insert) {
    List<Agent_Skill_Usage_Log__c> logs = new List<Agent_Skill_Usage_Log__c>();
    for (Agent_Skill_Usage__e e : Trigger.new) {
        logs.add(new Agent_Skill_Usage_Log__c(
            Agent_Name__c = e.Agent_Name__c,
            Requested_Skills__c = e.Requested_Skills__c,
            Active_Skills__c = e.Active_Skills__c,
            Warnings__c = e.Warnings__c,
            Has_Warnings__c = String.isNotBlank(e.Warnings__c),
            Instruction_Chars__c = e.Instruction_Chars__c,
            Duration_Ms__c = e.Duration_Ms__c
        ));
    }
    insert logs;
}
