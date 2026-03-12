# Agentforce Sales Coach Agent Reference

Reference document for the built-in Agentforce Sales Coach agent: capabilities, assets, cloud dependencies, and analysis of replacing Data 360 with custom alternatives.

---

## 1. Overview

The **Agentforce Sales Coach** is Salesforce's pre-built AI-powered coaching agent that delivers personalized, real-time guidance to sales reps directly within Sales Cloud. It provides deal-specific feedback, role-play simulations, and pitch practice to help reps sharpen their skills and close deals more effectively.

### Key Characteristics

- **Employee-facing** – coaches sales reps (internal users), not external prospects
- **Deal-contextual** – uses Opportunity, Account, and CRM data for personalized feedback
- **On-demand** – available anytime without a live coach
- **Role-play capable** – simulates a customer or buyer for practice scenarios
- **Stage-specific** – feedback aligned to opportunity stage (Qualification, Needs Analysis, Discovery, Proposal/Pricing, Negotiation/Review)

### Primary Interface

- Embedded on the **Opportunity** record page via the Agentforce Sales Coach Lightning component
- Reps engage with the coach in the context of a specific opportunity

---

## 2. Capabilities

| Capability | Description |
|------------|-------------|
| **Role-Play Simulation** | AI simulates a customer or buyer; reps practice tough conversations, objections, and negotiations |
| **Pitch Practice** | Reps rehearse pitches and receive tailored, actionable feedback based on deal stage |
| **Opportunity Coaching** | Stage-specific feedback after role-play or pitch; evaluates rep performance against best practices |
| **Deal-Specific Feedback** | Insights grounded in CRM data (Account, Opportunity, tasks, notes) |
| **Scalable Coaching** | Managers can scale 1:1 coaching; agent has "infinite knowledge" for every opportunity |

---

## 3. Topics and Actions

The built-in Sales Coach agent is organized around three prebuilt topics:

| Topic | Purpose | Key Actions |
|-------|---------|-------------|
| **Agentforce Sales Coach: Proposal Quote Role-Play** | Simulate a customer in proposal/quote scenarios | Role-play as buyer; evaluate proposal language; identify gaps |
| **Agentforce Sales Coach: Negotiation/Review Role-Play** | Simulate a customer in negotiation scenarios | Role-play as buyer; practice objection handling; competitive positioning |
| **Agentforce Sales Coach: Opportunity Coaching** | Provide feedback after role-play or pitch | Stage-specific feedback; evaluate transcript; suggest next steps |

### Opportunity Stages Supported

Each stage has a dedicated prompt template with stage-specific evaluation criteria:

| Stage | Focus |
|-------|-------|
| **Qualification** | Lead qualification, fit assessment |
| **Needs Analysis** | Discovery, understanding customer needs |
| **Discovery** | Deeper discovery, solution alignment |
| **Proposal/Pricing** | Proposal presentation, pricing discussion |
| **Negotiation/Review** | Objection handling, competitive differentiation, closing |

### Prompt Templates

Feedback is driven by **Prompt Builder** templates that include:

- **Grounding data** – Opportunity, Account, User, and related CRM fields
- **Evaluation criteria** – Stage-specific questions and checklists (e.g., COMPETITOR_HANDLING_CHECKLIST)
- **Feedback format** – Deal Summary, Key Strengths, Areas for Improvement, Next Steps

Example dynamic fields in prompts:

- `{!$Input:Opportunity.Account.Name}`, `{!$Input:Opportunity.StageName}`
- `{!$Input:Opportunity.Amount}`, `{!$Input:Opportunity.Probability}`
- `{!$Input:Opportunity.Description}`, `{!$Input:Opportunity.NextStep}`
- `{!$Input:Transcript}` – Rep's role-play or pitch transcript

---

## 4. Assets Used

### Platform Assets (Required for Setup)

| Asset | Purpose |
|-------|---------|
| **Data 360** | Host files; support RAG for knowledge grounding |
| **Agentforce Studio** | Configure topics, actions; power role-play and feedback |
| **Einstein Generative AI** | Power prompt templates; guide LLM feedback generation |
| **Agentforce** | Configure and manage agents |

### Permission Sets

| Permission Set | Purpose |
|----------------|---------|
| **Manage Agentforce Sales Coach** | Admins/managers configure and manage the agent |
| **Use Agentforce Sales Coach** | Sales reps receive coaching and use the agent |

### Agent User

- Dedicated Salesforce user with **Einstein Agent** license
- Profile: **Einstein Agent User**
- Permission set: **Agentforce Sales Coach**
- Operates as the autonomous coach; no outbound email to prospects (unlike SDR)

### Lightning Component

- **Agentforce Sales Coach** – Added to Opportunity record page (Lightning App Builder)
- Primary interface for reps to engage with the coach

### Data Library (Optional for RAG)

- Can host coaching best practices, playbooks, competitor info
- Used for RAG grounding when configured
- Data 360 powers ingestion, chunking, indexing, retrieval

---

## 5. Cloud Dependencies

### 5.1 Data 360 (Data Cloud)

**Data 360** is required for Agentforce Sales Coach setup.

| Dependency | Role |
|------------|------|
| **Data Library** | Host files (playbooks, best practices); support RAG for knowledge grounding |
| **RAG Grounding** | Retrieve relevant content to augment feedback prompts |
| **Search Index** | Chunked, vectorized data for semantic search |

**Note:** Unlike the SDR agent, Sales Coach does not rely on Data Library for prospect-facing FAQ responses. RAG is used primarily for coaching content (best practices, playbooks) when a Data Library is configured.

### 5.2 Einstein Platform

| Component | Role |
|-----------|------|
| **Einstein Generative AI** | Powers prompt templates; LLM generates feedback |
| **Einstein Trust Layer** | Security, audit, governance |
| **Atlas Reasoning Engine** | Topic routing, action selection |

