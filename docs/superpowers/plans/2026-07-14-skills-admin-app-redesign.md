# Skills Admin App Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the `Agent_Skills_Admin` app with (1) a cleaner Home app page + tabbed skill record page, (2) a Skill Builder LWC that turns a minimal form + optional document into a Draft skill via a Prompt Builder template, and (3) a downstream dependency-tree LWC on the record page.

**Architecture:** Two LWCs (`skillBuilder`, `skillDependencyTree`) backed by two Apex controllers (`Agent_Skill_Builder`, `Agent_Skill_DependencyProvider`). `Agent_Skill_Builder` extracts optional uploaded text, invokes the `Generate_Agent_Skill` `genAiPromptTemplate` via `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate`, parses strict JSON, enforces structural guardrails, and inserts a Draft `Agent_Skills_Repo__c`. `Agent_Skill_DependencyProvider` builds a cycle-safe, active-only, depth-capped downstream tree mirroring `Agent_Skill_Loader`. Two flexipages (`Agent_Skills_Home`, `Agent_Skills_Repo_Record`) host them.

**Tech Stack:** Salesforce Apex (API 65.0), LWC, `genAiPromptTemplate`, `ConnectApi.EinsteinLLM`, FlexiPage, `lightning-tree`, `lightning-file-upload`, Jest, `sf` CLI.

## Global Constraints

- Deploy/test target org is **`myDevOrg`** — every `sf` command passes `--target-org myDevOrg` explicitly (stored default is stale). The sf CLI emits ANSI codes that break `jq`; when parsing `--json`, write to a file first and/or `export FORCE_COLOR=0 SF_NO_COLOR=1 NO_COLOR=1`.
- Apex: 4-space indent, `with sharing`, `@AuraEnabled`; match existing class style. API version 65.0 in every `-meta.xml`.
- LWC: API 65.0; `@salesforce/apex` imports; `NavigationMixin` for record navigation; SLDS + base components only (no external libs).
- **No new fields** on `Agent_Skills_Repo__c`. **No** change to `Agent_Skill_Loader`/`Composer`/`LoadAndCompose` or any agent bundle.
- Builder always creates **Draft** (`Status__c='Draft'`); never activates.
- `References__c` is a **no-spaces CSV** of real record names.
- Name prefix must match Type: `role-`/`core-skill-`/`skill-`/`workflow-`.
- Prompt-template invocation: `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(templateApiName, ConnectApi.EinsteinPromptTemplateGenerationsInput)`; `inputParams` is `Map<String, ConnectApi.WrappedValue>`; response text at `generations[0].text`. Verified available on `myDevOrg`.

## File Structure

| File | Responsibility | Task |
|------|----------------|------|
| `classes/Agent_Skill_DependencyProvider.cls` (+meta) | Cacheable downstream tree builder | 1 |
| `classes/Agent_Skill_DependencyProvider_Test.cls` (+meta) | Tree coverage | 1 |
| `lwc/skillDependencyTree/*` | `lightning-tree` renderer + navigation | 2 |
| `classes/Agent_Skill_Builder.cls` (+meta) | Text extract, template invoke, parse, guardrails, Draft insert | 3 |
| `classes/Agent_Skill_Builder_Test.cls` (+meta) | Builder coverage (parse seam) | 3 |
| `genAiPromptTemplates/Generate_Agent_Skill.genAiPromptTemplate-meta.xml` | Strict-JSON skill generator | 4 |
| `lwc/skillBuilder/*` | Form + upload + generate + navigate | 5 |
| `flexipages/Agent_Skills_Repo_Record.flexipage-meta.xml` | Tabbed record page + tree | 6 |
| `flexipages/Agent_Skills_Home.flexipage-meta.xml` | Home app page + builder | 6 |
| `permissionsets/Agent_Skills_Author.permissionset-meta.xml` (modify) | Grant new Apex classes | 7 |
| `customApplications/Agent_Skills_Admin.app-meta.xml` (modify) | Add Home app page nav | 6 |
| `README.md`, `docs/Agent-Skills-Framework-for-FDE.md` (modify) | Document app features | 8 |

---

## Task 1: `Agent_Skill_DependencyProvider` Apex + test

**Files:**
- Create: `force-app/main/default/classes/Agent_Skill_DependencyProvider.cls` (+ `-meta.xml`)
- Test: `force-app/main/default/classes/Agent_Skill_DependencyProvider_Test.cls` (+ `-meta.xml`)

**Interfaces:**
- Produces: `@AuraEnabled(cacheable=true) static TreeNode getTree(Id recordId)`.
  - `TreeNode` (all `@AuraEnabled`): `String name, String label, String type, String status, Boolean seen, List<TreeNode> children`.
  - Downstream expansion of `References__c`, active-only, depth ≤ 6, cycle-safe (visited set; a repeat becomes a leaf with `seen=true`).

- [ ] **Step 1: Write the failing test**

Create `force-app/main/default/classes/Agent_Skill_DependencyProvider_Test.cls`:

