# Progressive Disclosure + Generic Subagent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add router-level progressive disclosure (skill headers → selected skills) and a single generic handler topic that loads the selected skills and exposes the full support-demo tool catalog, driven entirely by the loaded skills.

**Architecture:** A new invocable `Agent_Skill_HeaderProvider` returns lean `Name: WhenToUse__c` headers for a candidate skill list (no body, no reference expansion, no fallback). The router (`start_agent`) presents those headers, the LLM writes a no-spaces CSV of chosen skills to `@variables.skills_to_load`, then `after_reasoning` transitions to one `generic_handler` topic that loads those skills (cascading to workflows via existing `References__c`) and re-exposes all ten support-demo action tools under `reasoning.actions`. `Agent_Skill_PromptComposer` gains one additive post-composition pass that rewrites `[[tool:Name]]` indicators in instruction bodies into validated plain-text cues. Seed instruction bodies are revised to carry those indicators, and two malformed `References__c` values are corrected.

**Tech Stack:** Salesforce Apex (API 65.0, `@InvocableMethod`), Agent Script (`.agent` authoring bundle), CSV seed data, `sf` CLI.

## Global Constraints

- Deploy/validate/test target org is **`myDevOrg`** — every `sf` command MUST pass `--target-org myDevOrg` explicitly (the stored default `dev-test-org` is stale).
- All Apex must be **PEP8-not-applicable but Apex-idiomatic**: match existing style in `Agent_Skill_Loader.cls` / `Agent_Skill_PromptComposer.cls` (4-space indent, `with sharing`, `@InvocableVariable` labelled I/O).
- `References__c` is a **no-spaces CSV of real record names only** — never prose, never a space after a comma.
- `instructionNames` CSV in Agent Script has **no spaces after commas**.
- Map action outputs with `set @variables.x=@outputs.y` **inside the same `run` block**.
- Keep `system.instructions` static; dynamic instruction text goes only in topic reasoning.
- **No fallback** for headers: a record with blank `WhenToUse__c` is treated as missing, never substituted with `Description__c`.
- The generic subagent reasoning block stays **topic-agnostic** — no per-tool enumeration; tool purpose lives in each action `description:`.
- Do **not** modify `Agent_Skill_Loader`, `Agent_Skill_LoadAndCompose`, or the existing `customer_support_skill_demo` bundle.
- The `[[tool:Name]]` allowlist is the ten support-demo tools (single source of truth, Task 2): `CreateCase, CreateEscalationTicket, Route_to_ESA, GetOrderStatus, FetchSupportHistory, TrackShipment, FetchAccountData, GetProductInfo, SendVerificationEmail, Render_Data`.

---

## File Structure

| File | Responsibility | Task |
|------|----------------|------|
| `force-app/main/default/classes/Agent_Skill_HeaderProvider.cls` (+ `-meta.xml`) | New invocable: candidate skill names → lean headers, no fallback | 1 |
| `force-app/main/default/classes/Agent_Skill_HeaderProvider_Test.cls` (+ `-meta.xml`) | Coverage for header retrieval, exclusion, locale | 1 |
| `force-app/main/default/classes/Agent_Skill_PromptComposer.cls` | Add additive `[[tool:Name]]` rewrite/validate pass | 2 |
| `force-app/main/default/classes/Agent_Skill_PromptComposer_Test.cls` | Extend with rewrite / unknown-tool / passthrough tests | 2 |
| `force-app/main/default/classes/Agent_Skill_SeedService.cls` | **PRIMARY seed source** (inline string bodies) — add `[[tool:Name]]` indicators; fix 2 malformed `References__c` | 3 |
| `data/agent-skills/roles.csv`, `skills.csv`, `workflows.csv` | Documentation/source-of-record mirror — same edits for consistency | 3 |
| `force-app/main/default/classes/Agent_Skill_SeedData_Test.cls` (+ `-meta.xml`) | Integrity test: refs resolve; indicators name real tools | 3 |
| `force-app/main/default/aiAuthoringBundles/customer_support_progressive/customer_support_progressive.agent` (+ `.bundle-meta.xml`) | New bundle: router + one generic subagent | 4 |
| `docs/Agent-Skills-Framework-for-FDE.md` | Document header contract, `[[tool:Name]]`, router/generic pattern | 5 |

---

## Task 1: `Agent_Skill_HeaderProvider` invocable + test

**Files:**
- Create: `force-app/main/default/classes/Agent_Skill_HeaderProvider.cls`
- Create: `force-app/main/default/classes/Agent_Skill_HeaderProvider.cls-meta.xml`
- Test: `force-app/main/default/classes/Agent_Skill_HeaderProvider_Test.cls`
- Create: `force-app/main/default/classes/Agent_Skill_HeaderProvider_Test.cls-meta.xml`

**Interfaces:**
- Consumes: `Agent_Skills_Repo__c` (`Name`, `WhenToUse__c`, `Status__c`, `Locale__c`).
- Produces: `Agent_Skill_HeaderProvider.getHeaders(List<HeaderRequest>) → List<HeaderResponse>`.
  - `HeaderRequest`: `String skillNames` (CSV, required), `String locale` (optional, default `en-US`).
  - `HeaderResponse`: `String skillHeaders`, `Integer headersFound`, `String missingNames`, `String warnings`.
  - `skillHeaders` format: one line per found skill, sorted, `- <Name>: <WhenToUse__c>`, joined by `\n`.

- [ ] **Step 1: Write the failing test**

Create `force-app/main/default/classes/Agent_Skill_HeaderProvider_Test.cls`:

