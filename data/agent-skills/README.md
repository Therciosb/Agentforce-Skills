# Agent Skills Seed Data

Seed files for demo role, skills, workflows, and references:

- `roles.csv` — 1 role (role-customer-support-agent)
- `skills.csv` — 5 core skills + 3 skills (core-skill-ltmManagement-service-agent, core-skill-user-otp-authentication, core-skill-txt-response-guidelines, core-skill-HTML-formatting-guidelines, core-skill-render-data-format, skill-product-information-qa, skill-support-case-management, skill-troubleshooting-support)
- `workflows.csv` — 8 workflows
- `references.csv` — instruction-to-instruction dependency mappings

All CSVs include `Type__c` and `References__c` to align with `Agent_Skills_Repo__c`. Preferred seeding method is `Agent_Skill_SeedService` (see `scripts/apex/seed_agent_skills.apex`) because it enforces deterministic upsert keys and reference integrity.
