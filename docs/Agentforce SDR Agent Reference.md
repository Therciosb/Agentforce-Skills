# Agentforce SDR Agent Reference

Reference document for the built-in Agentforce SDR (Lead Nurturing) agent: capabilities, assets, cloud dependencies, and analysis of replacing Data 360 with custom alternatives.

---

## 1. Overview

The **Agentforce SDR Agent** (also called **Agentforce Lead Nurturing**) is Salesforce's pre-built AI-powered Sales Development Representative that operates within Sales Cloud. It serves as the first point of contact for inbound leads, conducts personalized outreach, answers prospect questions, qualifies leads, and books meetings on behalf of sales representatives.

### Key Characteristics

- **24/7 operation** across supported channels
- **Autonomous** within guardrails (plans, reasons, executes without human intervention)
- **Native to Salesforce** – uses CRM data, metadata, and platform automation
- **Built on Atlas Reasoning Engine** – topic classification, agentic loops, advanced RAG

---

## 2. Capabilities


| Capability              | Description                                                                              |
| ----------------------- | ---------------------------------------------------------------------------------------- |
| **Send Outreach**       | Proactive intro emails and follow-up sequences; personalized based on lead/account data  |
| **Respond to Prospect** | Answer FAQs, pricing, product questions using approved content                           |
| **Manage Opt-Out**      | Respect and process opt-out requests; update Do Not Contact preferences                  |
| **Lead Qualification**  | Evaluate prospects using CRM data, engagement history, BANT; update qualification fields |
| **Meeting Scheduling**  | Propose and book meetings; hand off to assigned rep with full context                    |
| **Handoff to Rep**      | Transfer qualified leads with complete conversation and qualification context            |


---

## 3. Topics and Actions

The built-in SDR agent is organized around three main topics:


| Topic                   | Purpose                               | Key Actions                                             |
| ----------------------- | ------------------------------------- | ------------------------------------------------------- |
| **Send Outreach**       | Proactive lead engagement             | Draft intro email, follow-up, nudge sequences           |
| **Respond to Prospect** | Answer questions and handle inquiries | FAQ responses, pricing/product info, objection handling |
| **Manage Opt-Out**      | Handle prospect preferences           | Update Do Not Contact, respect opt-out status           |


### Pre-Built Prompt Templates

When Lead Nurturing is enabled, the agent includes at least five prompt templates:

1. **Draft Agentforce SDR Intro Email** – Initial outreach / first introduction
2. **Follow-up on Agentforce SDR** – Follow-up and nudge sequences
3. Additional templates for email variations, meeting invites, etc.

### Standard Actions

The agent can use Agentforce standard actions:

- **Update Record** – BANT, Lead Status, opt-out fields
- **Create Record** – Event for meeting scheduling
- **Query Records** / **Get Record Details** – Lead/Contact lookup, engagement history
- **Draft or Revise Email** – Draft emails with conversation context

---

## 4. Assets Used

### Platform Assets (Auto-Enabled with Lead Nurturing)


| Asset                         | Purpose                                                      |
| ----------------------------- | ------------------------------------------------------------ |
| **Sales Engagement**          | Cadences, outreach automation, email delivery                |
| **Automated Actions**         | Agent-triggered actions (e.g., field updates, task creation) |
| **Einstein Activity Capture** | Email sync, calendar sync; agent activity visibility in CRM  |
| **Email Productivity**        | Email composition, sending, tracking                         |


### Permission Sets


| Permission Set                       | Purpose                                              |
| ------------------------------------ | ---------------------------------------------------- |
| **Configure Agentforce SDR Agent**   | Admins/managers configure the agent                  |
| **Use Agentforce SDR Agent**         | Sales users assign prospects and view agent activity |
| **Sales Engagement Cadence Creator** | Manage outreach cadences                             |
| **Automated Actions User**           | Execute agent actions                                |


### Agent User

- Dedicated Salesforce user with **Einstein Agent** license
- Runs autonomously for outreach and responses
- Email configured via Einstein Activity Capture for outbound delivery

