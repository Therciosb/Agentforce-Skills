# DMO Seeding Guide

This guide seeds demo records for the Agent Skills custom data model objects.

## Seed Assets

- `data/agent-skills/roles.csv`
- `data/agent-skills/skills.csv`
- `data/agent-skills/workflows.csv`
- `data/agent-skills/references.csv`
- Apex utility: `Agent_Skill_SeedService.seedCustomerSupportDemo()`
- Runner script: `scripts/apex/seed_agent_skills.apex`

## Recommended Method

Use Apex utility for deterministic upsert behavior and reference integrity:

```bash
sf apex run --file scripts/apex/seed_agent_skills.apex --target-org <orgAlias>
```

## Verification Queries

```bash
sf data query -q "SELECT Name, Type__c, Status__c, Version__c FROM Agent_Skills_Repo__c" --target-org <orgAlias>
```

## Expected Demo Dataset

- **Agent_Skills_Repo__c** (consolidated): 17 records
  - 1 Role (`role-customer-support-agent`)
  - 5 Core Skills (`core-skill-ltmManagement-service-agent`, `core-skill-user-otp-authentication`, `core-skill-txt-response-guidelines`, `core-skill-HTML-formatting-guidelines`, `core-skill-render-data-format`)
  - 3 Skills (`skill-product-information-qa`, `skill-troubleshooting-support`, `skill-support-case-management`)
  - 8 Workflows (`workflow-support-case-lifecycle`, `workflow-escalate-to-human`, `workflow-troubleshooting-wifi-modem`, `workflow-troubleshooting-5g-modem`, `workflow-troubleshooting-iphone-16`, `workflow-troubleshooting-iphone-16-pro`, `workflow-troubleshooting-galaxy-s25`, `workflow-troubleshooting-galaxy-s25-ultra`)
- **Agent_Context__c**: 3 demo contexts

## Notes

- Loader and LoadAndCompose actions read active-only instructions.
- Deprecated records should not be returned by `Agent_Skill_Loader` or `Agent_Skill_LoadAndCompose`.
- The seed removes deprecated product-specific troubleshooting skills (converted to workflows) before upserting.