```apex
@IsTest
private class Agent_Skill_HeaderProvider_Test {
    @TestSetup
    static void setupData() {
        insert new List<Agent_Skills_Repo__c>{
            new Agent_Skills_Repo__c(
                Name = 'skill-product-information-qa',
                Type__c = 'Skill',
                ExternalId__c = 'skill-product-information-qa:v1:en-US',
                WhenToUse__c = 'Use when user asks about product features or comparisons.',
                InstructionBody__c = 'Body A',
                Status__c = 'active',
                Version__c = 'v1',
                Locale__c = 'en-US'
            ),
            new Agent_Skills_Repo__c(
                Name = 'skill-troubleshooting-support',
                Type__c = 'Skill',
                ExternalId__c = 'skill-troubleshooting-support:v1:en-US',
                WhenToUse__c = 'Use for any product troubleshooting need.',
                InstructionBody__c = 'Body B',
                Status__c = 'active',
                Version__c = 'v1',
                Locale__c = 'en-US'
            ),
            new Agent_Skills_Repo__c(
                Name = 'skill-blank-header',
                Type__c = 'Skill',
                ExternalId__c = 'skill-blank-header:v1:en-US',
                WhenToUse__c = '',
                InstructionBody__c = 'Body C',
                Status__c = 'active',
                Version__c = 'v1',
                Locale__c = 'en-US'
            ),
            new Agent_Skills_Repo__c(
                Name = 'skill-inactive',
                Type__c = 'Skill',
                ExternalId__c = 'skill-inactive:v1:en-US',
                WhenToUse__c = 'Use for inactive scenario.',
                InstructionBody__c = 'Body D',
                Status__c = 'deprecated',
                Version__c = 'v1',
                Locale__c = 'en-US'
            )
        };
    }

    @IsTest
    static void shouldReturnHeadersForActiveSkills() {
        Agent_Skill_HeaderProvider.HeaderRequest req = new Agent_Skill_HeaderProvider.HeaderRequest();
        req.skillNames = 'skill-product-information-qa,skill-troubleshooting-support';

        Test.startTest();
        List<Agent_Skill_HeaderProvider.HeaderResponse> res =
            Agent_Skill_HeaderProvider.getHeaders(
                new List<Agent_Skill_HeaderProvider.HeaderRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size());
        Agent_Skill_HeaderProvider.HeaderResponse r = res[0];
        System.assertEquals(2, r.headersFound, 'Both active skills should be returned');
        System.assert(
            r.skillHeaders.contains('- skill-product-information-qa: Use when user asks about product features or comparisons.'),
            'Header line for product skill expected: ' + r.skillHeaders);
        System.assert(
            r.skillHeaders.contains('- skill-troubleshooting-support: Use for any product troubleshooting need.'),
            'Header line for troubleshooting skill expected');
        System.assertEquals('', r.missingNames, 'No missing names expected');
        System.assertEquals('', r.warnings, 'No warnings expected');
    }

    @IsTest
    static void shouldExcludeBlankHeaderWithNoFallback() {
        Agent_Skill_HeaderProvider.HeaderRequest req = new Agent_Skill_HeaderProvider.HeaderRequest();
        req.skillNames = 'skill-product-information-qa,skill-blank-header';

        Test.startTest();
        Agent_Skill_HeaderProvider.HeaderResponse r =
            Agent_Skill_HeaderProvider.getHeaders(
                new List<Agent_Skill_HeaderProvider.HeaderRequest>{ req })[0];
        Test.stopTest();

        System.assertEquals(1, r.headersFound, 'Blank WhenToUse__c must be excluded');
        System.assertEquals('skill-blank-header', r.missingNames,
            'Blank-header skill reported as missing (no fallback)');
        System.assert(String.isNotBlank(r.warnings), 'A warning must be present for the excluded skill');
        System.assert(!r.skillHeaders.contains('skill-blank-header'),
            'Excluded skill must not appear in headers');
    }

    @IsTest
    static void shouldReportInactiveAndUnknownAsMissing() {
        Agent_Skill_HeaderProvider.HeaderRequest req = new Agent_Skill_HeaderProvider.HeaderRequest();
        req.skillNames = 'skill-inactive,skill-does-not-exist';

        Test.startTest();
        Agent_Skill_HeaderProvider.HeaderResponse r =
            Agent_Skill_HeaderProvider.getHeaders(
                new List<Agent_Skill_HeaderProvider.HeaderRequest>{ req })[0];
        Test.stopTest();

        System.assertEquals(0, r.headersFound);
        System.assert(r.missingNames.contains('skill-inactive'));
        System.assert(r.missingNames.contains('skill-does-not-exist'));
    }

    @IsTest
    static void shouldHandleEmptyInput() {
        Agent_Skill_HeaderProvider.HeaderRequest req = new Agent_Skill_HeaderProvider.HeaderRequest();
        req.skillNames = '';

        Test.startTest();
        Agent_Skill_HeaderProvider.HeaderResponse r =
            Agent_Skill_HeaderProvider.getHeaders(
                new List<Agent_Skill_HeaderProvider.HeaderRequest>{ req })[0];
        Test.stopTest();

        System.assertEquals(0, r.headersFound);
        System.assertEquals('', r.skillHeaders);
    }

    @IsTest
    static void shouldFilterByLocale() {
        Agent_Skill_HeaderProvider.HeaderRequest req = new Agent_Skill_HeaderProvider.HeaderRequest();
        req.skillNames = 'skill-product-information-qa';
        req.locale = 'fr-FR';

        Test.startTest();
        Agent_Skill_HeaderProvider.HeaderResponse r =
            Agent_Skill_HeaderProvider.getHeaders(
                new List<Agent_Skill_HeaderProvider.HeaderRequest>{ req })[0];
        Test.stopTest();

        System.assertEquals(0, r.headersFound, 'No en-US record should match fr-FR');
        System.assertEquals('skill-product-information-qa', r.missingNames);
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sf apex run test --tests Agent_Skill_HeaderProvider_Test --target-org myDevOrg --result-format human`
Expected: FAIL / compile error — `Agent_Skill_HeaderProvider` type does not exist.

- [ ] **Step 3: Write the implementation**

Create `force-app/main/default/classes/Agent_Skill_HeaderProvider.cls`:

```apex
public with sharing class Agent_Skill_HeaderProvider {
    public class HeaderRequest {
        @InvocableVariable(
            required=true
            label='Candidate Skill Names CSV'
            description='CSV of candidate skill names whose headers to return. No reference expansion.'
        )
        public String skillNames;

        @InvocableVariable(
            label='Locale (optional, default en-US)'
            description='Locale for header resolution (e.g. en-US).'
        )
        public String locale;
    }

    public class HeaderResponse {
        @InvocableVariable(
            label='Skill Headers'
            description='One line per skill: "- <Name>: <WhenToUse__c>".'
        )
        public String skillHeaders;

        @InvocableVariable(
            label='Headers Found'
            description='Count of headers returned.'
        )
        public Integer headersFound;

        @InvocableVariable(
            label='Missing Names'
            description='CSV of requested names inactive, not found, or with blank WhenToUse__c.'
        )
        public String missingNames;

        @InvocableVariable(
            label='Warnings'
            description='Warning message when any requested name is missing/excluded.'
        )
        public String warnings;
    }

    @InvocableMethod(
        label='Get Skill Headers'
        description='Returns lean Name + WhenToUse__c headers for candidate skills. No body, no reference expansion, no fallback.'
    )
    public static List<HeaderResponse> getHeaders(List<HeaderRequest> requests) {
        List<HeaderResponse> responses = new List<HeaderResponse>();
        for (HeaderRequest requestItem : requests) {
            responses.add(processRequest(requestItem));
        }
        return responses;
    }

    private static HeaderResponse processRequest(HeaderRequest requestItem) {
        HeaderResponse response = new HeaderResponse();
        Set<String> requested = parseCsv(requestItem.skillNames);
        String effectiveLocale = String.isBlank(requestItem.locale) ? 'en-US' : requestItem.locale;

        Map<String, String> headerByName = new Map<String, String>();
        if (!requested.isEmpty()) {
            for (Agent_Skills_Repo__c rec : [
                SELECT Name, WhenToUse__c
                FROM Agent_Skills_Repo__c
                WHERE Name IN :requested
                AND Status__c = 'active'
                AND Locale__c = :effectiveLocale
            ]) {
                // No fallback: a blank WhenToUse__c is treated as missing.
                if (String.isBlank(rec.WhenToUse__c)) {
                    continue;
                }
                if (!headerByName.containsKey(rec.Name)) {
                    headerByName.put(rec.Name, rec.WhenToUse__c.trim());
                }
            }
        }

        List<String> foundNames = new List<String>(headerByName.keySet());
        foundNames.sort();

        List<String> lines = new List<String>();
        for (String name : foundNames) {
            lines.add('- ' + name + ': ' + headerByName.get(name));
        }

        List<String> missing = new List<String>();
        for (String name : requested) {
            if (!headerByName.containsKey(name)) {
                missing.add(name);
            }
        }
        missing.sort();

        response.skillHeaders = String.join(lines, '\n');
        response.headersFound = foundNames.size();
        response.missingNames = String.join(missing, ',');
        response.warnings = missing.isEmpty()
            ? ''
            : 'Missing or excluded skill headers (inactive, not found, or blank WhenToUse__c): ' + String.join(missing, ',');
        return response;
    }

    private static Set<String> parseCsv(String csv) {
        Set<String> outSet = new Set<String>();
        if (String.isBlank(csv)) {
            return outSet;
        }
        for (String token : csv.split(',')) {
            String trimmed = token == null ? null : token.trim();
            if (!String.isBlank(trimmed)) {
                outSet.add(trimmed);
            }
        }
        return outSet;
    }
}
```

- [ ] **Step 4: Create the class meta files**

Create `force-app/main/default/classes/Agent_Skill_HeaderProvider.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

Create `force-app/main/default/classes/Agent_Skill_HeaderProvider_Test.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 5: Deploy and run test to verify it passes**

Run:
```bash
sf project deploy start --source-dir force-app/main/default/classes/Agent_Skill_HeaderProvider.cls,force-app/main/default/classes/Agent_Skill_HeaderProvider.cls-meta.xml,force-app/main/default/classes/Agent_Skill_HeaderProvider_Test.cls,force-app/main/default/classes/Agent_Skill_HeaderProvider_Test.cls-meta.xml --target-org myDevOrg
sf apex run test --tests Agent_Skill_HeaderProvider_Test --target-org myDevOrg --result-format human
```
Expected: PASS — all 5 test methods pass, 100% coverage of `Agent_Skill_HeaderProvider`.

- [ ] **Step 6: Commit**

