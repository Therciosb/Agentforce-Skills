# Agent Skills Framework

A reusable framework for building **Agentforce** agents with dynamic, CRM-backed instruction loading and prompt composition. Store roles, skills, and workflows in Salesforce, compose them at runtime, and keep agent behavior consistent and maintainable—without redeploying code for instruction changes.

---

## About This Project

Building production-ready AI agents for enterprise use cases often runs into the same issues: prompts are hardcoded in agent definitions, so any change to policies or procedures requires redeploying the agent bundle. Domain expertise lives in documents and wikis with no single source of truth for agents to consume. Similar agents duplicate logic and diverge over time. Shared skills—identity verification, escalation, response guidelines—cannot be composed, so each topic reinvents the wheel. Instruction changes are not versioned or governed, and loading all instructions into every topic wastes tokens.

The Agent Skills framework addresses these problems by **separating instructions from agent logic**. Instructions live in a CRM-backed repository (`Agent_Skills_Repo__c`) and are editable by business users without redeploying agents. A structured taxonomy—roles, core skills, skills, and workflows—with clear naming and reference relationships enables **dynamic composition**: agents load only the instructions needed for the current topic and merge them with role/core context. Reference expansion pulls in dependent workflows automatically. Records support versioning (`Status__c`, `Version__c`, `Locale__c`) for governance and localization.

For enterprises, this means **business agility** (non-developers can update instructions via the Admin app; no code changes for policy updates), **consistency and compliance** (single source of truth; auditability in Salesforce), **scalability** (reusable building blocks; change a workflow once and all referencing skills inherit it), and **cost efficiency** (token optimization via topic-specific composition; lower development cost through reuse). The framework is CRM-native and integrates with permission sets, approval processes, and data governance. It can also work alongside optional Long-Term Memory for personalized, session-aware conversations.

For implementation details, Agent Script structure, and key rules, see [Agent-Skills-Framework-for-FDE](docs/Agent-Skills-Framework-for-FDE.md).

---

## Key Features

- **CRM-backed instruction repository** — Roles, core skills, skills, and workflows stored in `Agent_Skills_Repo__c`
- **Dynamic load and compose** — Load only topic-relevant instructions; merge with role/core context; expand references recursively
- **Reference expansion** — Skills reference workflows; workflows reference other workflows; composer pulls dependencies automatically
- **Versioning and lifecycle** — `Status__c` (active/deprecated), `Version__c`, `Locale__c` for governance
- **Admin UI** — Custom app for Authors, Reviewers, and Consumers
- **Agent Script integration** — Designed for Agentforce agents authored in Agent Script

## No Dependency on LTM-Agentforce

**This project is fully standalone.** It does not depend on, require, or reference the LTM-Agentforce project.

- **Core framework** — The Loader, Composer, LoadAndCompose Apex actions, `Agent_Skills_Repo__c`, and optional `Load_And_Compose_Agent_Skills` flow work independently. Agents use `apex://Agent_Skill_LoadAndCompose` directly. Deploy this project to any Salesforce org with Agentforce and you can build agents that load and compose skills.
- **skill_load_test agent** — A minimal agent that demonstrates the framework without persistent memory. Use it to validate the skill loading pipeline.
- **customer_support_skill_demo agent** — A full demo that includes optional Long-Term Memory (LTM) integration. LTM requires an `Agent_Context__c` object and read/save flows. Implement per the [LTM Integration Mapping](docs/LTM%20Integration%20Mapping.md) spec: Get flow returns `agent_memory` (formatted string); Save flow accepts scalar inputs only (`new_summary`, `new_goal`, `has_issue`, `new_style`).

## Prerequisites

- Salesforce org with **Agentforce** and **Agent Script** enabled
- Salesforce CLI (`sf`) for deployment and testing
- For `customer_support_skill_demo` with LTM: `Agent_Context__c` object (create per [LTM Integration Mapping](docs/LTM%20Integration%20Mapping.md))

## Quick Start

### 1. Clone and Deploy

```bash
git clone https://github.com/your-org/Agent-Skills.git
cd Agent-Skills
sf project deploy start --source-dir force-app/main/default --target-org <your-org-alias>
```

### 2. Assign Permission Set

Assign **Agent Skills Agent Runtime** to your agent bot user (Setup → Users → select bot user → Permission Set Assignments → Add → Agent Skills Agent Runtime).

### 3. Seed Demo Skills

```bash
sf apex run --file scripts/apex/seed_agent_skills.apex --target-org <your-org-alias>
```

