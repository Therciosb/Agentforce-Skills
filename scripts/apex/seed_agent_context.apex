// Re-seed Agent_Context__c with demo scenarios matching customer support skill capabilities.
// Run: sf apex run --file scripts/apex/seed_agent_context.apex --target-org ltm-memory-org
Agent_Skill_SeedService.seedAgentContextDemo();
System.debug('Agent_Context__c demo records re-seeded.');
