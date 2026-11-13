# Skills Admin App Redesign — Design

**Date:** 2026-07-14
**Branch:** `worktree-progressive-disclosure`
**Status:** Approved design, pending implementation plan
**Target org:** `myDevOrg` (`00DKY00000gXHJ52AO`) — every `sf` command passes `--target-org myDevOrg`.

---

## 1. Problem & Goal

The `Agent_Skills_Admin` app today is bare: standard Home + a raw `Agent_Skills_Repo__c`
object tab with default record pages. Authoring a skill means hand-filling every field
(`Name`, `Type__c`, `WhenToUse__c`, `InstructionBody__c`, `References__c`, …) with no
guidance, and there is no way to see how a skill's dependencies cascade at runtime.

We want three improvements, all on the **enhanced-record-page + LWC** approach (stay close to
standard Salesforce UX; no single-page console rewrite):

1. **Better UI layout** — a redesigned Home app page and a tabbed skill record page.
2. **Skill Builder** — a minimal form (intent + type + optional reference document) that calls
   a Prompt Builder template to generate skill-field JSON, which Apex parses into a new
   **Draft** `Agent_Skills_Repo__c` record for the admin to review and activate.
3. **Dependency Tree** — a read-only visualization of a selected skill's **downstream**
   `References__c` cascade (what it loads at runtime), embedded on the record page.

## 2. Non-Goals

- No change to the runtime pipeline (`Agent_Skill_Loader` / `Composer` / `LoadAndCompose`) or
  to any agent bundle. This is admin-app UX only.
- No new fields on `Agent_Skills_Repo__c` (all needed fields already exist).
- No single-page/console app rewrite; keep the standard app + object tab.
- No upstream/reverse-dependency or data-health view in the tree (downstream-only, per D6).
- No external visualization library (D7) and no PDF-parsing dependency (D4).
- The Builder does **not** auto-activate skills — it always creates Draft (D3).

## 3. Key Design Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Enhanced record pages + focused LWCs (not a console app) | Lighter build, standard UX, matches user choice. |
| D2 | Skill Builder inputs = **minimal**: skill `type` + free-text `intent` + **optional** document upload | Lowest admin effort; the prompt template does the heavy lifting; the doc enriches/grounds. |
| D3 | Builder **auto-creates a Draft** record, admin reviews/activates | Human approval before anything goes live; fastest happy path. |
| D4 | Uploaded doc → **extract text, pass inline** to the template; text/markdown/HTML reliable, PDF best-effort | No external parsing dependency; clear UI note about supported formats. |
| D5 | Generation is a **Prompt Builder template** (`genAiPromptTemplate`) invoked from Apex via `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate`; returns **strict JSON** | Standard deployable path; strict JSON lets Apex parse deterministically. **Verified on `myDevOrg`:** `ConnectApi.EinsteinLLM` and `ConnectApi.EinsteinPromptTemplateGenerationsInput` are both available. |
| D6 | Dependency tree = **downstream only** (what the skill loads), loader-faithful | Mirrors runtime cascade; focused, matches user choice. |
| D7 | Tree renders with **`lightning-tree`** (standard base component), no D3/libs | Dependency-free, SLDS-consistent. |
| D8 | Apex owns guardrails (name-prefix ↔ type, CSV normalization, Draft/version/locale/ExternalId) | Don't trust the LLM with structural invariants; keep them deterministic. |

## 4. Architecture

```
Agent Skills Admin app
├── Home  →  App Page (flexipage: Agent_Skills_Home)
│     ├── skillBuilder LWC           (the form + generate action)
│     └── recent/Draft skills list   (standard list view component)
│
├── Skills tab (Agent_Skills_Repo__c) — record page (flexipage: Agent_Skills_Repo_Record)
│     ┌───────────────────────────────┬─────────────────────────────┐
│     │ Details (tabbed record form)  │ skillDependencyTree LWC     │
│     │  • Overview                   │  root = this record          │
│     │  • Instruction Body           │  downstream References cascade│
│     │  • References                 │                              │
│     └───────────────────────────────┴─────────────────────────────┘
│
└── Apex + Prompt Template behind the two LWCs
```

### 4.1 Skill Builder pipeline

```
skillBuilder (LWC)
  │  inputs: skillType (radio), intent (textarea), optional file (lightning-file-upload)
  │  1. if file uploaded → contentVersionId captured
  ▼
Agent_Skill_Builder.generateSkill(intent, skillType, contentVersionId)   @AuraEnabled
  │  2. if contentVersionId: extract text from ContentVersion.VersionData
  │       - text/markdown/html/csv → decode blob to string (cap ~100k chars)
  │       - other (pdf/docx) → skip with a warning appended to the response
  │  3. invoke prompt template Generate_Agent_Skill with {intent, skillType, referenceText}
  │       via ConnectApi.EinsteinLLM / aiplatform prompt-template invocation
  │  4. parse strict JSON → SkillDraft {name,type,description,whenToUse,instructionBody,
  │       references[], priority}
  │  5. guardrails:
  │       - force Name to start with the prefix for skillType
  │         (role- / core-skill- / skill- / workflow-); slugify if needed
  │       - references[] → no-spaces CSV, drop blanks
  │       - Status__c='Draft', Version__c='v1', Locale__c='en-US',
  │         ExternalId__c = name+':v1:en-US'
  │  6. insert Agent_Skills_Repo__c (Draft)
  │  7. return {recordId, warnings, rawJson}
  ▼
skillBuilder navigates to the new Draft record (NavigationMixin) or shows warnings/errors.
```

