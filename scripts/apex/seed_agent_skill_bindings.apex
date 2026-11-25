// Seeds Agent_Skill_Binding__c wiring for the demo agents. Safe to re-run:
// bindings upsert by Agent_Developer_Name__c and their items are replaced.
// sf apex run --file scripts/apex/seed_agent_skill_bindings.apex --target-org <org>

Map<String, String> labels = new Map<String, String>{
    'customer_support_progressive_pd2' => 'Customer Support (Progressive Disclosure)',
    'skill_state_spike' => 'Skill State Spike'
};

List<List<String>> supportItems = new List<List<String>>{
    new List<String>{ 'role-customer-support-agent', 'Always' },
    new List<String>{ 'core-skill-ltmManagement-service-agent', 'Always' },
    new List<String>{ 'core-skill-txt-response-guidelines', 'Always' },
    new List<String>{ 'skill-product-information-qa', 'Default' },
    new List<String>{ 'skill-troubleshooting-support', 'Selectable' },
    new List<String>{ 'skill-support-case-management', 'Selectable' },
    new List<String>{ 'skill-order-status-support', 'Selectable' }
};

List<Agent_Skill_Binding__c> bindings = new List<Agent_Skill_Binding__c>();
for (String agentName : labels.keySet()) {
    bindings.add(new Agent_Skill_Binding__c(
        Name = labels.get(agentName),
        Agent_Developer_Name__c = agentName,
        Status__c = 'Active',
        Locale__c = 'en-US'
    ));
}
upsert bindings Agent_Developer_Name__c;

delete [SELECT Id FROM Agent_Skill_Binding_Item__c WHERE Binding__c IN :bindings];

List<Agent_Skill_Binding_Item__c> items = new List<Agent_Skill_Binding_Item__c>();
for (Agent_Skill_Binding__c b : bindings) {
    Integer order = 1;
    for (List<String> entry : supportItems) {
        items.add(new Agent_Skill_Binding_Item__c(Binding__c = b.Id, Skill_Name__c = entry[0], Mode__c = entry[1], Order__c = order++));
    }
}
insert items;
System.debug('Seeded ' + bindings.size() + ' bindings with ' + items.size() + ' items.');
