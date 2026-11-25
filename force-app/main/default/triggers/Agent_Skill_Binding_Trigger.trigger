trigger Agent_Skill_Binding_Trigger on Agent_Skill_Binding__c (before insert, before update) {
    for (Agent_Skill_Binding__c b : Trigger.new) {
        b.Binding_Key__c = Agent_Skill_State.bindingKey(b.Agent_Developer_Name__c, b.Subagent__c);
    }
}
