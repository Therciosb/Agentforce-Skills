# Contributing to Agent Skills Framework

Thank you for your interest in contributing. This document provides guidelines for contributing to the project.

## Getting Started

1. **Fork and clone** the repository.
2. **Deploy** to a Salesforce org with Agentforce enabled:
   ```bash
   sf project deploy start --source-dir force-app/main/default --target-org <your-org>
   ```
3. **Run tests** to verify the baseline:
   ```bash
   sf apex run test --tests Agent_Skill_Loader_Test,Agent_Skill_PromptComposer_Test,Agent_Skill_LoadAndCompose_Test --target-org <your-org> --result-format human
   ```

## Development Guidelines

### Code Style

- **Apex**: Follow [Apex Style Guide](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_style_guide.htm).
- **Agent Script**: Follow patterns in [Agent-Skills-Framework-for-FDE](docs/Agent-Skills-Framework-for-FDE.md) and [Agent Script Manual v4](docs/Agent%20Script%20Manual%20v4.md).
- **Documentation**: Use clear, concise language. Update relevant docs when changing behavior.

### Instruction Naming

- Roles: `role-*` (e.g., `role-customer-support-agent`)
- Core skills: `core-skill-*` (e.g., `core-skill-txt-response-guidelines`)
- Skills: `skill-*` (e.g., `skill-product-information-qa`)
- Workflows: `workflow-*` (e.g., `workflow-escalate-to-human`)

### Pull Request Process

1. Create a feature branch from `main`.
2. Make your changes. Ensure tests pass.
3. Update documentation if behavior or APIs change.
4. Submit a pull request with a clear description of the change.
5. Address review feedback.

### Reporting Issues

When reporting issues, please include:

- Salesforce API version and org type (sandbox/production)
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs or error messages

### Scope

This project focuses on the Agent Skills framework: instruction loading, composition, and Agent Script integration. For Agentforce platform features or Agent Script language questions, refer to [Salesforce Developer Documentation](https://developer.salesforce.com/docs/atlas.en-us.agentforce.meta/agentforce/).