### Data Library

- Configured in Setup → Agentforce Data Library
- Sources: FAQs, pricing sheets, product info, competitor comparisons, etc.
- Used for RAG grounding in Respond to Prospect

---

## 5. Cloud Dependencies

### 5.1 Data 360 (Data Cloud)

**Data 360** (formerly Data Cloud) is the foundational data layer for Agentforce agents.


| Dependency         | Role                                                                                                              |
| ------------------ | ----------------------------------------------------------------------------------------------------------------- |
| **Data Library**   | Data Libraries are powered by Data Cloud. Content is ingested, chunked, indexed, and stored for retrieval.        |
| **RAG Grounding**  | Semantic search, vector embeddings, and retrieval use Data Cloud infrastructure.                                  |
| **Real-Time Data** | Agents access structured and unstructured data from CRM, knowledge articles, and external sources via Data Cloud. |


**Data 360 Architecture (High Level):**

- **Ingestion**: 270+ connectors, APIs, web crawlers; zero-copy federation
- **Storage**: Data Lake Objects (DLOs), Unstructured Data Lake Objects (UDLOs)
- **Unification**: Data Model Objects (DMOs) using C360 Data Model
- **Indexing**: Search indexes with vector embeddings (e.g., E5-Large-V2), chunking (~512 tokens)
- **Activation**: Reporting, Einstein Studio, segmentation, agent grounding

**Agent Requirements from Data 360:**

- Real-time, low-latency data access
- Unified data across CRM and external sources
- Security, governance, lineage, consent awareness
- Knowledge management (chunking, indexing, retrieval)

### 5.2 Einstein Platform


| Component                  | Role                                                                   |
| -------------------------- | ---------------------------------------------------------------------- |
| **Einstein for Sales**     | Required for SDR; pricing, forecasting, AI features                    |
| **Einstein Trust Layer**   | Zero data retention, toxicity detection, secure retrieval, audit trail |
| **Atlas Reasoning Engine** | Topic classification, agentic loops, advanced RAG                      |


### 5.3 Sales Cloud


| Component          | Role                                                               |
| ------------------ | ------------------------------------------------------------------ |
| **Sales Cloud**    | Lead, Contact, Account, Activity objects; standard sales processes |
| **Lead Nurturing** | SDR agent template and configuration                               |


### 5.4 Licensing and Editions

- **Editions**: Enterprise, Performance, or Unlimited
- **Products**: Sales Cloud + Einstein for Sales
- **Agent License**: Einstein Agent license per SDR agent user

---

## 6. Analysis: Replacing Data 360 with a Custom/Customer-Provided Alternative

### 6.1 Context

Data 360 powers Data Libraries and RAG grounding for Agentforce. Organizations may want to replace it with:

- Customer-owned data lakes or warehouses
- Third-party vector databases (Pinecone, Weaviate, etc.)
- External knowledge bases or APIs
- Custom RAG pipelines outside Salesforce

### 6.2 What Data 360 Provides for Agentforce


| Capability            | Data 360 Role                      | Replacement Implication                     |
| --------------------- | ---------------------------------- | ------------------------------------------- |
| **Ingestion**         | Connectors, web crawlers, APIs     | Custom ingestion must feed your alternative |
| **Chunking**          | Token-based chunking (~512 tokens) | Implement chunking in your pipeline         |
| **Vector Embeddings** | E5-Large-V2 or similar             | Use your own embedding model                |
| **Search Index**      | Semantic + keyword hybrid search   | Provide vector + keyword search             |
| **Retrieval API**     | Agent queries index, gets chunks   | Implement retrieval endpoint for agents     |
| **Storage**           | DLOs, UDLOs, DMOs                  | Data resides in your system                 |


### 6.3 Replacement Options

#### Option A: Custom Retrievers (Einstein Studio)

**Mechanism:** Build custom retrievers in Einstein Studio that query Data Model Objects or Search Indexes. Data Cloud still indexes the data, but custom retrievers control what is returned.