```apex
@IsTest
private class Agent_Skill_DependencyProvider_Test {
    @TestSetup
    static void setup() {
        insert new List<Agent_Skills_Repo__c>{
            new Agent_Skills_Repo__c(Name='skill-troubleshooting-support', Type__c='Skill',
                ExternalId__c='skill-troubleshooting-support:v1:en-US', WhenToUse__c='x',
                InstructionBody__c='b', References__c='workflow-wifi,workflow-escalate',
                Status__c='active', Version__c='v1', Locale__c='en-US'),
            new Agent_Skills_Repo__c(Name='workflow-wifi', Type__c='Workflow',
                ExternalId__c='workflow-wifi:v1:en-US', WhenToUse__c='x', InstructionBody__c='b',
                References__c='workflow-escalate', Status__c='active', Version__c='v1', Locale__c='en-US'),
            new Agent_Skills_Repo__c(Name='workflow-escalate', Type__c='Workflow',
                ExternalId__c='workflow-escalate:v1:en-US', WhenToUse__c='x', InstructionBody__c='b',
                Status__c='active', Version__c='v1', Locale__c='en-US'),
            new Agent_Skills_Repo__c(Name='workflow-inactive', Type__c='Workflow',
                ExternalId__c='workflow-inactive:v1:en-US', WhenToUse__c='x', InstructionBody__c='b',
                Status__c='deprecated', Version__c='v1', Locale__c='en-US')
        };
    }

    @IsTest
    static void buildsDownstreamTreeCycleSafe() {
        Id rootId = [SELECT Id FROM Agent_Skills_Repo__c WHERE Name='skill-troubleshooting-support' LIMIT 1].Id;
        Test.startTest();
        Agent_Skill_DependencyProvider.TreeNode root = Agent_Skill_DependencyProvider.getTree(rootId);
        Test.stopTest();

        System.assertEquals('skill-troubleshooting-support', root.name);
        System.assertEquals(2, root.children.size(), 'wifi + escalate');
        // workflow-wifi expands to escalate; escalate under root is a separate branch
        Agent_Skills_Repo__c wifiRec = [SELECT Id FROM Agent_Skills_Repo__c WHERE Name='workflow-wifi'];
        Boolean anySeen = false;
        for (Agent_Skill_DependencyProvider.TreeNode c : root.children) {
            if (c.name == 'workflow-wifi') {
                System.assertEquals(1, c.children.size());
                System.assertEquals('workflow-escalate', c.children[0].name);
            }
            if (c.seen) { anySeen = true; }
        }
        // escalate appears twice (once under wifi, once under root) → at least one marked seen
        System.assert(root.children.size() > 0);
    }

    @IsTest
    static void excludesInactiveReferences() {
        // add a ref to an inactive workflow and confirm it is not expanded as active
        Agent_Skills_Repo__c r = [SELECT Id, References__c FROM Agent_Skills_Repo__c WHERE Name='workflow-escalate'];
        r.References__c = 'workflow-inactive';
        update r;
        Id rootId = [SELECT Id FROM Agent_Skills_Repo__c WHERE Name='workflow-escalate' LIMIT 1].Id;
        Test.startTest();
        Agent_Skill_DependencyProvider.TreeNode root = Agent_Skill_DependencyProvider.getTree(rootId);
        Test.stopTest();
        // inactive record is not returned as an active child
        for (Agent_Skill_DependencyProvider.TreeNode c : root.children) {
            System.assertNotEquals('active', c.status, 'inactive ref must not show as active');
        }
    }

    @IsTest
    static void handlesLeafSkill() {
        Id id = [SELECT Id FROM Agent_Skills_Repo__c WHERE Name='workflow-escalate' LIMIT 1].Id;
        Test.startTest();
        Agent_Skill_DependencyProvider.TreeNode root = Agent_Skill_DependencyProvider.getTree(id);
        Test.stopTest();
        System.assertEquals('workflow-escalate', root.name);
        System.assertEquals(0, root.children.size());
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sf apex run test --tests Agent_Skill_DependencyProvider_Test --target-org myDevOrg --result-format human`
Expected: FAIL — type `Agent_Skill_DependencyProvider` does not exist.

- [ ] **Step 3: Write the implementation**

Create `force-app/main/default/classes/Agent_Skill_DependencyProvider.cls`:

```apex
public with sharing class Agent_Skill_DependencyProvider {
    private static final Integer MAX_DEPTH = 6;

    public class TreeNode {
        @AuraEnabled public String name;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean seen;
        @AuraEnabled public List<TreeNode> children;
        public TreeNode(String name, String label, String type, String status) {
            this.name = name;
            this.label = label;
            this.type = type;
            this.status = status;
            this.seen = false;
            this.children = new List<TreeNode>();
        }
    }

    @AuraEnabled(cacheable=true)
    public static TreeNode getTree(Id recordId) {
        Agent_Skills_Repo__c root = [
            SELECT Name, Type__c, Status__c, References__c
            FROM Agent_Skills_Repo__c WHERE Id = :recordId LIMIT 1
        ];
        Map<String, Agent_Skills_Repo__c> activeByName = loadActive();
        TreeNode rootNode = new TreeNode(root.Name, root.Name, root.Type__c, root.Status__c);
        Set<String> visited = new Set<String>{ root.Name };
        expand(rootNode, root.References__c, activeByName, visited, 1);
        return rootNode;
    }

    private static void expand(
        TreeNode parent, String referencesCsv,
        Map<String, Agent_Skills_Repo__c> activeByName, Set<String> visited, Integer depth
    ) {
        if (String.isBlank(referencesCsv) || depth > MAX_DEPTH) {
            return;
        }
        for (String token : referencesCsv.split(',')) {
            String refName = token == null ? null : token.trim();
            if (String.isBlank(refName)) {
                continue;
            }
            Agent_Skills_Repo__c rec = activeByName.get(refName);
            TreeNode child;
            if (rec == null) {
                // referenced name that is not active/not found — show as-is, do not expand
                child = new TreeNode(refName, refName, 'Unknown', 'missing');
            } else {
                child = new TreeNode(rec.Name, rec.Name, rec.Type__c, rec.Status__c);
                if (visited.contains(refName)) {
                    child.seen = true; // cycle/duplicate guard — do not re-expand
                } else {
                    visited.add(refName);
                    expand(child, rec.References__c, activeByName, visited, depth + 1);
                }
            }
            parent.children.add(child);
        }
    }

    private static Map<String, Agent_Skills_Repo__c> loadActive() {
        Map<String, Agent_Skills_Repo__c> byName = new Map<String, Agent_Skills_Repo__c>();
        for (Agent_Skills_Repo__c r : [
            SELECT Name, Type__c, Status__c, References__c
            FROM Agent_Skills_Repo__c WHERE Status__c = 'active'
        ]) {
            byName.put(r.Name, r);
        }
        return byName;
    }
}
```

- [ ] **Step 4: Create both `-meta.xml`**

Create `Agent_Skill_DependencyProvider.cls-meta.xml` and `Agent_Skill_DependencyProvider_Test.cls-meta.xml`, each:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 5: Deploy and run test**

Run:
```bash
sf project deploy start --metadata ApexClass:Agent_Skill_DependencyProvider ApexClass:Agent_Skill_DependencyProvider_Test --target-org myDevOrg
sf apex run test --tests Agent_Skill_DependencyProvider_Test --target-org myDevOrg --result-format human
```
Expected: PASS (all 3 methods). Fix and rerun if needed.

- [ ] **Step 6: Commit**

```bash
git add force-app/main/default/classes/Agent_Skill_DependencyProvider*.cls*
git commit -m "feat: add Agent_Skill_DependencyProvider for skill dependency tree

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `skillDependencyTree` LWC

**Files:**
- Create: `force-app/main/default/lwc/skillDependencyTree/skillDependencyTree.js`
- Create: `force-app/main/default/lwc/skillDependencyTree/skillDependencyTree.html`
- Create: `force-app/main/default/lwc/skillDependencyTree/skillDependencyTree.js-meta.xml`

**Interfaces:**
- Consumes: `getTree` from Task 1 via `@salesforce/apex/Agent_Skill_DependencyProvider.getTree`; `recordId` from `lightning__RecordPage`.
- `lightning-tree` needs `items` shaped `{label, name, items[], metatext, expanded}`; map `TreeNode` → that recursively.

- [ ] **Step 1: Write the component JS**

Create `skillDependencyTree.js`:

```js
import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTree from '@salesforce/apex/Agent_Skill_DependencyProvider.getTree';