**Prompt template `Generate_Agent_Skill`** (Flex type): inputs `intent` (Text),
`skillType` (Text), `referenceText` (Text, optional). Output: a single JSON object, no prose,
matching:

```json
{
  "name": "skill-...",
  "type": "Skill",
  "description": "one-line summary",
  "whenToUse": "Use when ... (rich, example-laden routing header)",
  "instructionBody": "# ...markdown body...",
  "references": ["workflow-...", "core-skill-..."],
  "priority": 5
}
```

The template's system text instructs: emit ONLY valid JSON; follow the naming prefix for the
given `skillType`; write a detailed `whenToUse` (routing header) with example utterances; ground
`instructionBody` and `references` in `referenceText` when provided; never invent tool names.

### 4.2 Dependency Tree

```
skillDependencyTree (LWC) — record page right column, gets recordId
  ▼
Agent_Skill_DependencyProvider.getTree(recordId)   @AuraEnabled(cacheable=true)
  │  - load the record's Name
  │  - BFS over Agent_Skills_Repo__c WHERE Status__c='active', parsing References__c,
  │    depth-cap ≤ 6, cycle-safe (visited set; repeat node marked seen=true, not re-expanded)
  │  - build nested nodes {name, label, type, status, seen, children[]}
  ▼
lightning-tree renders; node metatext = Type badge; onselect → NavigationMixin to that record.
```

Expansion semantics **match `Agent_Skill_Loader.expandReferencesFromLoaded`**: active-only,
same `References__c` CSV parsing, depth ≤ 6, cycle-safe — so the tree is a faithful preview of
runtime loading.

## 5. UI Layout Detail

- **Home App Page (`Agent_Skills_Home` flexipage):** header region with the `skillBuilder`
  card; below it a `Recent` / Draft-skills list (standard `report`/list component filtered to
  `Status__c = Draft`) so newly generated skills are one click away.
- **Record Page (`Agent_Skills_Repo_Record` flexipage):** two-column. Left = record detail with
  a tabbed layout — **Overview** (Name, Type, Status, Version, WhenToUse, Priority),
  **Instruction Body** (the long text), **References** (the CSV field). Right = `skillDependencyTree`.
- Both flexipages are assigned via the app (`Agent_Skills_Admin`) and the object.

## 6. Deliverables

1. `skillBuilder` LWC (+ meta) — form, file upload, generate button, error/warning display.
2. `Agent_Skill_Builder.cls` (+ test) — text extraction, template invocation, JSON parse,
   guardrails, Draft insert.
3. `Generate_Agent_Skill` `genAiPromptTemplate` (+ meta) — strict-JSON skill generator.
4. `skillDependencyTree` LWC (+ meta) — `lightning-tree` renderer, node navigation.
5. `Agent_Skill_DependencyProvider.cls` (+ test) — cacheable, loader-faithful tree builder.
6. `Agent_Skills_Home` flexipage (App Page) + `Agent_Skills_Repo_Record` flexipage (Record Page).
7. App/tab wiring: add the Home app page to `Agent_Skills_Admin`; assign the record page.
8. Permission-set updates: grant admin profiles/perm sets access to the two new Apex classes
   (author/reviewer/consumer perm sets as appropriate) and the prompt template.
9. Docs update (README / FDE doc) describing the admin app features.

## 7. Testing Strategy

- **Apex — `Agent_Skill_Builder_Test`:** JSON parse happy path; name-prefix enforcement per
  type; references CSV normalization (no spaces); Draft/version/locale/ExternalId defaults;
  malformed-JSON path returns error not exception; text extraction from a text ContentVersion;
  unsupported-file warning path. Prompt-template call is mocked/stubbed (inject the raw JSON via
  a test seam so tests don't require a live model).
- **Apex — `Agent_Skill_DependencyProvider_Test`:** linear chain; branching; cycle
  (workflow→escalate referenced by multiple parents → seen marker, no infinite loop);
  inactive references excluded; depth cap; missing record.
- **LWC — Jest:** `skillBuilder` renders inputs, disables Generate until intent present, calls
  Apex, navigates on success, shows warnings; `skillDependencyTree` renders a nested tree from
  mock Apex data and fires navigation on select.
- **Manual/org:** deploy to `myDevOrg`, open the app, generate a skill from an intent (+ a
  sample .md doc), confirm a Draft record is created and the tree renders on a seeded skill
  (e.g. `skill-troubleshooting-support`).

## 8. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Prompt template returns non-JSON / extra prose | Apex extracts the first `{...}` block, parses defensively, returns raw text + error to the LWC on failure (no silent insert). |
| Prompt-template invocation API differs by org/version | Isolate the call in one Apex method with a test seam; document the exact `ConnectApi`/invocation used; validate on `myDevOrg` during implementation. |
| PDF/binary upload yields garbage text | Only decode known text MIME types; other types skipped with a clear warning; UI notes "text, markdown, HTML work best". |
| LLM invents a bad Name or wrong prefix | Apex overrides prefix by `skillType` and slugifies; never trusts the model's `name` verbatim. |
| Large document blows past prompt limits | Cap extracted text (~100k chars) before passing to the template. |
| Tree cycles / deep chains | Visited-set cycle guard + depth cap ≤ 6, matching the loader. |
| Admin lacks access to new Apex/template | Perm-set grants in scope (deliverable 8). |

## 9. Deployment

Implement on the current branch; deploy to **`myDevOrg`** with explicit `--target-org myDevOrg`.
Order: Apex + prompt template + LWCs + flexipages + perm sets, then assign pages and smoke-test
in the app. LWC Jest via `npm run test:unit`; Apex via `sf apex run test`.