> **Note:** The seed creates `Agent_Skills_Repo__c` records and, if `Agent_Context__c` exists, demo context records. For skills-only validation, use the `skill_load_test` agent.

### 4. Validate and Publish an Agent

```bash
sf agent validate authoring-bundle --api-name skill_load_test --target-org <your-org-alias>
sf agent publish authoring-bundle --api-name skill_load_test --target-org <your-org-alias>
```

## Project Structure

```
Agent-Skills/
├── force-app/main/default/
│   ├── aiAuthoringBundles/          # Agent bundles
│   │   ├── skill_load_test/         # Minimal agent (no LTM)
│   │   └── customer_support_skill_demo/  # Full demo (optional LTM)
│   ├── classes/                     # Apex: Loader, Composer, LoadAndCompose, SeedService
│   ├── flows/                       # Load_And_Compose_Agent_Skills (optional); LTM uses LoadAgentMemory, SaveAgentContext Apex
│   ├── objects/                     # Agent_Skills_Repo__c
│   ├── customApplications/         # Agent_Skills_Admin app
│   └── permissionsets/              # Agent_Skills_Author, Reviewer, Consumer, Agent_Runtime
├── data/agent-skills/              # CSV seed data (roles, skills, workflows, references)
├── scripts/apex/                   # Anonymous Apex seed runner
└── docs/                           # Documentation
```

## Documentation

| Document | Description |
|----------|-------------|
| [Agent-Skills-Framework-for-FDE](docs/Agent-Skills-Framework-for-FDE.md) | Framework overview for engineers: problem, value, implementation, Agent Script structure |
| [Agent Script Manual v4](docs/Agent%20Script%20Manual%20v4.md) | Agent Script language, execution model, blocks, patterns |
| [Apex Action Contracts](docs/Apex%20Action%20Contracts.md) | Loader, Composer, LoadAndCompose API details |
| [Implementation Plan v1](docs/Implementation%20Plan%20v1.md) | Framework scope and implementation baseline |
| [LTM Integration Mapping](docs/LTM%20Integration%20Mapping.md) | Optional persistent memory: object schema, Apex action contracts, runtime pattern |
| [DMO Seeding Guide](docs/DMO%20Seeding%20Guide.md) | Seeding roles, skills, workflows |
| [Admin-App-Setup](docs/Admin-App-Setup.md) | Permission sets, list views, tab visibility |
| [Agentforce SDR Agent Reference](docs/Agentforce%20SDR%20Agent%20Reference.md) | Built-in SDR agent analysis |
| [Agentforce Sales Coach Agent Reference](docs/Agentforce%20Sales%20Coach%20Agent%20Reference.md) | Built-in Sales Coach agent analysis |
| [SDR Agent Implementation Plan](docs/SDR%20Agent%20Implementation%20Plan.md) | Plan for Agent Script–based SDR agent |

## Usage Guidelines

### For New Agents

1. **Define your instruction taxonomy** — Roles (`role-*`), core skills (`core-skill-*`), skills (`skill-*`), workflows (`workflow-*`). Use `References__c` to link skills to workflows.
2. **Create the `load_and_compose_skills` action** — Target `apex://Agent_Skill_LoadAndCompose`. See [Agent-Skills-Framework-for-FDE](docs/Agent-Skills-Framework-for-FDE.md) for the action contract.
3. **Wire `start_agent`** — Load role + core skills, store `loadedInstructionBundle` in `@variables.instruction_bundle_json`, transition to first topic.
4. **Wire each topic** — Call Load_And_Compose with topic-specific `instructionNames` and `existingInstructionBundle`; inject `composed_instructions` into reasoning.
5. **Assign Agent Skills Agent Runtime** to the agent bot user.

### For Instruction Authors

- Use the **Agent Skills Admin** app to create and edit `Agent_Skills_Repo__c` records.
- Follow naming: `role-*`, `core-skill-*`, `skill-*`, `workflow-*`.
- Set `Status__c` to `active` for production; use `deprecated` to retire instructions.
- Use `References__c` (CSV of names) to declare dependencies; the composer expands them automatically.

### Testing

```bash
sf apex run test --tests Agent_Skill_Loader_Test,Agent_Skill_PromptComposer_Test,Agent_Skill_LoadAndCompose_Test --target-org <org> --result-format human
```

## License

See [LICENSE](LICENSE) for details.

## Contributing

See [CONTRIBUTING](CONTRIBUTING.md) for guidelines.

## Security

See [SECURITY](SECURITY.md) for vulnerability reporting.