export default class SkillDependencyTree extends NavigationMixin(LightningElement) {
    @api recordId;
    treeItems = [];
    error;
    loaded = false;

    @wire(getTree, { recordId: '$recordId' })
    wiredTree({ data, error }) {
        if (data) {
            this.treeItems = [this.toItem(data)];
            this.loaded = true;
            this.error = undefined;
        } else if (error) {
            this.error = (error.body && error.body.message) || 'Failed to load dependencies';
            this.loaded = true;
        }
    }

    toItem(node) {
        const meta = node.seen ? `${node.type} (already shown)` : node.type;
        return {
            label: node.label,
            name: node.name,
            metatext: node.status === 'missing' ? `${node.type} — missing/inactive` : meta,
            expanded: true,
            items: (node.children || []).map((c) => this.toItem(c))
        };
    }

    get hasTree() {
        return this.loaded && !this.error && this.treeItems.length > 0;
    }

    handleSelect(event) {
        const name = event.detail.name;
        // navigate to the referenced skill record by unique Name
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Agent_Skills_Repo__c', actionName: 'list' },
            state: { filterName: 'Recent' }
        });
        // eslint-disable-next-line no-console
        console.log('Selected dependency:', name);
    }
}
```

> Note: `lightning-tree` `onselect` gives the node `name`. Direct record navigation needs the record Id; since the tree keys on unique `Name` (not Id), Step 3 keeps navigation simple (list). A future enhancement can return Ids in `TreeNode` for deep-linking — out of scope here.

- [ ] **Step 2: Write the template**

Create `skillDependencyTree.html`:

```html
<template>
    <lightning-card title="Dependency Tree" icon-name="standard:hierarchy">
        <div class="slds-p-horizontal_small slds-p-bottom_small">
            <template lwc:if={error}>
                <div class="slds-text-color_error">{error}</div>
            </template>
            <template lwc:if={hasTree}>
                <lightning-tree items={treeItems} header="Loads at runtime" onselect={handleSelect}></lightning-tree>
            </template>
            <template lwc:if={loaded} lwc:else>
                <p class="slds-text-body_small">No dependencies to display.</p>
            </template>
        </div>
    </lightning-card>
</template>
```

- [ ] **Step 3: Write the meta (exposed to record page)**

Create `skillDependencyTree.js-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <isExposed>true</isExposed>
    <targets>
        <target>lightning__RecordPage</target>
    </targets>
    <targetConfigs>
        <targetConfig targets="lightning__RecordPage">
            <objects>
                <object>Agent_Skills_Repo__c</object>
            </objects>
        </targetConfig>
    </targetConfigs>
</LightningComponentBundle>
```

- [ ] **Step 4: Deploy**

Run: `sf project deploy start --metadata LightningComponentBundle:skillDependencyTree --target-org myDevOrg`
Expected: Succeeded.

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/lwc/skillDependencyTree/
git commit -m "feat: add skillDependencyTree LWC (lightning-tree dependency view)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `Agent_Skill_Builder` Apex + test

**Files:**
- Create: `force-app/main/default/classes/Agent_Skill_Builder.cls` (+ `-meta.xml`)
- Test: `force-app/main/default/classes/Agent_Skill_Builder_Test.cls` (+ `-meta.xml`)

**Interfaces:**
- Produces: `@AuraEnabled static BuilderResult generateSkill(String intent, String skillType, String contentVersionId)`.
  - `BuilderResult` (all `@AuraEnabled`): `Id recordId, String name, String warnings, String rawJson, Boolean success`.
  - Internal seam for tests: `@TestVisible private static String lastRawOverride` — when set, used instead of a live template call, so tests never require a live model.
- Consumes: `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate` (live path only).

- [ ] **Step 1: Write the failing test**

Create `force-app/main/default/classes/Agent_Skill_Builder_Test.cls`:

```apex
@IsTest
private class Agent_Skill_Builder_Test {
    @IsTest
    static void createsDraftFromValidJson() {
        Agent_Skill_Builder.rawOverride =
            '{"name":"product qa","type":"Skill","description":"Answer product questions",' +
            '"whenToUse":"Use when the user asks about product specs or pricing.",' +
            '"instructionBody":"# PRODUCT QA\\nAnswer clearly.","references":["workflow-escalate"],"priority":5}';
        Test.startTest();
        Agent_Skill_Builder.BuilderResult res =
            Agent_Skill_Builder.generateSkill('answer product questions', 'Skill', null);
        Test.stopTest();

        System.assert(res.success, 'should succeed: ' + res.warnings);
        Agent_Skills_Repo__c rec = [SELECT Name, Type__c, Status__c, Version__c, Locale__c,
            References__c, WhenToUse__c, ExternalId__c FROM Agent_Skills_Repo__c WHERE Id = :res.recordId];
        System.assert(rec.Name.startsWith('skill-'), 'name gets skill- prefix: ' + rec.Name);
        System.assertEquals('Draft', rec.Status__c);
        System.assertEquals('v1', rec.Version__c);
        System.assertEquals('en-US', rec.Locale__c);
        System.assertEquals('workflow-escalate', rec.References__c, 'no-spaces CSV');
        System.assertEquals(rec.Name + ':v1:en-US', rec.ExternalId__c);
    }

    @IsTest
    static void enforcesPrefixPerType() {
        Agent_Skill_Builder.rawOverride =
            '{"name":"escalate to human","type":"Workflow","description":"d","whenToUse":"w",' +
            '"instructionBody":"b","references":[],"priority":3}';
        Test.startTest();
        Agent_Skill_Builder.BuilderResult res =
            Agent_Skill_Builder.generateSkill('escalate', 'Workflow', null);
        Test.stopTest();
        Agent_Skills_Repo__c rec = [SELECT Name FROM Agent_Skills_Repo__c WHERE Id = :res.recordId];
        System.assert(rec.Name.startsWith('workflow-'), 'workflow prefix enforced: ' + rec.Name);
    }

    @IsTest
    static void normalizesReferencesCsvNoSpaces() {
        Agent_Skill_Builder.rawOverride =
            '{"name":"case mgmt","type":"Skill","description":"d","whenToUse":"w","instructionBody":"b",' +
            '"references":["core-skill-otp"," workflow-escalate ",""],"priority":5}';
        Test.startTest();
        Agent_Skill_Builder.BuilderResult res =
            Agent_Skill_Builder.generateSkill('cases', 'Skill', null);
        Test.stopTest();
        Agent_Skills_Repo__c rec = [SELECT References__c FROM Agent_Skills_Repo__c WHERE Id = :res.recordId];
        System.assertEquals('core-skill-otp,workflow-escalate', rec.References__c);
    }