### 5.3 Sales Cloud

| Component | Role |
|-----------|------|
| **Opportunity** | Primary context; stage, amount, probability, description, next steps |
| **Account** | Customer context; industry, description |
| **User** | Rep identity; first name, etc. |
| **Tasks** | Overdue task detection (`HasOverdueTask`) |

### 5.4 Licensing and Editions

- **Editions**: Enterprise, Performance, or Unlimited
- **Add-on**: Agentforce Sales Coach license
- **Agent License**: Einstein Agent license per Sales Coach user

---

## 6. Analysis: Replacing Data 360 with a Custom/Customer-Provided Alternative

### 6.1 Context

Data 360 is required for Sales Coach setup and powers Data Libraries used for RAG grounding. Organizations may want to replace it with customer-owned or third-party alternatives for coaching content.

### 6.2 What Data 360 Provides for Sales Coach

| Capability | Data 360 Role | Replacement Implication |
|------------|---------------|--------------------------|
| **File Hosting** | Store playbooks, best practices, competitor info | Host content in your system |
| **Chunking & Indexing** | Prepare content for retrieval | Implement in your pipeline |
| **RAG Retrieval** | Augment feedback prompts with relevant content | Provide retrieval API or action |
| **Setup Requirement** | Sales Coach setup wizard requires Data 360 enabled | May need workaround if Data 360 is not available |

### 6.3 Sales Coach vs SDR: Data 360 Dependency

| Aspect | SDR Agent | Sales Coach |
|--------|-----------|-------------|
| **Primary data source** | Data Library for prospect FAQs, pricing | CRM (Opportunity, Account) + optional Data Library for playbooks |
| **RAG criticality** | High for Respond to Prospect | Lower; feedback is driven by prompt templates + CRM data |
| **Replacement impact** | High – core to answering prospect questions | Moderate – coaching can work with CRM-only; RAG enhances with playbooks |

### 6.4 Replacement Options

#### Option A: CRM-Only (No Data Library)

**Mechanism:** Use only prompt templates with CRM data (Opportunity, Account, User). No Data Library, no RAG.

**Pros:** No Data 360 dependency for content; feedback still personalized via CRM fields.

**Cons:** Setup wizard may require Data 360 to be enabled; no retrieval of playbooks or best practices.

**Use case:** Organizations that rely on prompt template logic and CRM data only.

#### Option B: Custom Retriever for Coaching Content

**Mechanism:** Build a custom retriever (Einstein Studio) or Apex action that fetches coaching content from an external source (e.g., SharePoint, Confluence, internal wiki).

**Requirements:**

- Custom retriever or invocable action
- External API or connector to your knowledge base
- Response format compatible with agent expectations

**Use case:** Coaching playbooks and best practices stored outside Salesforce.

#### Option C: Skill-Based Instructions (Agent Script Equivalent)

**Mechanism:** If building a custom Sales Coach–like agent with Agent Script, embed coaching guidelines in Agent Skills (e.g., `Agent_Skills_Repo__c`) instead of Data Library.

**Pros:** No Data Cloud; content in CRM records.

**Cons:** Static content; no semantic search; updates require record changes.

#### Option D: Prompt Template + External API

**Mechanism:** Custom Apex/Flow action invoked by the agent that:

1. Accepts context (opportunity ID, stage, transcript)
2. Calls external API for coaching content or evaluation
3. Returns content for prompt augmentation

**Pros:** Full control over data source and logic.

**Cons:** Custom development; agent must invoke action; may not integrate with standard Sales Coach UX.

### 6.5 Trade-Offs Summary

| Approach | Data 360 Required | Custom Code | Coaching Content Source |
|----------|-------------------|-------------|-------------------------|
| Default (Data Library) | Yes | No | Data Library files |
| CRM-only prompts | Setup may require | No | CRM fields only |
| Custom retriever | Yes (indexing) | Moderate | External via retriever |
| Skill-based (custom agent) | No | Yes | Agent_Skills_Repo__c |
| Apex/Flow + External API | No | High | External system |

### 6.6 Implementation Considerations

1. **Setup Wizard:** Sales Coach setup explicitly requires Data 360. Verify if the wizard can be bypassed or if Data 360 must be enabled for activation.

2. **Feedback Quality:** CRM data (Opportunity, Account) drives most feedback. RAG adds playbooks and best practices. Replacing Data 360 has less impact than for SDR if prompts are well-designed.

3. **Prompt Template Design:** Maximize use of CRM merge fields (`{!$Input:Opportunity.*}`) so feedback remains contextual without RAG.

4. **Custom Agent Alternative:** For full control, build an Agent Script–based Sales Coach using Agent Skills for coaching instructions, bypassing Data Library entirely.

### 6.7 Recommendation

- **Data 360 available:** Use Data Library for playbooks and best practices; leverage RAG for richer feedback.
- **Data 360 restricted:** Rely on CRM-grounded prompt templates; consider custom retriever if external coaching content is critical.
- **Full custom:** Build Agent Script Sales Coach with Agent Skills; use `apex://Agent_Skill_LoadAndCompose` for coaching instructions; no Data 360 required.

---

## 7. Related Documents

- [Agentforce SDR Agent Reference](Agentforce%20SDR%20Agent%20Reference.md) – Built-in SDR agent reference
- [SDR Agent Implementation Plan](SDR%20Agent%20Implementation%20Plan.md) – Plan for Agent Script–based SDR agent
- [LTM Integration Mapping](LTM%20Integration%20Mapping.md) – Agent_Context__c and flow contracts
- [Agent Script Manual v4](Agent%20Script%20Manual%20v4.md) – Agent Script reference
