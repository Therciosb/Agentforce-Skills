# Agent Skills Seed Data

Seed files for demo role, skills, workflows, and references:

- `roles.csv`
- `skills.csv`
- `workflows.csv`
- `references.csv`

Preferred seeding method is `Agent_Skill_SeedService` (see `scripts/apex/seed_agent_skills.apex`) because it enforces deterministic upsert keys and reference integrity.
