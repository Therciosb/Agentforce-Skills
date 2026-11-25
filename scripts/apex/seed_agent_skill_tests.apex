// Seeds skill routing test cases for the demo agent. Safe to re-run: the agent's cases are replaced.
// sf apex run --file scripts/apex/seed_agent_skill_tests.apex --target-org <org>
// Contact-gated tools (fetch_support_history, fetch_account_data) are left out of Expected Tools:
// Testing Center sessions are anonymous, so those tools are never available there.

String agentName = 'customer_support_progressive_pd2';
String subagentName = 'skill_host';
// name, utterance, expected skills, expected tools, expected outcome
List<List<String>> rows = new List<List<String>>{
    new List<String>{ 'Product price', 'What is the price of the Widget X?', 'skill-product-information-qa', 'get_product_info',
        'Agent states the price of the Widget X.' },
    new List<String>{ 'Device troubleshooting', 'My phone screen keeps flickering even after a restart. What should I try?', 'skill-troubleshooting-support', '',
        'Agent suggests troubleshooting steps for the flickering screen beyond a restart.' },
    new List<String>{ 'Order status', 'Where is my order 00000100?', 'skill-order-status-support', 'get_order_status',
        'Agent reports the status of order 00000100.' },
    new List<String>{ 'Shipment tracking', 'Can you track my UPS package 1Z999AA10123456784?', 'skill-order-status-support', 'track_shipment',
        'Agent reports the tracking status of the UPS package.' },
    new List<String>{ 'Case history', 'Show me the status of the support cases I opened before.', 'skill-support-case-management', '',
        'Agent helps the customer review their previous support cases, asking them to verify their identity if needed.' }
};

delete [SELECT Id FROM Agent_Skill_Test_Case__c WHERE Agent_Developer_Name__c = :agentName];
List<Agent_Skill_Test_Case__c> cases = new List<Agent_Skill_Test_Case__c>();
for (List<String> r : rows) {
    cases.add(new Agent_Skill_Test_Case__c(
        Name = r[0],
        Agent_Developer_Name__c = agentName,
        Subagent__c = subagentName,
        Utterance__c = r[1],
        Expected_Skills__c = r[2],
        Expected_Tools__c = String.isBlank(r[3]) ? null : r[3],
        Expected_Outcome__c = r[4],
        Active__c = true
    ));
}
insert cases;
System.debug('Seeded ' + cases.size() + ' test cases for ' + agentName + '.');