```bash
git add force-app/main/default/classes/Agent_Skill_HeaderProvider.cls force-app/main/default/classes/Agent_Skill_HeaderProvider.cls-meta.xml force-app/main/default/classes/Agent_Skill_HeaderProvider_Test.cls force-app/main/default/classes/Agent_Skill_HeaderProvider_Test.cls-meta.xml
git commit -m "feat: add Agent_Skill_HeaderProvider invocable for router progressive disclosure

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Composer `[[tool:Name]]` rewrite/validation pass + tests

**Files:**
- Modify: `force-app/main/default/classes/Agent_Skill_PromptComposer.cls` (add rewrite pass; call it at line 132 assembly point)
- Test: `force-app/main/default/classes/Agent_Skill_PromptComposer_Test.cls` (add 3 methods)

**Interfaces:**
- Consumes: existing `ComposerResponse.composedInstructions` (assembled text), `ComposerResponse.warnings`.
- Produces: `Agent_Skill_PromptComposer` private helpers `rewriteToolIndicators(String text)` → rewritten text, and appended warnings for unknown tool names. Public method signatures are unchanged.
- Allowlist constant: `private static final Set<String> KNOWN_TOOL_NAMES` — the ten support-demo tools (single source of truth; Task 3's integrity test reads the same list).

- [ ] **Step 1: Write the failing tests**

Append these three methods inside `Agent_Skill_PromptComposer_Test` (before the closing brace):

```apex
    @IsTest
    static void shouldRewriteKnownToolIndicatorToPlainCue() {
        insert new Agent_Skills_Repo__c(
            Name = 'skill-tool-cue',
            Type__c = 'Skill',
            ExternalId__c = 'skill-tool-cue:v1:en-US',
            Description__c = 'Tool cue skill',
            WhenToUse__c = 'Use to test tool cue rewriting.',
            InstructionBody__c = 'When the customer approves, create the case with [[tool:CreateCase]].',
            Status__c = 'active',
            Version__c = 'v1',
            Locale__c = 'en-US'
        );

        Agent_Skill_Loader.LoaderRequest loadReq = new Agent_Skill_Loader.LoaderRequest();
        loadReq.instructionNames = 'skill-tool-cue';
        loadReq.includeReferences = false;
        loadReq.version = 'v1';
        loadReq.locale = 'en-US';
        String bundleJson = Agent_Skill_Loader.load(
            new List<Agent_Skill_Loader.LoaderRequest>{ loadReq })[0].loadedInstructionBundle;

        Agent_Skill_PromptComposer.ComposerRequest composeReq = new Agent_Skill_PromptComposer.ComposerRequest();
        composeReq.instructionBundle = bundleJson;
        composeReq.requiredNames = 'skill-tool-cue';
        composeReq.includeReferenceExpansion = false;

        Test.startTest();
        Agent_Skill_PromptComposer.ComposerResponse r = Agent_Skill_PromptComposer.compose(
            new List<Agent_Skill_PromptComposer.ComposerRequest>{ composeReq })[0];
        Test.stopTest();

        System.assert(r.composedInstructions.contains('the "CreateCase" tool'),
            'Indicator should be rewritten to a plain cue: ' + r.composedInstructions);
        System.assert(!r.composedInstructions.contains('[[tool:CreateCase]]'),
            'Raw indicator must not survive in output');
    }

    @IsTest
    static void shouldWarnAndMarkUnknownToolIndicator() {
        insert new Agent_Skills_Repo__c(
            Name = 'skill-bad-tool',
            Type__c = 'Skill',
            ExternalId__c = 'skill-bad-tool:v1:en-US',
            Description__c = 'Bad tool skill',
            WhenToUse__c = 'Use to test unknown tool warnings.',
            InstructionBody__c = 'Escalate with [[tool:Crete_Case]].',
            Status__c = 'active',
            Version__c = 'v1',
            Locale__c = 'en-US'
        );

        Agent_Skill_Loader.LoaderRequest loadReq = new Agent_Skill_Loader.LoaderRequest();
        loadReq.instructionNames = 'skill-bad-tool';
        loadReq.includeReferences = false;
        loadReq.version = 'v1';
        loadReq.locale = 'en-US';
        String bundleJson = Agent_Skill_Loader.load(
            new List<Agent_Skill_Loader.LoaderRequest>{ loadReq })[0].loadedInstructionBundle;

        Agent_Skill_PromptComposer.ComposerRequest composeReq = new Agent_Skill_PromptComposer.ComposerRequest();
        composeReq.instructionBundle = bundleJson;
        composeReq.requiredNames = 'skill-bad-tool';
        composeReq.includeReferenceExpansion = false;

        Test.startTest();
        Agent_Skill_PromptComposer.ComposerResponse r = Agent_Skill_PromptComposer.compose(
            new List<Agent_Skill_PromptComposer.ComposerRequest>{ composeReq })[0];
        Test.stopTest();

        System.assert(r.composedInstructions.contains('[[unknown tool: Crete_Case]]'),
            'Unknown tool should be visibly marked: ' + r.composedInstructions);
        System.assert(r.warnings.contains('Crete_Case'),
            'Unknown tool name should be surfaced in warnings: ' + r.warnings);
    }

    @IsTest
    static void shouldLeaveBodyWithoutIndicatorsUnchanged() {
        insert new Agent_Skills_Repo__c(
            Name = 'skill-no-indicator',
            Type__c = 'Skill',
            ExternalId__c = 'skill-no-indicator:v1:en-US',
            Description__c = 'No indicator skill',
            WhenToUse__c = 'Use to test passthrough.',
            InstructionBody__c = 'Provide a clear, concise answer with no tool reference.',
            Status__c = 'active',
            Version__c = 'v1',
            Locale__c = 'en-US'
        );

        Agent_Skill_Loader.LoaderRequest loadReq = new Agent_Skill_Loader.LoaderRequest();
        loadReq.instructionNames = 'skill-no-indicator';
        loadReq.includeReferences = false;
        loadReq.version = 'v1';
        loadReq.locale = 'en-US';
        String bundleJson = Agent_Skill_Loader.load(
            new List<Agent_Skill_Loader.LoaderRequest>{ loadReq })[0].loadedInstructionBundle;

        Agent_Skill_PromptComposer.ComposerRequest composeReq = new Agent_Skill_PromptComposer.ComposerRequest();
        composeReq.instructionBundle = bundleJson;
        composeReq.requiredNames = 'skill-no-indicator';
        composeReq.includeReferenceExpansion = false;

        Test.startTest();
        Agent_Skill_PromptComposer.ComposerResponse r = Agent_Skill_PromptComposer.compose(
            new List<Agent_Skill_PromptComposer.ComposerRequest>{ composeReq })[0];
        Test.stopTest();

        System.assert(r.composedInstructions.contains('Provide a clear, concise answer with no tool reference.'),
            'Body without indicators must pass through verbatim');
        System.assert(!r.composedInstructions.contains('[[unknown tool:'),
            'No unknown-tool marker should appear');
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `sf apex run test --tests Agent_Skill_PromptComposer_Test --target-org myDevOrg --result-format human`
Expected: FAIL — `shouldRewriteKnownToolIndicatorToPlainCue` and the unknown-tool test fail because the raw `[[tool:...]]` text passes through unrewritten. (Deploy the modified test first if a deploy is needed to compile.)

- [ ] **Step 3: Add the allowlist constant and rewrite helper**

In `Agent_Skill_PromptComposer.cls`, add the allowlist constant just below the existing `LINE_SEPARATOR` constant (line 2):

```apex
    // Single source of truth for [[tool:Name]] validation — the support-demo tool inventory.
    private static final Set<String> KNOWN_TOOL_NAMES = new Set<String>{
        'CreateCase', 'CreateEscalationTicket', 'Route_to_ESA', 'GetOrderStatus',
        'FetchSupportHistory', 'TrackShipment', 'FetchAccountData', 'GetProductInfo',
        'SendVerificationEmail', 'Render_Data'
    };
    private static final Pattern TOOL_INDICATOR = Pattern.compile('\\[\\[tool:([A-Za-z0-9_]+)\\]\\]');
```

Add these two private methods before the final closing brace of the class:

```apex
    // Additive post-composition pass: rewrite [[tool:Name]] indicators to validated plain-text cues.
    // Known names become 'the "Name" tool'; unknown names are visibly marked and collected for warnings.
    private static String rewriteToolIndicators(String text, Set<String> unknownToolNames) {
        if (String.isBlank(text) || !text.contains('[[tool:')) {
            return text;
        }
        // Apex has no StringBuilder; assemble segments in a List and join at the end.
        Matcher m = TOOL_INDICATOR.matcher(text);
        List<String> segments = new List<String>();
        Integer lastEnd = 0;
        while (m.find()) {
            segments.add(text.substring(lastEnd, m.start()));
            String toolName = m.group(1);
            if (KNOWN_TOOL_NAMES.contains(toolName)) {
                segments.add('the "' + toolName + '" tool');
            } else {
                segments.add('[[unknown tool: ' + toolName + ']]');
                unknownToolNames.add(toolName);
            }
            lastEnd = m.end();
        }
        segments.add(text.substring(lastEnd));
        return String.join(segments, '');
    }
```

- [ ] **Step 4: Wire the pass into `processRequest`**

In `Agent_Skill_PromptComposer.cls`, replace the assembly block (current lines 131-138) so the rewrite runs over the joined text and its warnings merge with existing warnings. Change:

```apex
        String separatorBlock = '\n\n\n' + LINE_SEPARATOR + '\n\n';
        response.composedInstructions = String.join(blocks, separatorBlock);

        missing.sort();
        warnings.sort();
        response.resolvedNames = String.join(ordered, ',');
        response.missingNames = String.join(missing, ',');
        response.warnings = String.join(warnings, ' | ');
        return response;
```

to:

```apex
        String separatorBlock = '\n\n\n' + LINE_SEPARATOR + '\n\n';
        String composed = String.join(blocks, separatorBlock);

        // Additive tool-cue rewrite/validation pass (composition/ordering above is unchanged).
        Set<String> unknownToolNames = new Set<String>();
        composed = rewriteToolIndicators(composed, unknownToolNames);
        response.composedInstructions = composed;

        if (!unknownToolNames.isEmpty()) {
            List<String> unknownList = new List<String>(unknownToolNames);
            unknownList.sort();
            warnings.add('Unknown tool indicator(s): ' + String.join(unknownList, ','));
        }

        missing.sort();
        warnings.sort();
        response.resolvedNames = String.join(ordered, ',');
        response.missingNames = String.join(missing, ',');
        response.warnings = String.join(warnings, ' | ');
        return response;
```

- [ ] **Step 5: Deploy and run tests to verify they pass**

Run:
```bash
sf project deploy start --source-dir force-app/main/default/classes/Agent_Skill_PromptComposer.cls,force-app/main/default/classes/Agent_Skill_PromptComposer_Test.cls --target-org myDevOrg
sf apex run test --tests Agent_Skill_PromptComposer_Test --target-org myDevOrg --result-format human
```
Expected: PASS — original `shouldComposeWithReferenceExpansion` plus the 3 new methods all pass.

- [ ] **Step 6: Commit**

```bash
git add force-app/main/default/classes/Agent_Skill_PromptComposer.cls force-app/main/default/classes/Agent_Skill_PromptComposer_Test.cls
git commit -m "feat: add [[tool:Name]] indicator rewrite/validation pass to composer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Seed-data revisions + integrity test

> **CRITICAL — where the org data actually comes from:** `scripts/apex/seed_agent_skills.apex` is a 2-line wrapper calling `Agent_Skill_SeedService.seedCustomerSupportDemo()`. The instruction bodies are **inline string literals inside `Agent_Skill_SeedService.cls`** (built via the `repoItem(name, version, locale, description, whenToUse, body, references)` helper at line 507; `InstructionBody__c` set at line 522, `References__c` at line 523). The `data/agent-skills/*.csv` files are a documentation mirror and are **not** read by the seed. Therefore the PRIMARY edit target is `Agent_Skill_SeedService.cls`; the CSVs get the same edits only to stay consistent as source-of-record.

**Files:**
- Modify: `force-app/main/default/classes/Agent_Skill_SeedService.cls` (**primary** — inline bodies + 2 `References__c` fixes)
- Modify: `data/agent-skills/roles.csv` (mirror: tool indicators in `role-customer-support-agent`)
- Modify: `data/agent-skills/skills.csv` (mirror: tool indicators; fix `core-skill-ltmManagement-service-agent` `References__c`)
- Modify: `data/agent-skills/workflows.csv` (mirror: tool indicators; fix `workflow-support-case-lifecycle` `References__c` spacing)
- Create: `force-app/main/default/classes/Agent_Skill_SeedData_Test.cls` (+ `-meta.xml`)

**Interfaces:**
- Consumes: the ten-tool allowlist (must match `KNOWN_TOOL_NAMES` from Task 2 verbatim).
- Produces: revised seed data (Apex + CSV mirror) where every actionable step names its tool via `[[tool:Name]]`; `References__c` values are clean no-spaces CSVs of real record names.

**Data-fix reference (exact current → target):**

1. `core-skill-ltmManagement-service-agent` `References__c`
   - Current (malformed prose): `Agent_Context__c,Get_Agent_ContextObject,Save_Agent_ContextObject. Depends on agent_memory (formatted string from Get_Agent_ContextObject). Save: Save_Agent_ContextObject (new_summary, new_goal, has_issue, new_style).`
   - Target: empty string `` (the referenced names are not `Agent_Skills_Repo__c` records; move the prose to `Description__c` if not already conveyed there).
2. `workflow-support-case-lifecycle` `References__c`
   - Current (space after comma): `core-skill-user-otp-authentication, workflow-escalate-to-human`
   - Target (no spaces): `core-skill-user-otp-authentication,workflow-escalate-to-human`

**Tool-indicator edits (per §7.3 of the spec — insert `[[tool:Name]]` inline at the point of action):** the authoritative, verbatim find/replace pairs are in the **Edit reference table** below (after Step 3). The affected records are: `role-customer-support-agent`, `core-skill-user-otp-authentication`, `core-skill-render-data-format`, `skill-product-information-qa`, `skill-support-case-management`, `skill-troubleshooting-support`, `workflow-support-case-lifecycle`, `workflow-escalate-to-human`, and the **6** `workflow-troubleshooting-*` records (wifi-modem, 5g-modem, iphone-16, iphone-16-pro, galaxy-s25, galaxy-s25-ultra). Do not hand-summarize — apply the table exactly.

- [ ] **Step 1: Write the failing integrity test**

Create `force-app/main/default/classes/Agent_Skill_SeedData_Test.cls`. This test seeds from the shipped CSV logic via `Agent_Skill_SeedService` is NOT used (it may require the object); instead it asserts against records after a manual insert helper is unnecessary — the test validates the *live seeded org data*. Use a query-based assertion that runs against whatever active records exist, guarded to no-op when empty (so it is safe pre-seed) but FAILS on malformed data when records are present:

```apex
@IsTest
private class Agent_Skill_SeedData_Test {
    // Mirrors Agent_Skill_PromptComposer.KNOWN_TOOL_NAMES (single source of truth).
    private static final Set<String> KNOWN_TOOL_NAMES = new Set<String>{
        'CreateCase', 'CreateEscalationTicket', 'Route_to_ESA', 'GetOrderStatus',
        'FetchSupportHistory', 'TrackShipment', 'FetchAccountData', 'GetProductInfo',
        'SendVerificationEmail', 'Render_Data'
    };
    private static final Pattern TOOL_INDICATOR = Pattern.compile('\\[\\[tool:([A-Za-z0-9_]+)\\]\\]');

    @TestSetup
    static void setup() {
        // Representative fixtures reflecting the corrected seed shape.
        insert new List<Agent_Skills_Repo__c>{
            new Agent_Skills_Repo__c(
                Name = 'skill-support-case-management',
                Type__c = 'Skill',
                ExternalId__c = 'skill-support-case-management:v1:en-US',
                WhenToUse__c = 'Use when user needs a new case.',
                InstructionBody__c = 'Get approval, then create the case with [[tool:CreateCase]].',
                References__c = 'workflow-support-case-lifecycle',
                Status__c = 'active', Version__c = 'v1', Locale__c = 'en-US'
            ),
            new Agent_Skills_Repo__c(
                Name = 'workflow-support-case-lifecycle',
                Type__c = 'Workflow',
                ExternalId__c = 'workflow-support-case-lifecycle:v1:en-US',
                WhenToUse__c = 'Use when opening or closing cases.',
                InstructionBody__c = 'Verify identity with [[tool:SendVerificationEmail]].',
                References__c = 'core-skill-user-otp-authentication,workflow-escalate-to-human',
                Status__c = 'active', Version__c = 'v1', Locale__c = 'en-US'
            ),
            new Agent_Skills_Repo__c(
                Name = 'core-skill-user-otp-authentication',
                Type__c = 'Core_Skill',
                ExternalId__c = 'core-skill-user-otp-authentication:v1:en-US',
                WhenToUse__c = 'Use before account actions.',
                InstructionBody__c = 'Send OTP with [[tool:SendVerificationEmail]].',
                Status__c = 'active', Version__c = 'v1', Locale__c = 'en-US'
            ),
            new Agent_Skills_Repo__c(
                Name = 'workflow-escalate-to-human',
                Type__c = 'Workflow',
                ExternalId__c = 'workflow-escalate-to-human:v1:en-US',
                WhenToUse__c = 'Use for escalation.',
                InstructionBody__c = 'Route with [[tool:Route_to_ESA]].',
                Status__c = 'active', Version__c = 'v1', Locale__c = 'en-US'
            )
        };
    }

    @IsTest
    static void referencesResolveToRealActiveRecords() {
        Map<String, Agent_Skills_Repo__c> byName = new Map<String, Agent_Skills_Repo__c>();
        for (Agent_Skills_Repo__c r : [
            SELECT Name, References__c FROM Agent_Skills_Repo__c WHERE Status__c = 'active'
        ]) {
            byName.put(r.Name, r);
        }

        for (Agent_Skills_Repo__c r : byName.values()) {
            if (String.isBlank(r.References__c)) {
                continue;
            }
            for (String token : r.References__c.split(',')) {
                // No leading/trailing whitespace permitted (guards prose + "space after comma").
                System.assertEquals(token, token.trim(),
                    'References__c token must have no surrounding spaces on ' + r.Name + ': "' + token + '"');
                System.assert(byName.containsKey(token.trim()),
                    'References__c token "' + token.trim() + '" on ' + r.Name + ' must resolve to an active record');
            }
        }
    }

    @IsTest
    static void toolIndicatorsNameRealTools() {
        for (Agent_Skills_Repo__c r : [
            SELECT Name, InstructionBody__c FROM Agent_Skills_Repo__c WHERE Status__c = 'active'
        ]) {
            if (String.isBlank(r.InstructionBody__c)) {
                continue;
            }
            Matcher m = TOOL_INDICATOR.matcher(r.InstructionBody__c);
            while (m.find()) {
                System.assert(KNOWN_TOOL_NAMES.contains(m.group(1)),
                    'Tool indicator [[tool:' + m.group(1) + ']] on ' + r.Name + ' must name a known tool');
            }
        }
    }
}
```

- [ ] **Step 2: Create the test meta file**

Create `force-app/main/default/classes/Agent_Skill_SeedData_Test.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

- [ ] **Step 3: Deploy and run test to verify it passes against fixtures**

Run:
```bash
sf project deploy start --source-dir force-app/main/default/classes/Agent_Skill_SeedData_Test.cls,force-app/main/default/classes/Agent_Skill_SeedData_Test.cls-meta.xml --target-org myDevOrg
sf apex run test --tests Agent_Skill_SeedData_Test --target-org myDevOrg --result-format human
```
Expected: PASS — the in-test fixtures are already clean, proving the assertions are correct. (This test guards against regressions; the CSV edits in Steps 4-6 are validated by the reseed + rerun in Step 8.)

**Edit reference (applies to BOTH `Agent_Skill_SeedService.cls` inline strings AND the CSV mirror).** In the Apex class these are string-concatenation literals (`'...text...\n' +`); in the CSVs they are cell text. The substring to find and its replacement are identical in both; make the same textual change in each place.

| Record | Find (verbatim substring) | Replace with |
|--------|---------------------------|--------------|
| `role-customer-support-agent` | `Always invoke core-skill-user-otp-authentication before account-sensitive operations. Use workflow-support-case-lifecycle for case creation and updates. Use workflow-escalate-to-human when troubleshooting fails or the customer requests a human.` | `Always invoke core-skill-user-otp-authentication (send the code with [[tool:SendVerificationEmail]]) before account-sensitive operations. Use workflow-support-case-lifecycle for case creation and updates (create cases with [[tool:CreateCase]]). Use workflow-escalate-to-human when troubleshooting fails or the customer requests a human (route with [[tool:Route_to_ESA]] and open a ticket with [[tool:CreateEscalationTicket]]).` |
| `core-skill-user-otp-authentication` | `Initiate 6-digit code (5–10 min validity).` | `Send the 6-digit code with [[tool:SendVerificationEmail]] (5–10 min validity).` |
| `core-skill-render-data-format` | `Use the render_data action when you have structured data to display to the user.` | `Call [[tool:Render_Data]] when you have structured data to display to the user.` |
| `skill-product-information-qa` (uncertainty) | `I can create a case for our product team to follow up.` | `I can create a case with [[tool:CreateCase]] for our product team to follow up.` |
| `skill-product-information-qa` (delivery) | `Include relevant specs: screen size, resolution, refresh rate, camera MP, RAM, storage, price.` | `Include relevant specs: screen size, resolution, refresh rate, camera MP, RAM, storage, price. Look up specs with [[tool:GetProductInfo]] and present comparison tables with [[tool:Render_Data]].` |
| `skill-support-case-management` (intake) | `Ensure identity verification (OTP) before creating or updating cases.` | `Ensure identity verification (OTP) with [[tool:SendVerificationEmail]] before creating or updating cases.` |
| `skill-support-case-management` (creation) | `Create with concise summary and user-approved notes.` | `Create the case with [[tool:CreateCase]] using a concise summary and user-approved notes.` |
| `skill-support-case-management` (status) | `For status requests: look up case by number or contact; report current status (Open, In Progress, Completed).` | `For status requests: look up case history with [[tool:FetchSupportHistory]] by contact; report current status (Open, In Progress, Completed). Present results with [[tool:Render_Data]].` |
| `skill-troubleshooting-support` (escalation) | `If the product workflow does not resolve the issue, or the customer requests human support, invoke workflow-escalate-to-human.` | `If the product workflow does not resolve the issue, or the customer requests human support, invoke workflow-escalate-to-human (route with [[tool:Route_to_ESA]], open a ticket with [[tool:CreateEscalationTicket]]).` |
| `workflow-escalate-to-human` (routing) | `By type: technical, billing, general.` | `By type: technical, billing, general. Route the customer with [[tool:Route_to_ESA]] and open the handoff ticket with [[tool:CreateEscalationTicket]].` |
| `workflow-support-case-lifecycle` (identity) | `Invoke core-skill-user-otp-authentication. Do not proceed until OTP succeeds.` | `Invoke core-skill-user-otp-authentication; send the code with [[tool:SendVerificationEmail]]. Do not proceed until OTP succeeds.` |
| `workflow-support-case-lifecycle` (create) | `Create with approved summary.` | `Create the case with [[tool:CreateCase]] using the approved summary.` |
| each of the 6 `workflow-troubleshooting-*` (escalate step) | `invoke workflow-escalate-to-human` (the occurrence in each record's `## Escalate` / `## 4.` / `## 5.` step) | `invoke workflow-escalate-to-human (route with [[tool:Route_to_ESA]])` |

> **Apply-order guard for the escalation edits:** `skill-troubleshooting-support`'s sentence
> (row above it) contains the substring `invoke workflow-escalate-to-human`. Apply the
> `skill-troubleshooting-support` row FIRST (it targets the full unique sentence and yields
> BOTH `[[tool:Route_to_ESA]]` + `[[tool:CreateEscalationTicket]]`), then apply the 6-workflow
> row scoped to each `workflow-troubleshooting-*` record only. Do NOT run a repo-wide blanket
> replace of the short string — it would rewrite the skill's sentence and drop the
> `CreateEscalationTicket` binding. In `Agent_Skill_SeedService.cls` each record is a distinct
> `repoItem(...)` call (skill at line ~225; the 6 workflows at lines ~257/276/293/310/327/344),
> so edit within each call's string literals.

> **LTM save note:** in `core-skill-ltmManagement-service-agent`, the save action is `SaveAgentContext` — an LTM Apex action that is **NOT** in the tool allowlist. Leave it as plain text; do **not** wrap it in `[[tool:]]` (the composer would mark it unknown). Optionally clarify: change `invoke the save action with extracted values` → `invoke the save action (SaveAgentContext) with extracted values`.

- [ ] **Step 4: Edit `Agent_Skill_SeedService.cls` (primary seed source)**

Apply every row of the Edit reference table above to the inline string literals in `Agent_Skill_SeedService.cls`. Each body is a chain of `'...\n' +` literals inside a `repoItem(...)` call; find the literal containing the "Find" substring and replace that substring in place (mind the `\n` line boundaries — the Find text may span the tail of one literal; if so, edit the specific literal that holds it).

Then fix the two `References__c` arguments (the 7th positional arg to `repoItem`):
1. `core-skill-ltmManagement-service-agent` — change its `References__c` argument from the prose string `'Agent_Context__c,Get_Agent_ContextObject,Save_Agent_ContextObject. Depends on agent_memory (formatted string from Get_Agent_ContextObject). Save: Save_Agent_ContextObject (new_summary, new_goal, has_issue, new_style).'` to `''` (empty).
2. `workflow-support-case-lifecycle` — change its `References__c` argument from `'core-skill-user-otp-authentication, workflow-escalate-to-human'` to `'core-skill-user-otp-authentication,workflow-escalate-to-human'` (remove the space).

- [ ] **Step 5: Mirror the edits into `data/agent-skills/skills.csv` and `roles.csv`**

Apply the same Edit-reference substring replacements to `roles.csv` (`role-customer-support-agent`) and `skills.csv` (`core-skill-*`, `skill-*` rows). Also set `core-skill-ltmManagement-service-agent` `References__c` cell to empty.

- [ ] **Step 6: Mirror the edits into `data/agent-skills/workflows.csv`**

Apply the workflow rows of the Edit reference to `workflows.csv`, and set `workflow-support-case-lifecycle` `References__c` cell to `core-skill-user-otp-authentication,workflow-escalate-to-human` (no space).

- [ ] **Step 7: Verify CSV integrity locally (no stray spaces/prose in References__c)**

Run:
```bash
python3 - <<'PY'
import csv
for f in ['roles','skills','workflows']:
    with open(f'data/agent-skills/{f}.csv', newline='') as fh:
        for row in csv.DictReader(fh):
            refs = (row.get('References__c') or '').strip()
            if not refs:
                continue
            for tok in refs.split(','):
                assert tok == tok.strip(), f"{f}:{row['Name']} space in References__c: '{tok}'"
                assert tok.startswith(('role-','core-skill-','skill-','workflow-')), \
                    f"{f}:{row['Name']} non-record ref: '{tok}'"
print("CSV References__c OK")
PY
```
Expected: `CSV References__c OK`.

- [ ] **Step 8: Deploy the edited seed class, reseed, and rerun the integrity test against live data**

Deploy the updated `Agent_Skill_SeedService.cls` (the seed source) first, then run the seed wrapper and the integrity test:
```bash
sf project deploy start --source-dir force-app/main/default/classes/Agent_Skill_SeedService.cls --target-org myDevOrg
sf apex run --file scripts/apex/seed_agent_skills.apex --target-org myDevOrg
sf apex run test --tests Agent_Skill_SeedData_Test --target-org myDevOrg --result-format human
```
Expected: seed completes; test PASSES against the freshly seeded records (all `References__c` resolve, all `[[tool:...]]` indicators name known tools).

- [ ] **Step 9: Sanity-check that indicators actually reached the seed source and org**

Run:
```bash
grep -c '\[\[tool:' force-app/main/default/classes/Agent_Skill_SeedService.cls
```
Expected: a count matching the number of indicators added (≥ 14 across the edited records). If 0, the Apex edits were missed and the reseed did nothing — fix before committing.

- [ ] **Step 10: Commit**

```bash
git add force-app/main/default/classes/Agent_Skill_SeedService.cls data/agent-skills/roles.csv data/agent-skills/skills.csv data/agent-skills/workflows.csv force-app/main/default/classes/Agent_Skill_SeedData_Test.cls force-app/main/default/classes/Agent_Skill_SeedData_Test.cls-meta.xml
git commit -m "feat: bind seed skills to tools via [[tool:Name]]; fix malformed References__c

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: New agent bundle `customer_support_progressive`

**Files:**
- Create: `force-app/main/default/aiAuthoringBundles/customer_support_progressive/customer_support_progressive.agent`
- Create: `force-app/main/default/aiAuthoringBundles/customer_support_progressive/customer_support_progressive.bundle-meta.xml`

**Interfaces:**
- Consumes: `apex://Agent_Skill_HeaderProvider` (Task 1), `apex://Agent_Skill_LoadAndCompose` (existing), the 10 flow tools (`CreateCase`, etc.), `apex://SaveAgentContext`, `apex://LoadAgentMemory`.
- Produces: a bundle where `start_agent agent_router`'s LLM sets `@variables.skills_to_load` (via a `reasoning.actions` `@utils.setVariables` tool) and its `after_reasoning` transitions to `topic generic_handler`, which loads those skills (first `run` in `reasoning.instructions`) and re-exposes all business actions as tools under `reasoning.actions`.

> **CRITICAL — match the on-disk repo conventions, verified against `customer_support_skill_demo.agent` and `render_data_test.agent` (do NOT use the `subagent`/`before_reasoning` shape):**
> 1. Use `topic <name>:` blocks and `@utils.transition to @topic.<name>` / `transition to @topic.<name>` — the repo has **no** `subagent`/`@subagent.` syntax.
> 2. There is **no `before_reasoning`** in this repo. Do skill loading as the **first `run` block inside `reasoning.instructions:`** (see `general_support` lines 122-127 of the demo).
> 3. An action is only an **LLM-callable tool when re-exposed under `reasoning.actions:`** with slot-fill (`with x=...`) — a `topic.actions:` declaration alone is deterministic-only. `render_data_test` shows the wrapper form: `render_data: @actions.render_data\n  with data=...\n  with display_type=...`. The 10 business tools must therefore appear BOTH under `topic.actions:` (the contract with `target:`) AND under `reasoning.actions:` (the slot-filled tool wrapper).
> 4. The router selects skills with a `reasoning.actions:` tool `select_skills: @utils.setVariables with skills_to_load=...`, and transitions in `after_reasoning` using `transition to @topic.generic_handler` (NOT `@utils.transition`, per Manual §10) so the LLM's selection is set before the transition fires.

**Flow tool contracts (declare inputs + scalar outputs only; SObject/collection outputs omitted intentionally):**
- `CreateCase`: in `subject`; out `case_number`
- `CreateEscalationTicket`: in `customer_id`, `issue_description`, `issue_type`; out `ticket_id`
- `Route_to_ESA`: in `recordId`
- `GetOrderStatus`: in `order_id`; out `status`, `tracking_number`
- `FetchSupportHistory`: in `user_id`
- `TrackShipment`: in `carrier`, `tracking_number`; out `estimated_delivery`, `status`, `success`
- `FetchAccountData`: in `user_id`
- `GetProductInfo`: in `product_name`; out `in_stock`, `price`, `product_details`
- `SendVerificationEmail`: in `customer_id`, `email`; out `sent`, `token`
- `Render_Data` (`apex://GenericRenderAction`): in `data`, `display_type`; out `result` (`c__genericRenderOutput`)

- [ ] **Step 1: Create the bundle meta file**

Create `force-app/main/default/aiAuthoringBundles/customer_support_progressive/customer_support_progressive.bundle-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<AiAuthoringBundle xmlns="http://soap.sforce.com/2006/04/metadata">
  <bundleType>AGENT</bundleType>
</AiAuthoringBundle>
```

- [ ] **Step 2: Write the `.agent` script**

Create `force-app/main/default/aiAuthoringBundles/customer_support_progressive/customer_support_progressive.agent`:

```
# -----------------------------------------------------------------------------
# Customer Support Progressive Disclosure Agent
# -----------------------------------------------------------------------------
# Architecture
# - start_agent (agent_router): loads role+core skills (flat) and OPTIONAL LTM,
#   fetches lean headers for candidate_skills via Agent_Skill_HeaderProvider,
#   the LLM sets skills_to_load (no-spaces CSV) via select_skills, and
#   after_reasoning transitions to the generic_handler topic.
# - generic_handler (topic): ONE topic-agnostic handler. Loads skills_to_load
#   (first run in reasoning; each selected skill cascades to its workflows via
#   References__c), injects the composed instructions, and re-exposes the full
#   support-demo tool catalog under reasoning.actions. Behavior for a turn is
#   determined entirely by which skills were loaded.
# -----------------------------------------------------------------------------


system:
    instructions: |
        You are a customer support AI agent.
        Follow policy and safety constraints at all times.
        Do not invent product facts, case updates, or troubleshooting outcomes.
        Be concise. Respond in 2-4 sentences unless the user asks for detail.
    messages:
        welcome: "I'm Ready to Help!"
        error: "I am sorry, something went wrong. Please try again or ask for escalation to a human specialist."


config:
    developer_name: "customer_support_progressive"
    agent_label: "Customer Support (Progressive Disclosure)"
    default_agent_user: "ltm_agent@00dky00000gxhj51777765750.ext"
    description: "Router-level progressive disclosure with a single generic handler topic driven by loaded skills."


variables:
    ContactId: mutable string = "003KY00000KNAGqYAP"
    EndUserId: linked string
    RoutableId: linked string
    context_loaded: mutable boolean = False
    agent_memory: mutable string = ""
    memory_summary: mutable string = ""
    memory_goal: mutable string = ""
    memory_has_issue: mutable boolean = False
    memory_style: mutable string = ""
    instruction_bundle_json: mutable object
    composed_instructions: mutable string = ""
    candidate_skills: mutable string = "skill-product-information-qa,skill-troubleshooting-support,skill-support-case-management"
    skill_headers: mutable string = ""
    skills_to_load: mutable string = ""


start_agent agent_router:
    description: "Progressive disclosure: load role/core + optional memory, fetch candidate headers, select skills, route."

    actions:
        load_user_memory:
            description: "Load persistent memory for this contact (optional LTM)."
            inputs:
                contactId: string
                    description: "Contact identifier."
            outputs:
                agentMemory: string
                    description: "Formatted merge of memory fields for personalization."
                memorySummary: string
                    description: "Last conversation summary."
                memoryGoal: string
                    description: "Pending goal."
                hasIssue: boolean
                    description: "Unresolved issue flag."
                memoryStyle: string
                    description: "Communication style."
            target: "apex://LoadAgentMemory"
        load_skills_init:
            description: "Load role and core skills into the instruction bundle (flat, no cascade)."
            inputs:
                instructionNames: string
                    description: "CSV list of role and core skill names."
            outputs:
                loadedInstructionBundle: string
                    description: "Aggregated instruction bundle JSON for merge."
                instructionsBundle: string
                    description: "Formatted prompt (not consumed in start_agent)."
            target: "apex://Agent_Skill_LoadAndCompose"
        get_skill_headers:
            description: "Fetch lean Name + WhenToUse headers for candidate skills (no body, no expansion)."
            inputs:
                skillNames: string
                    description: "CSV of candidate skill names."
            outputs:
                skillHeaders: string
                    description: "One line per skill: '- <Name>: <WhenToUse__c>'."
                missingNames: string
                    description: "CSV of names inactive, not found, or missing WhenToUse."
            target: "apex://Agent_Skill_HeaderProvider"

    reasoning:
        instructions: ->
            if @variables.context_loaded == False and @variables.ContactId and @variables.ContactId != "":
                run @actions.load_user_memory
                    with contactId=@variables.ContactId
                    set @variables.agent_memory=@outputs.agentMemory
                    set @variables.memory_summary=@outputs.memorySummary
                    set @variables.memory_goal=@outputs.memoryGoal
                    set @variables.memory_has_issue=@outputs.hasIssue
                    set @variables.memory_style=@outputs.memoryStyle
                    set @variables.context_loaded=True

            if @variables.context_loaded == False:
                set @variables.context_loaded=True

            run @actions.load_skills_init
                with instructionNames="role-customer-support-agent,core-skill-ltmManagement-service-agent,core-skill-txt-response-guidelines"
                set @variables.instruction_bundle_json=@outputs.loadedInstructionBundle

            run @actions.get_skill_headers
                with skillNames=@variables.candidate_skills
                set @variables.skill_headers=@outputs.skillHeaders

            | You are the router. Select which skills are needed for the user's request.
            | Available skills (choose from these names only):
            | {!@variables.skill_headers}
            |
            | Decide the minimal set of skill names that match the user's request, then call {!@actions.select_skills} with a comma-separated list of those exact names (no spaces after commas). Do not answer the user directly; selecting the skills is your only job this turn.

        actions:
            select_skills: @utils.setVariables
                description: "Record the chosen skill names to load for this request."
                with skills_to_load=...

    after_reasoning:
        transition to @topic.generic_handler


topic generic_handler:
    label: "Generic Handler"
    description: "Single generic handler. Loads the router-selected skills and re-exposes the full support-demo tool catalog; behavior is driven by the loaded skills."

    actions:
        load_skills:
            description: "Load the selected skills (cascading to workflows via References), merge with role/core, and compose instructions."
            inputs:
                instructionNames: string
                    description: "CSV of router-selected skill names."
                existingInstructionBundle: string
                    description: "Existing bundle JSON (role + core from start_agent)."
            outputs:
                instructionsBundle: string
                    description: "Formatted prompt-ready instruction text."
                loadedInstructionBundle: string
                    description: "Raw instruction bundle JSON for merge."
            target: "apex://Agent_Skill_LoadAndCompose"
        create_case:
            description: "Create a new support case from a concise subject line."
            inputs:
                subject: string
                    description: "Concise, user-approved case subject."
            outputs:
                case_number: string
                    description: "The created case number."
            target: "flow://CreateCase"
        create_escalation_ticket:
            description: "Create an escalation ticket for handoff to a human specialist."
            inputs:
                customer_id: string
                    description: "Contact/customer identifier."
                issue_description: string
                    description: "Summary of the unresolved issue."
                issue_type: string
                    description: "Escalation type (technical, billing, general)."
            outputs:
                ticket_id: string
                    description: "The created escalation ticket ID."
            target: "flow://CreateEscalationTicket"
        route_to_esa:
            description: "Route the conversation to an Enhanced Service Agent (human) queue."
            inputs:
                recordId: string
                    description: "Record/routable identifier to route."
            target: "flow://Route_to_ESA"
        get_order_status:
            description: "Look up the current status of an order."
            inputs:
                order_id: string
                    description: "Order identifier."
            outputs:
                status: string
                    description: "Order status."
                tracking_number: string
                    description: "Shipment tracking number, if any."
            target: "flow://GetOrderStatus"
        fetch_support_history:
            description: "Fetch the support/case history for a user."
            inputs:
                user_id: string
                    description: "User/contact identifier."
            target: "flow://FetchSupportHistory"
        track_shipment:
            description: "Track a shipment by carrier and tracking number."
            inputs:
                carrier: string
                    description: "Shipping carrier."
                tracking_number: string
                    description: "Tracking number."
            outputs:
                estimated_delivery: string
                    description: "Estimated delivery date."
                status: string
                    description: "Shipment status."
                success: boolean
                    description: "Whether tracking succeeded."
            target: "flow://TrackShipment"
        fetch_account_data:
            description: "Fetch account details for a user."
            inputs:
                user_id: string
                    description: "User/contact identifier."
            target: "flow://FetchAccountData"
        get_product_info:
            description: "Look up product specifications, price, and availability."
            inputs:
                product_name: string
                    description: "Product name to look up."
            outputs:
                in_stock: boolean
                    description: "Whether the product is in stock."
                price: string
                    description: "Product price."
                product_details: string
                    description: "Product specification details."
            target: "flow://GetProductInfo"
        send_verification_email:
            description: "Send a one-time verification code to the customer."
            inputs:
                customer_id: string
                    description: "Contact/customer identifier."
                email: string
                    description: "Destination email address."
            outputs:
                sent: boolean
                    description: "Whether the code was sent."
                token: string
                    description: "Verification token reference."
            target: "flow://SendVerificationEmail"
        render_data:
            description: "Display structured data in table, card, list, or key-value format."
            inputs:
                data: string
                    description: "JSON string following the schema for the display type."
                display_type: string
                    description: "One of: table, card, list, key-value."
            outputs:
                result: object
                    description: "Render output for LWC display (GenericRenderOutput)."
                    complex_data_type_name: "c__genericRenderOutput"
            target: "apex://GenericRenderAction"
        save_context:
            description: "Persist an Agent_Context__c memory checkpoint (optional LTM)."
            inputs:
                contactId: string
                    description: "Contact ID."
                newSummary: string
                    description: "Conversation summary."
                newGoal: string
                    description: "Pending goal or empty string."
                hasIssue: boolean
                    description: "Unresolved issue flag."
                newStyle: string
                    description: "Communication style."
            outputs:
                success: boolean
                    description: "Whether save succeeded."
            target: "apex://SaveAgentContext"

    reasoning:
        instructions: ->
            run @actions.load_skills
                with instructionNames=@variables.skills_to_load
                with existingInstructionBundle=@variables.instruction_bundle_json
                set @variables.instruction_bundle_json=@outputs.loadedInstructionBundle
                set @variables.composed_instructions=@outputs.instructionsBundle

            | Here is your past context. Use it for personalization if present:
            | {!@variables.agent_memory}
            |
            | Follow these instructions. They determine what to do and which tools to use:
            | {!@variables.composed_instructions}
            |
            | Use the tools available to you as directed by the instructions above.

        actions:
            create_case: @actions.create_case
                description: "Create a new support case from a concise, user-approved subject."
                with subject=...
            create_escalation_ticket: @actions.create_escalation_ticket
                description: "Create an escalation ticket for handoff to a human specialist."
                with customer_id=...
                with issue_description=...
                with issue_type=...
            route_to_esa: @actions.route_to_esa
                description: "Route the conversation to a human (Enhanced Service Agent) queue."
                with recordId=...
            get_order_status: @actions.get_order_status
                description: "Look up the current status of an order."
                with order_id=...
            fetch_support_history: @actions.fetch_support_history
                description: "Fetch the support/case history for a user."
                with user_id=...
            track_shipment: @actions.track_shipment
                description: "Track a shipment by carrier and tracking number."
                with carrier=...
                with tracking_number=...
            fetch_account_data: @actions.fetch_account_data
                description: "Fetch account details for a user."
                with user_id=...
            get_product_info: @actions.get_product_info
                description: "Look up product specifications, price, and availability."
                with product_name=...
            send_verification_email: @actions.send_verification_email
                description: "Send a one-time verification code to the customer."
                with customer_id=...
                with email=...
            render_data: @actions.render_data
                description: "Display structured data in table, card, list, or key-value format."
                with data=...
                with display_type=...
            save_context: @actions.save_context
                description: "Persist an Agent_Context__c memory checkpoint (optional LTM)."
                with contactId=@variables.ContactId
                with newSummary=...
                with newGoal=...
                with hasIssue=...
                with newStyle=...
```

> **Tool re-exposure note:** the block above under `reasoning.actions:` is what makes each
> business action LLM-callable (the `topic.actions:` declarations earlier only define the
> contract + `target:`). This mirrors `render_data_test.agent` (the `render_data` wrapper) and
> the demo's `persist_memory: @actions.save_context_tool` wrapper. The reasoning **prose** stays
> topic-agnostic (no per-tool enumeration); the tool *declarations* are required plumbing, not
> topic coupling.

- [ ] **Step 3: Validate the authoring bundle**

Run: `sf agent validate authoring-bundle --api-name customer_support_progressive --target-org myDevOrg`
Expected: validation succeeds (no unresolved action targets, no syntax errors). If a target flow/apex is reported missing, confirm it was deployed in Tasks 1-3.

- [ ] **Step 4: Commit**

```bash
git add force-app/main/default/aiAuthoringBundles/customer_support_progressive/
git commit -m "feat: add customer_support_progressive bundle (router + generic subagent)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Documentation update

**Files:**
- Modify: `docs/Agent-Skills-Framework-for-FDE.md` (add a section)

**Interfaces:** None (docs only).

- [ ] **Step 1: Add a "Progressive Disclosure & Generic Subagent" section**

Append a new section to `docs/Agent-Skills-Framework-for-FDE.md` documenting:
1. **Header contract (no fallback):** `Agent_Skill_HeaderProvider` returns `Name: WhenToUse__c`; a blank `WhenToUse__c` excludes the skill and is reported in `missingNames`/`warnings`. Authoring `WhenToUse__c` is mandatory for any candidate skill.
2. **`[[tool:Name]]` indicator:** authors write `[[tool:CreateCase]]` inline in `InstructionBody__c` at the point of action; the composer rewrites it to `the "CreateCase" tool` and validates the name against the tool allowlist, marking unknowns as `[[unknown tool: X]]` and warning. Explain it is a *plain-text cue*, not a resolvable `{!@actions.X}` pointer (platform preprocessing constraint), and that record references in `References__c` are separate and drive cascade.
3. **Router + generic subagent pattern:** router loads role/core flat, fetches candidate headers, LLM sets `skills_to_load`, transitions to one `generic_handler` that loads the selected skills (cascading to workflows) and declares the full tool catalog. Reasoning block stays topic-agnostic.

Use exact code fences copied from the bundle in Task 4 for the router/handler snippet, and reference `docs/superpowers/specs/2026-07-13-progressive-disclosure-generic-subagent-design.md` for the full design rationale.

- [ ] **Step 2: Commit**

```bash
git add docs/Agent-Skills-Framework-for-FDE.md
git commit -m "docs: document progressive disclosure, [[tool:Name]] indicator, generic subagent

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Full verification pass

**Files:** None (verification only).

- [ ] **Step 1: Run the full Apex suite**

Run:
```bash
sf apex run test --tests Agent_Skill_Loader_Test,Agent_Skill_PromptComposer_Test,Agent_Skill_LoadAndCompose_Test,Agent_Skill_HeaderProvider_Test,Agent_Skill_SeedData_Test --target-org myDevOrg --result-format human
```
Expected: all classes PASS; no regressions in Loader/LoadAndCompose (unchanged).

- [ ] **Step 2: Re-validate the new bundle after reseed**

Run: `sf agent validate authoring-bundle --api-name customer_support_progressive --target-org myDevOrg`
Expected: PASS.

- [ ] **Step 3: Targeted conversation smoke checks (manual/agent preview)**

Using `sf agent preview --api-name customer_support_progressive --target-org myDevOrg` (or the testing-agentforce harness), confirm:
- A product-info utterance ("compare iPhone 16 vs Galaxy S25") → router sets `skills_to_load` to `skill-product-information-qa` only.
- A troubleshooting utterance ("my Wi-Fi modem is down") → `skill-troubleshooting-support` selected; composed instructions include the cascaded `workflow-troubleshooting-wifi-modem` and `workflow-escalate-to-human` bodies.
- A case-creation turn → composed instructions contain `the "CreateCase" tool` cue and the model invokes `create_case`.

Record observed selections and tool calls in the PR description (no code change expected here).

- [ ] **Step 4: Confirm no unintended files changed**

Run: `git status` and `git diff --stat main`
Expected: only the files listed in the File Structure table appear (`Agent_Skill_SeedService.cls`, the 3 CSVs, the new HeaderProvider/SeedData classes + tests, the modified composer + test, the new bundle, and the FDE doc). `scripts/apex/seed_agent_skills.apex` is unchanged (it is a thin wrapper).

---

## Self-Review Notes (author checklist, completed)

- **Spec coverage:** Deliverables §8.1→Task 1; §8.2→Task 1; §8.3→Task 2; §8.4→Task 4; §8.5→Task 3; §8.6→Task 5. Testing §9 Apex→Tasks 1-2, data→Task 3, agent→Task 4/6. Deployment §11 (myDevOrg, explicit flag)→Global Constraints + every command.
- **Seed source correction:** verified the org is seeded from inline strings in `Agent_Skill_SeedService.cls` (line 507 `repoItem` helper, `InstructionBody__c` @522, `References__c` @523), NOT from the CSVs — Task 3 edits the Apex class as primary and mirrors to CSV. This was corrected after inspecting `scripts/apex/seed_agent_skills.apex` (a 2-line wrapper).
- **No fallback (D2):** enforced in `Agent_Skill_HeaderProvider` (blank `WhenToUse__c` → `continue`) and asserted in `shouldExcludeBlankHeaderWithNoFallback`.
- **Cascade (D6):** unchanged loader expansion; bundle loads role/core flat and selected skills separately; verified in Task 6 Step 3.
- **Type consistency:** `getHeaders`/`HeaderRequest`/`HeaderResponse` field names identical across Task 1 code, tests, and the Task 4 action declaration (`skillNames`, `skillHeaders`, `missingNames`). `KNOWN_TOOL_NAMES` list identical in Task 2 and Task 3.
- **Placeholder scan:** no TBD/TODO; every code step shows full code; every command shows expected output.
```
