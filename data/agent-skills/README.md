# Agent Skills Seed Data

Seed files for demo role, skills, workflows, and references:

- `roles.csv` — 1 role (role-customer-support-agent)
- `skills.csv` — 5 core skills + 3 skills (core-skill-ltmManagement-service-agent, core-skill-user-otp-authentication, core-skill-txt-response-guidelines, core-skill-HTML-formatting-guidelines, core-skill-render-data-format, skill-product-information-qa, skill-support-case-management, skill-troubleshooting-support)
- `workflows.csv` — 8 workflows
- `references.csv` — instruction-to-instruction dependency mappings

All CSVs include `Type__c` and `References__c` to align with `Agent_Skills_Repo__c`. Preferred seeding method is `Agent_Skill_SeedService` (see `scripts/apex/seed_agent_skills.apex`) because it enforces deterministic upsert keys and reference integrity.

`drafts.csv` is a snapshot of the Draft skills created in the org with the skill builder. It is not loaded by the seed service.

## Instruction body format

Every `InstructionBody__c` follows the same shape so composed instructions read consistently:

- One H1 title (`# ORDER STATUS SUPPORT`), then H2 sections (`## Purpose`, `## Steps`, `## Rules`) and H3 numbered steps (`### 1. Identify the order`).
- Written to the agent ("Ask for the order number"), never to the end user.
- Tools only as `[[tool:Name]]` indicators. Plain-text tool names are not rewritten or validated.
- Every record named in the body (`workflow-*`, `core-skill-*`) is listed in `References__c`, and every reference is named in the body. `Agent_Skill_SeedService_Test` checks this for the seeded records.
- No `{!@variables...}` merge fields: skill text is injected as a variable value and is never interpolated again.