**Limitation:** Data Cloud remains the indexing layer. Custom retrievers are for *filtering* and *targeting*, not for *replacing* Data Cloud entirely.

**Use case:** Fine-grained control over what data is returned to agents.

#### Option B: External Data via Custom Retriever / Apex

**Mechanism:** Implement a custom retriever or Apex invocable action that:

1. Accepts a query from the agent
2. Calls your external API, vector DB, or data lake
3. Returns chunks/results in the format the agent expects

**Requirements:**

- Custom retriever interface (if supported by Agentforce) or Apex action that the agent invokes
- Your data source must support semantic search or keyword search
- Chunking and embedding must be done in your pipeline
- Response format must match what the agent expects (e.g., chunks with metadata for citations)

**Implementation path:** Custom Apex `@InvocableMethod` that calls an external HTTP API or uses a connector.

#### Option C: Skill-Based Grounding (No Data Library)

**Mechanism:** Use Agent Skills (or similar) to embed static content in instructions. No Data Library, no RAG.

**Pros:** No Data Cloud dependency; no custom retriever needed.

**Cons:** No real-time retrieval; content must be in Agent_Skills_Repo__c or similar; updates require record changes; no semantic search.

**Use case:** Small, stable knowledge sets (FAQs, policies) that change infrequently.

#### Option D: Prompt Builder + External Data

**Mechanism:** Implement a custom Apex or Flow action that:

1. Accepts a user query
2. Fetches from your external system
3. Injects retrieved content into a prompt template
4. Returns the response to the agent

**Pros:** Full control over data source and retrieval logic.

**Cons:** More custom code; may not integrate with Agentforce Data Library UX; requires agent to invoke the action explicitly.

### 6.4 Trade-Offs Summary


| Approach                           | Data Cloud Required | Custom Code | Real-Time Retrieval   | Semantic Search |
| ---------------------------------- | ------------------- | ----------- | --------------------- | --------------- |
| Data Library (default)             | Yes                 | No          | Yes                   | Yes             |
| Custom Retriever (Einstein Studio) | Yes (indexing)      | Moderate    | Yes                   | Yes             |
| Apex/Flow + External API           | No                  | High        | Yes (if API supports) | Depends on API  |
| Skill-Based Instructions           | No                  | Low         | No                    | No              |


### 6.5 Implementation Considerations for Custom Alternative

1. **Retrieval Contract:** Agentforce expects a specific format for RAG results (chunks, metadata, citations). Your external system must match this.
2. **Latency:** Agent interactions are synchronous. External retrieval latency must be acceptable (typically < 2–3 seconds).
3. **Security:** Data must be accessible from the Salesforce org (e.g., via Named Credential, MuleSoft, or secure API). Consider data residency and compliance.
4. **Governance:** Custom solutions may not inherit Einstein Trust Layer features (audit, toxicity, etc.). Ensure alignment with governance requirements.
5. **Maintenance:** Custom pipelines require ongoing maintenance for ingestion, chunking, indexing, and embedding updates.
6. **Migration:** If Data Cloud is required today, migration to a custom alternative requires agent reconfiguration and testing.

### 6.6 Recommendation

- **Data Cloud available:** Use Data Libraries for RAG grounding. Use custom retrievers only when you need more control over retrieval logic.
- **Data Cloud not available or restricted:** Use skill-based instructions for static content, or a custom Apex/Flow action that calls an external retrieval API. Ensure the agent can invoke the action and consume the response format.
- **Hybrid:** Use Data Library for core CRM/knowledge content and a custom action for external or specialized data sources.

---

## 7. Related Documents

- [SDR Agent Implementation Plan](SDR%20Agent%20Implementation%20Plan.md) – Plan for implementing an Agent Script–based SDR agent
- [LTM Integration Mapping](LTM%20Integration%20Mapping.md) – Agent_Context__c and flow contracts
- [Agent Script Manual v4](Agent%20Script%20Manual%20v4.md) – Agent Script reference

