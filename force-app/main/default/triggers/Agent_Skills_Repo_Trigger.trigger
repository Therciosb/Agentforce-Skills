trigger Agent_Skills_Repo_Trigger on Agent_Skills_Repo__c (after insert, after update, after delete, after undelete) {
    List<Agent_Skills_Repo__c> changed = new List<Agent_Skills_Repo__c>();
    if (Trigger.new != null) {
        changed.addAll(Trigger.new);
    }
    if (Trigger.old != null) {
        changed.addAll(Trigger.old);
    }
    Agent_Skill_Catalog.invalidate(changed);
}
