# Agent Skills Framework — Documentation

This folder contains documentation for the Agent Skills framework and related Agentforce/Agent Script topics.

## Framework Documentation


| Document                                                            | Audience          | Description                                                                                                      |
| ------------------------------------------------------------------- | ----------------- | ---------------------------------------------------------------------------------------------------------------- |
| [Agent-Skills-Framework-for-FDE](Agent-Skills-Framework-for-FDE.md) | FDE engineers     | Problem statement, enterprise value, implementation overview, Agent Script structure when applying the framework |
| [Implementation Plan v1](Implementation%20Plan%20v1.md)             | Engineers, PMs    | Framework scope, implemented metadata, Apex contracts, Agent Script wiring, demo scenario                        |
| [Apex Action Contracts](Apex%20Action%20Contracts.md)               | Engineers         | API details for `Agent_Skill_Loader`, `Agent_Skill_PromptComposer`, `Agent_Skill_LoadAndCompose`                 |
| [DMO Seeding Guide](DMO%20Seeding%20Guide.md)                       | Admins, engineers | Seeding roles, skills, workflows via CSV and Apex                                                                |
| [Admin-App-Setup](Admin-App-Setup.md)                               | Admins            | Permission sets, list views, tab visibility for Agent Skills Admin                                               |


## Agent Script Reference


| Document                                                  | Description                                                                                                                               |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| [Agent Script Manual v4](Agent%20Script%20Manual%20v4.md) | Language model, execution model, blocks, variables, actions vs tools, conditionals, transitions, patterns, LTM reference, troubleshooting |


## Optional Integrations


| Document                                                  | Description                                                                                                                                                                                                                            |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [LTM Integration Mapping](LTM%20Integration%20Mapping.md) | Optional persistent memory: `Agent_Context__c` schema, flow contracts (`Get_Agent_ContextObject`, `Save_Agent_ContextObject`), runtime pattern. **No dependency on LTM-Agentforce**—implement per spec or use any compatible solution. |


## Agentforce Reference


| Document                                                                                    | Description                                                          |
| ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| [Agentforce SDR Agent Reference](Agentforce%20SDR%20Agent%20Reference.md)                   | Built-in SDR agent: capabilities, assets, cloud dependencies         |
| [Agentforce Sales Coach Agent Reference](Agentforce%20Sales%20Coach%20Agent%20Reference.md) | Built-in Sales Coach agent: capabilities, assets, cloud dependencies |
| [SDR Agent Implementation Plan](SDR%20Agent%20Implementation%20Plan.md)                     | Plan for Agent Script–based SDR agent                                |