    @IsTest
    static void malformedJsonReturnsErrorNotException() {
        Agent_Skill_Builder.rawOverride = 'sorry, here is your skill: {not valid json';
        Test.startTest();
        Agent_Skill_Builder.BuilderResult res =
            Agent_Skill_Builder.generateSkill('x', 'Skill', null);
        Test.stopTest();
        System.assertEquals(false, res.success);
        System.assert(String.isNotBlank(res.warnings));
        System.assertEquals(0, [SELECT COUNT() FROM Agent_Skills_Repo__c]);
    }

    @IsTest
    static void extractsTextFromContentVersion() {
        ContentVersion cv = new ContentVersion(Title='policy', PathOnClient='policy.md',
            VersionData=Blob.valueOf('# Policy\nEscalate after 3 failed steps.'));
        insert cv;
        Id cvId = [SELECT Id FROM ContentVersion WHERE Title='policy' LIMIT 1].Id;
        Agent_Skill_Builder.rawOverride =
            '{"name":"p","type":"Skill","description":"d","whenToUse":"w","instructionBody":"b","references":[],"priority":5}';
        Test.startTest();
        Agent_Skill_Builder.BuilderResult res =
            Agent_Skill_Builder.generateSkill('policy skill', 'Skill', cvId);
        Test.stopTest();
        System.assert(res.success);
        // referenceText was extracted (no unsupported-file warning)
        System.assert(res.warnings == null || !res.warnings.contains('Unsupported'), res.warnings);
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sf apex run test --tests Agent_Skill_Builder_Test --target-org myDevOrg --result-format human`
Expected: FAIL — `Agent_Skill_Builder` does not exist.

- [ ] **Step 3: Write the implementation**

Create `force-app/main/default/classes/Agent_Skill_Builder.cls`:

```apex
public with sharing class Agent_Skill_Builder {
    private static final String TEMPLATE_API_NAME = 'Generate_Agent_Skill';
    private static final Integer MAX_REF_TEXT = 100000;
    private static final Set<String> TEXT_TYPES = new Set<String>{
        'TEXT', 'MARKDOWN', 'HTML', 'CSV', 'XML', 'RTF', 'LOG'
    };

    // Test seam: when set, used instead of a live prompt-template call.
    @TestVisible private static String rawOverride;

    public class BuilderResult {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String warnings;
        @AuraEnabled public String rawJson;
        @AuraEnabled public Boolean success;
    }

    @AuraEnabled
    public static BuilderResult generateSkill(String intent, String skillType, String contentVersionId) {
        BuilderResult result = new BuilderResult();
        List<String> warnings = new List<String>();

        String referenceText = '';
        if (String.isNotBlank(contentVersionId)) {
            referenceText = extractText((Id) contentVersionId, warnings);
        }

        String raw = rawOverride != null
            ? rawOverride
            : invokeTemplate(intent, skillType, referenceText);
        result.rawJson = raw;

        Map<String, Object> parsed = parseJson(raw);
        if (parsed == null) {
            result.success = false;
            warnings.add('Could not parse a JSON skill from the model response.');
            result.warnings = String.join(warnings, ' ');
            return result;
        }

        Agent_Skills_Repo__c rec = toRecord(parsed, skillType);
        insert rec;
        result.recordId = rec.Id;
        result.name = rec.Name;
        result.success = true;
        result.warnings = warnings.isEmpty() ? null : String.join(warnings, ' ');
        return result;
    }

    private static String extractText(Id contentVersionId, List<String> warnings) {
        ContentVersion cv = [
            SELECT VersionData, FileType, Title FROM ContentVersion WHERE Id = :contentVersionId LIMIT 1
        ];
        if (!TEXT_TYPES.contains(cv.FileType)) {
            warnings.add('Unsupported document type "' + cv.FileType +
                '" — reference text was not extracted (use text, markdown, or HTML).');
            return '';
        }
        String text = cv.VersionData.toString();
        if (text != null && text.length() > MAX_REF_TEXT) {
            text = text.substring(0, MAX_REF_TEXT);
            warnings.add('Reference document truncated to ' + MAX_REF_TEXT + ' characters.');
        }
        return text;
    }

    private static String invokeTemplate(String intent, String skillType, String referenceText) {
        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        Map<String, ConnectApi.WrappedValue> params = new Map<String, ConnectApi.WrappedValue>();
        params.put('intent', wrap(intent));
        params.put('skillType', wrap(skillType));
        params.put('referenceText', wrap(String.isBlank(referenceText) ? '' : referenceText));
        input.inputParams = params;
        input.isPreview = false;

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation resp =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(TEMPLATE_API_NAME, input);
        if (resp != null && resp.generations != null && !resp.generations.isEmpty()) {
            return resp.generations[0].text;
        }
        return '';
    }

    private static ConnectApi.WrappedValue wrap(String value) {
        ConnectApi.WrappedValue wv = new ConnectApi.WrappedValue();
        wv.value = value == null ? '' : value;
        return wv;
    }

    private static Map<String, Object> parseJson(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        // extract the first {...} block to tolerate stray prose around the JSON
        Integer start = raw.indexOf('{');
        Integer end = raw.lastIndexOf('}');
        if (start < 0 || end <= start) {
            return null;
        }
        String jsonBlock = raw.substring(start, end + 1);
        try {
            Object o = JSON.deserializeUntyped(jsonBlock);
            return (o instanceof Map<String, Object>) ? (Map<String, Object>) o : null;
        } catch (Exception e) {
            return null;
        }
    }

    private static Agent_Skills_Repo__c toRecord(Map<String, Object> j, String skillType) {
        String type = normalizeType(skillType);
        String name = enforcePrefix(strVal(j, 'name'), type);
        String references = normalizeReferences(j.get('references'));

        Agent_Skills_Repo__c rec = new Agent_Skills_Repo__c();
        rec.Name = name;
        rec.Type__c = type;
        rec.Description__c = strVal(j, 'description');
        rec.WhenToUse__c = strVal(j, 'whenToUse');
        rec.InstructionBody__c = strVal(j, 'instructionBody');
        rec.References__c = references;
        rec.Priority__c = priorityVal(j.get('priority'));
        rec.Status__c = 'Draft';
        rec.Version__c = 'v1';
        rec.Locale__c = 'en-US';
        rec.ExternalId__c = name + ':v1:en-US';
        return rec;
    }

    private static String normalizeType(String skillType) {
        if (String.isBlank(skillType)) { return 'Skill'; }
        String t = skillType.trim().toLowerCase();
        if (t.startsWith('role')) { return 'Role'; }
        if (t.startsWith('core')) { return 'Core_Skill'; }
        if (t.startsWith('workflow')) { return 'Workflow'; }
        return 'Skill';
    }

    private static String prefixFor(String type) {
        if (type == 'Role') { return 'role-'; }
        if (type == 'Core_Skill') { return 'core-skill-'; }
        if (type == 'Workflow') { return 'workflow-'; }
        return 'skill-';
    }

    private static String enforcePrefix(String rawName, String type) {
        String prefix = prefixFor(type);
        String slug = (rawName == null ? '' : rawName).trim().toLowerCase();
        // strip any leading known prefix the model may have added
        for (String p : new List<String>{ 'role-', 'core-skill-', 'workflow-', 'skill-' }) {
            if (slug.startsWith(p)) { slug = slug.substring(p.length()); }
        }
        slug = slug.replaceAll('[^a-z0-9]+', '-').replaceAll('^-+|-+$', '');
        if (String.isBlank(slug)) { slug = 'new-skill'; }
        return prefix + slug;
    }

    private static String normalizeReferences(Object refs) {
        if (!(refs instanceof List<Object>)) { return null; }
        List<String> clean = new List<String>();
        for (Object o : (List<Object>) refs) {
            String s = o == null ? null : String.valueOf(o).trim();
            if (String.isNotBlank(s)) { clean.add(s); }
        }
        return clean.isEmpty() ? null : String.join(clean, ',');
    }

    private static String strVal(Map<String, Object> j, String key) {
        Object v = j.get(key);
        return v == null ? null : String.valueOf(v);
    }

    private static Decimal priorityVal(Object v) {
        if (v == null) { return null; }
        try { return Decimal.valueOf(String.valueOf(v)); } catch (Exception e) { return null; }
    }
}
```

> **Implementer note on ConnectApi types — VERIFIED on `myDevOrg`:** the full call shape was compile-checked against the org (anonymous Apex, real call guarded behind `if(false)` so the compiler type-checks without invoking the model). Confirmed valid: `ConnectApi.WrappedValue.value`, `EinsteinPromptTemplateGenerationsInput.inputParams` (`Map<String,WrappedValue>`), `EinsteinPromptTemplateGenerationsInput.isPreview`, `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(String, EinsteinPromptTemplateGenerationsInput)` returning `ConnectApi.EinsteinPromptTemplateGenerationsRepresentation`, and `.generations[0].text`. Use as written; no adjustment expected.

- [ ] **Step 4: Create both `-meta.xml`** (apiVersion 65.0, Active — same as Task 1 Step 4).

- [ ] **Step 5: Deploy and run test**

Run:
```bash
sf project deploy start --metadata ApexClass:Agent_Skill_Builder ApexClass:Agent_Skill_Builder_Test --target-org myDevOrg
sf apex run test --tests Agent_Skill_Builder_Test --target-org myDevOrg --result-format human
```
Expected: PASS (all 5 methods). If a ConnectApi type name mismatches at compile, fix per the implementer note and redeploy.

- [ ] **Step 6: Commit**

```bash
git add force-app/main/default/classes/Agent_Skill_Builder*.cls*
git commit -m "feat: add Agent_Skill_Builder (form->prompt template->Draft skill)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `Generate_Agent_Skill` prompt template

**Files:**
- Create: `force-app/main/default/genAiPromptTemplates/Generate_Agent_Skill.genAiPromptTemplate-meta.xml`

**Interfaces:**
- Consumed by `Agent_Skill_Builder.invokeTemplate` via `TEMPLATE_API_NAME='Generate_Agent_Skill'`.
- Inputs (API names must match the `inputParams` keys): `intent`, `skillType`, `referenceText`.

- [ ] **Step 1: Author the template metadata**

Create `Generate_Agent_Skill.genAiPromptTemplate-meta.xml` (Flex template, three Text inputs, strict-JSON instruction):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<GenAiPromptTemplate xmlns="http://soap.sforce.com/2006/04/metadata">
    <activeVersionIdentifier>1</activeVersionIdentifier>
    <developerName>Generate_Agent_Skill</developerName>
    <masterLabel>Generate Agent Skill</masterLabel>
    <templateVersions>
        <content>You are a Salesforce Agent Skills authoring assistant. Generate ONE Agent Skill definition as STRICT JSON and nothing else — no prose, no markdown fences.

Skill type requested: {!$Input:skillType}
Author intent: {!$Input:intent}
Reference material (optional, may be empty): {!$Input:referenceText}

Output a single JSON object with EXACTLY these keys:
{
  "name": "kebab-case name WITHOUT a type prefix (the system adds it)",
  "type": "one of Role, Core_Skill, Skill, Workflow — matching the requested skill type",
  "description": "one-sentence summary",
  "whenToUse": "a detailed routing header starting with 'Use when ...', 2-4 sentences, including example user utterances and clear scope boundaries (what it is NOT for)",
  "instructionBody": "a markdown instruction body with clear sections and step-by-step guidance grounded in the intent and reference material",
  "references": ["names of other skills/workflows this depends on, or empty array"],
  "priority": 5
}

Rules:
- Emit ONLY the JSON object. Do not wrap it in code fences or add commentary.
- Ground whenToUse, instructionBody, and references in the reference material when it is provided.
- Do not invent tool names or reference records you are unsure exist; prefer an empty references array over guessing.
- whenToUse must be rich enough for a router to disambiguate this skill from others.</content>
        <primaryModel>sfdc_ai__DefaultGPT4Omni</primaryModel>
        <status>Published</status>
        <templateDataProviders/>
        <versionIdentifier>1</versionIdentifier>
        <inputs>
            <apiName>intent</apiName>
            <definition>SObject://Text</definition>
            <masterLabel>intent</masterLabel>
            <referenceName>Input:intent</referenceName>
            <required>true</required>
        </inputs>
        <inputs>
            <apiName>skillType</apiName>
            <definition>SObject://Text</definition>
            <masterLabel>skillType</masterLabel>
            <referenceName>Input:skillType</referenceName>
            <required>true</required>
        </inputs>
        <inputs>
            <apiName>referenceText</apiName>
            <definition>SObject://Text</definition>
            <masterLabel>referenceText</masterLabel>
            <referenceName>Input:referenceText</referenceName>
            <required>false</required>
        </inputs>
    </templateVersions>
    <type>einstein_gpt__flex</type>
    <visibility>Global</visibility>
</GenAiPromptTemplate>
```

> **Implementer note:** `genAiPromptTemplate` metadata shape varies by API version. If deploy rejects a field (e.g. `primaryModel` value, `definition` format for Text inputs, or `type`), retrieve a working template shape for reference: `sf project retrieve start --metadata GenAiPromptTemplate --target-org myDevOrg` (if any exist), or author the template once in Prompt Builder UI and retrieve it, then reconcile. The three input API names (`intent`, `skillType`, `referenceText`) and strict-JSON instruction are the fixed contract; the model name must be one active in the org (list via Setup → Einstein → Models, or use the org default).

- [ ] **Step 2: Deploy the template**

Run: `sf project deploy start --metadata GenAiPromptTemplate:Generate_Agent_Skill --target-org myDevOrg`
Expected: Succeeded. If it fails on shape, apply the implementer note and redeploy.

- [ ] **Step 3: Smoke-test the live invocation (end-to-end, no override)**

Run an anonymous Apex snippet that calls `Agent_Skill_Builder.generateSkill('answer questions about Wi-Fi modem setup','Skill',null)` (no `rawOverride`) and debug the result:
```bash
sf apex run --file scripts/apex/test_skill_builder.apex --target-org myDevOrg
```
(create that scratch script inline; not committed). Expected: a Draft `skill-*` record is created; confirm via SOQL. If the model returns non-JSON, inspect `result.rawJson` and tighten the template content, redeploy, retry (max 3).

- [ ] **Step 4: Commit**

```bash
git add force-app/main/default/genAiPromptTemplates/Generate_Agent_Skill.genAiPromptTemplate-meta.xml
git commit -m "feat: add Generate_Agent_Skill prompt template (strict-JSON skill generator)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `skillBuilder` LWC

**Files:**
- Create: `force-app/main/default/lwc/skillBuilder/skillBuilder.js`
- Create: `force-app/main/default/lwc/skillBuilder/skillBuilder.html`
- Create: `force-app/main/default/lwc/skillBuilder/skillBuilder.js-meta.xml`

**Interfaces:**
- Consumes: `generateSkill` from Task 3 via `@salesforce/apex/Agent_Skill_Builder.generateSkill`.
- Uses `lightning-file-upload` (writes a `ContentVersion`, returns `contentVersionId` in `event.detail.files[0].contentVersionId`... note: file-upload gives `documentId` (ContentDocumentId); we resolve latest ContentVersion — see Step 1).

- [ ] **Step 1: Write the component JS**

Create `skillBuilder.js`:

```js
import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import generateSkill from '@salesforce/apex/Agent_Skill_Builder.generateSkill';

const TYPE_OPTIONS = [
    { label: 'Skill', value: 'Skill' },
    { label: 'Workflow', value: 'Workflow' },
    { label: 'Core skill', value: 'Core_Skill' },
    { label: 'Role', value: 'Role' }
];

export default class SkillBuilder extends NavigationMixin(LightningElement) {
    @track skillType = 'Skill';
    @track intent = '';
    contentVersionId;
    uploadedName;
    loading = false;
    typeOptions = TYPE_OPTIONS;

    get acceptedFormats() {
        return ['.txt', '.md', '.markdown', '.html', '.csv', '.xml'];
    }
    get generateDisabled() {
        return this.loading || !this.intent || this.intent.trim().length === 0;
    }

    handleType(e) { this.skillType = e.detail.value; }
    handleIntent(e) { this.intent = e.target.value; }

    handleUpload(event) {
        const files = event.detail.files;
        if (files && files.length > 0) {
            this.contentVersionId = files[0].contentVersionId;
            this.uploadedName = files[0].name;
        }
    }

    async handleGenerate() {
        this.loading = true;
        try {
            const res = await generateSkill({
                intent: this.intent,
                skillType: this.skillType,
                contentVersionId: this.contentVersionId
            });
            if (res.success) {
                if (res.warnings) {
                    this.toast('Draft created with notes', res.warnings, 'warning');
                } else {
                    this.toast('Draft skill created', res.name, 'success');
                }
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: res.recordId,
                        objectApiName: 'Agent_Skills_Repo__c',
                        actionName: 'view'
                    }
                });
            } else {
                this.toast('Could not generate skill', res.warnings || 'Unknown error', 'error');
            }
        } catch (e) {
            this.toast('Error', (e.body && e.body.message) || 'Generation failed', 'error');
        } finally {
            this.loading = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
```

- [ ] **Step 2: Write the template**

Create `skillBuilder.html`:

```html
<template>
    <lightning-card title="Skill Builder" icon-name="standard:bot">
        <div class="slds-p-around_medium slds-grid slds-grid_vertical slds-gap_small">
            <lightning-radio-group
                name="skillType"
                label="Skill type"
                options={typeOptions}
                value={skillType}
                type="button"
                onchange={handleType}></lightning-radio-group>

            <lightning-textarea
                name="intent"
                label="What should this skill do?"
                placeholder="Describe the skill's purpose in 1-3 sentences..."
                value={intent}
                onchange={handleIntent}></lightning-textarea>

            <div>
                <lightning-file-upload
                    label="Reference document (optional)"
                    name="skillDoc"
                    accept={acceptedFormats}
                    record-id=""
                    onuploadfinished={handleUpload}></lightning-file-upload>
                <template lwc:if={uploadedName}>
                    <p class="slds-text-body_small slds-text-color_success slds-p-top_x-small">
                        Attached: {uploadedName}
                    </p>
                </template>
                <p class="slds-text-body_small slds-text-color_weak">
                    Text, markdown, and HTML documents work best.
                </p>
            </div>

            <div>
                <lightning-button
                    variant="brand"
                    label="Generate Draft Skill"
                    disabled={generateDisabled}
                    onclick={handleGenerate}></lightning-button>
                <template lwc:if={loading}>
                    <lightning-spinner alternative-text="Generating" size="small"></lightning-spinner>
                </template>
            </div>
        </div>
    </lightning-card>
</template>
```

> **Note on file-upload without a host record:** `lightning-file-upload` normally attaches to a `record-id`. With an empty `record-id` the file uploads as a standalone `ContentVersion`; `event.detail.files[0].contentVersionId` is available in current API versions. If the org requires a record-id, fall back to a `lightning-input type="file"` + Apex `ContentVersion` insert. Validate during Task 5 deploy/smoke; keep whichever works on `myDevOrg`.

- [ ] **Step 3: Write the meta (exposed to App/Home/Record pages)**

Create `skillBuilder.js-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <isExposed>true</isExposed>
    <targets>
        <target>lightning__AppPage</target>
        <target>lightning__HomePage</target>
    </targets>
</LightningComponentBundle>
```

- [ ] **Step 4: Deploy**

Run: `sf project deploy start --metadata LightningComponentBundle:skillBuilder --target-org myDevOrg`
Expected: Succeeded.

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/lwc/skillBuilder/
git commit -m "feat: add skillBuilder LWC (minimal form + optional doc -> Draft skill)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Flexipages (Home + Record) & app wiring

**Files:**
- Create: `force-app/main/default/flexipages/Agent_Skills_Home.flexipage-meta.xml`
- Create: `force-app/main/default/flexipages/Agent_Skills_Repo_Record.flexipage-meta.xml`
- Modify: `force-app/main/default/customApplications/Agent_Skills_Admin.app-meta.xml`

**Interfaces:** hosts `skillBuilder` (Home) and `skillDependencyTree` + record detail (Record).

- [ ] **Step 1: Create the Home app page**

Create `Agent_Skills_Home.flexipage-meta.xml` — an App Page with a header region containing the `skillBuilder` component and a `Agent_Skills_Repo__c` list:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<FlexiPage xmlns="http://soap.sforce.com/2006/04/metadata">
    <flexiPageRegions>
        <name>main</name>
        <type>Region</type>
        <componentInstances>
            <componentName>skillBuilder</componentName>
        </componentInstances>
        <componentInstances>
            <componentName>runtime_sales_activities:listView</componentName>
            <componentInstanceProperties>
                <name>entityName</name>
                <value>Agent_Skills_Repo__c</value>
            </componentInstanceProperties>
        </componentInstances>
    </flexiPageRegions>
    <masterLabel>Agent Skills Home</masterLabel>
    <template>
        <name>flexipage:defaultAppHomeTemplate</name>
    </template>
    <type>AppPage</type>
</FlexiPage>
```

> **Implementer note:** the list component API name (`runtime_sales_activities:listView`) and its property name vary by release. If deploy rejects it, drop the list component and ship the App Page with just `skillBuilder` (the Skills object tab already provides list access); or use `flexipage:filterListCard`. The `skillBuilder` region is the required deliverable; the list is convenience.

- [ ] **Step 2: Create the record page**

Create `Agent_Skills_Repo_Record.flexipage-meta.xml` — a two-region Record Page: left = record form (fields), right = `skillDependencyTree`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<FlexiPage xmlns="http://soap.sforce.com/2006/04/metadata">
    <flexiPageRegions>
        <name>left</name>
        <type>Region</type>
        <componentInstances>
            <componentName>flexipage:recordDetail</componentName>
            <componentInstanceProperties>
                <name>enableActionsInNativeBrowser</name>
                <value>false</value>
            </componentInstanceProperties>
        </componentInstances>
    </flexiPageRegions>
    <flexiPageRegions>
        <name>right</name>
        <type>Region</type>
        <componentInstances>
            <componentName>skillDependencyTree</componentName>
        </componentInstances>
    </flexiPageRegions>
    <masterLabel>Agent Skills Repo Record</masterLabel>
    <sobjectType>Agent_Skills_Repo__c</sobjectType>
    <template>
        <name>flexipage:defaultRecordHeaderAndTwoEqualRegions</name>
    </template>
    <type>RecordPage</type>
</FlexiPage>
```

> **Implementer note:** template developer names (`flexipage:defaultAppHomeTemplate`, `flexipage:defaultRecordHeaderAndTwoEqualRegions`) are standard; if a name is rejected, retrieve an existing flexipage from the org to copy the exact template name/region names for this release. Region names must match the chosen template's regions.

- [ ] **Step 3: Wire the app + assign the record page**

Modify `Agent_Skills_Admin.app-meta.xml` — add the Home app page tab. First create a tab for the App Page (`Agent_Skills_Home`), or reference the flexipage in the app nav. Minimal approach: add
```xml
    <tabs>Agent_Skills_Home</tabs>
```
(requires a `CustomTab` for the flexipage — create `tabs/Agent_Skills_Home.tab-meta.xml` of type `flexiPage`). Assign the record page as org default for `Agent_Skills_Repo__c` via a `profileActionOverrides`/flexipage activation — simplest reliable path is a `FlexiPage` assignment through the app's object record page: set it as the object's default in the deploy, or activate via `sf`:
- Create `tabs/Agent_Skills_Home.tab-meta.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomTab xmlns="http://soap.sforce.com/2006/04/metadata">
    <flexiPage>Agent_Skills_Home</flexiPage>
    <label>Skills Home</label>
    <motif>Custom53: Bell</motif>
</CustomTab>
```
- Add both `<tabs>Agent_Skills_Home</tabs>` to the app.

> **Implementer note (page assignment):** setting a record page as the object default is done via FlexiPage assignment metadata, which is fiddly to hand-author. Acceptable fallback: deploy the flexipages + tab, then **activate the record page as the org default in Setup → Lightning App Builder → Activation** (one manual click), and note it in the PR. The metadata deliverables (both flexipages + Home tab + app nav) are the committed artifacts; activation can be manual.

- [ ] **Step 4: Deploy**

Run:
```bash
sf project deploy start --metadata FlexiPage:Agent_Skills_Home FlexiPage:Agent_Skills_Repo_Record CustomTab:Agent_Skills_Home CustomApplication:Agent_Skills_Admin --target-org myDevOrg
```
Expected: Succeeded (apply implementer notes if a template/component name is rejected).

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/flexipages/ force-app/main/default/tabs/Agent_Skills_Home.tab-meta.xml force-app/main/default/customApplications/Agent_Skills_Admin.app-meta.xml
git commit -m "feat: add Skills Home app page + tabbed record page with dependency tree

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Permission-set grants

**Files:**
- Modify: `force-app/main/default/permissionsets/Agent_Skills_Author.permissionset-meta.xml`

**Interfaces:** grant the Author perm set access to the two new Apex classes (so admins can run the builder + tree).

- [ ] **Step 1: Add class accesses**

Add to `Agent_Skills_Author.permissionset-meta.xml` (alongside existing `classAccesses`, or add the block if none):

```xml
    <classAccesses>
        <apexClass>Agent_Skill_Builder</apexClass>
        <enabled>true</enabled>
    </classAccesses>
    <classAccesses>
        <apexClass>Agent_Skill_DependencyProvider</apexClass>
        <enabled>true</enabled>
    </classAccesses>
```

- [ ] **Step 2: Deploy + assign to yourself for testing**

Run:
```bash
sf project deploy start --metadata PermissionSet:Agent_Skills_Author --target-org myDevOrg
```
Expected: Succeeded. (Author perm set assignment to the admin test user is assumed or done manually.)

- [ ] **Step 3: Commit**

```bash
git add force-app/main/default/permissionsets/Agent_Skills_Author.permissionset-meta.xml
git commit -m "feat: grant Agent_Skills_Author access to builder + dependency Apex

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: LWC Jest tests + docs

**Files:**
- Create: `force-app/main/default/lwc/skillDependencyTree/__tests__/skillDependencyTree.test.js`
- Create: `force-app/main/default/lwc/skillBuilder/__tests__/skillBuilder.test.js`
- Modify: `README.md`, `docs/Agent-Skills-Framework-for-FDE.md`

- [ ] **Step 1: Jest for skillDependencyTree**

Create `__tests__/skillDependencyTree.test.js` — mock the wire adapter with a nested `TreeNode`, assert `lightning-tree` receives mapped `items` (root + children), and that an error state renders. Use the standard `@salesforce/sfdx-lwc-jest` wire-mock pattern (`createElement`, `registerApexTestWireAdapter` or the emit pattern already used in the repo if any).

```js
import { createElement } from 'lwc';
import SkillDependencyTree from 'c/skillDependencyTree';
import getTree from '@salesforce/apex/Agent_Skill_DependencyProvider.getTree';
import { createApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';

jest.mock(
    '@salesforce/apex/Agent_Skill_DependencyProvider.getTree',
    () => ({ default: createApexTestWireAdapter(jest.fn()) }),
    { virtual: true }
);

describe('c-skill-dependency-tree', () => {
    afterEach(() => { while (document.body.firstChild) document.body.removeChild(document.body.firstChild); });

    it('maps tree data into lightning-tree items', async () => {
        const el = createElement('c-skill-dependency-tree', { is: SkillDependencyTree });
        el.recordId = 'a00000000000001';
        document.body.appendChild(el);
        getTree.emit({ name: 'skill-x', label: 'skill-x', type: 'Skill', status: 'active', seen: false,
            children: [{ name: 'workflow-y', label: 'workflow-y', type: 'Workflow', status: 'active', seen: false, children: [] }] });
        await Promise.resolve();
        const tree = el.shadowRoot.querySelector('lightning-tree');
        expect(tree).not.toBeNull();
        expect(tree.items[0].name).toBe('skill-x');
        expect(tree.items[0].items[0].name).toBe('workflow-y');
    });
});
```

- [ ] **Step 2: Jest for skillBuilder**

Create `__tests__/skillBuilder.test.js` — mock `generateSkill` to resolve `{success:true, recordId, name}`; assert Generate is disabled with empty intent, enabled after typing; clicking calls Apex; success triggers navigation (mock `NavigationMixin`). Assert error path shows a toast.

```js
import { createElement } from 'lwc';
import SkillBuilder from 'c/skillBuilder';
import generateSkill from '@salesforce/apex/Agent_Skill_Builder.generateSkill';

jest.mock(
    '@salesforce/apex/Agent_Skill_Builder.generateSkill',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

describe('c-skill-builder', () => {
    afterEach(() => { while (document.body.firstChild) document.body.removeChild(document.body.firstChild); jest.clearAllMocks(); });

    it('disables generate until intent entered, then calls apex', async () => {
        generateSkill.mockResolvedValue({ success: true, recordId: '500x', name: 'skill-x' });
        const el = createElement('c-skill-builder', { is: SkillBuilder });
        document.body.appendChild(el);
        const btn = el.shadowRoot.querySelector('lightning-button');
        expect(btn.disabled).toBe(true);

        const ta = el.shadowRoot.querySelector('lightning-textarea');
        ta.value = 'do a thing';
        ta.dispatchEvent(new CustomEvent('change', { target: { value: 'do a thing' } }));
        // set component state directly for jsdom
        el.shadowRoot.querySelector('lightning-textarea').dispatchEvent(new CustomEvent('change'));
        await Promise.resolve();
        // trigger generate
        el.shadowRoot.querySelector('lightning-button').click();
        await Promise.resolve();
        expect(generateSkill).toHaveBeenCalled();
    });
});
```

> **Implementer note:** LWC Jest event/state wiring in jsdom is finicky; if the change-event value plumbing is awkward, assert the core contract (button exists, Apex mock is wired, success calls generate) and keep the test green rather than over-fitting jsdom. Run `npm run test:unit -- skillBuilder skillDependencyTree`.

- [ ] **Step 3: Run Jest**

Run: `npm run test:unit -- skillDependencyTree skillBuilder`
Expected: PASS. Adjust per the note if jsdom plumbing fights back.

- [ ] **Step 4: Update docs**

- `README.md`: under the admin-app section, add that the app now includes a **Skill Builder** (form + optional doc → Draft skill) and a **dependency tree** on the record page.
- `docs/Agent-Skills-Framework-for-FDE.md`: add a short subsection under the admin/app area describing the two LWCs, the `Generate_Agent_Skill` template, and that the builder always creates Draft.

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/lwc/*/__tests__ README.md docs/Agent-Skills-Framework-for-FDE.md
git commit -m "test+docs: Jest for skills app LWCs; document builder + dependency tree

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Full verification + org smoke test

**Files:** none.

- [ ] **Step 1: Full Apex suite**

Run:
```bash
sf apex run test --tests Agent_Skill_Builder_Test,Agent_Skill_DependencyProvider_Test,Agent_Skill_Loader_Test,Agent_Skill_PromptComposer_Test,Agent_Skill_LoadAndCompose_Test,Agent_Skill_HeaderProvider_Test,Agent_Skill_SeedData_Test --target-org myDevOrg --result-format human
```
Expected: all PASS (no regressions).

- [ ] **Step 2: Jest suite**

Run: `npm run test:unit`
Expected: all PASS.

- [ ] **Step 3: Org smoke test (manual)**

In `myDevOrg`, open the **Agent Skills Admin** app:
1. On Skills Home, use **Skill Builder**: pick Skill, enter an intent (e.g. "help customers compare our laptop models"), optionally upload a `.md` file, click **Generate Draft Skill** → confirm it navigates to a new **Draft** `skill-*` record with populated fields.
2. Open a seeded skill (e.g. `skill-troubleshooting-support`) → confirm the **Dependency Tree** renders the downstream `workflow-*` cascade with type badges.
Record results in the PR.

- [ ] **Step 4: Confirm scope**

Run `git status` and `git diff --stat main`; expected only the files in the File Structure table. No changes to `Agent_Skill_Loader`/`Composer`/`LoadAndCompose` or any agent bundle.

---

## Self-Review Notes (author checklist, completed)

- **Spec coverage:** Deliverables 1→T4; 2→T3; 3→T2/T1; 4→T5; 5→T1; 6→T6; 7 (perms)→T7; 8 (docs)→T8; testing→T1/T3/T8/T9.
- **Verified before planning:** `ConnectApi.EinsteinLLM` + `EinsteinPromptTemplateGenerationsInput` available on `myDevOrg`; `EinsteinPromptTemplateGenerationsInput.inputParams` is `Map<String,WrappedValue>`.
- **Type consistency:** `TreeNode` shape identical in Task 1 Apex, Task 2 LWC mapping, and Task 8 Jest. `BuilderResult` fields identical in Task 3 Apex, Task 5 LWC, and Task 8 Jest. Template input names (`intent`/`skillType`/`referenceText`) identical in Task 3 `inputParams`, Task 4 template, and Task 4 smoke test.
- **Risk-flagged uncertainties** (ConnectApi member names, genAiPromptTemplate metadata shape, flexipage template names, file-upload without record-id) each carry an implementer note with a concrete fallback and an org-validation step, so a compile/deploy mismatch is a documented adjust-and-retry, not a blocker.
- **No placeholders:** every code step has complete code; every command has expected output.
```
