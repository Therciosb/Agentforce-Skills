public with sharing class Agent_Skill_Test_Runner {
    private static final String TEMPLATE_API_NAME = 'Route_Agent_Skill';
    private static final Integer RUN_ID_LENGTH = 40;

    // Test seam: when set, used instead of a live prompt-template call.
    @TestVisible private static String routeOverride;

    public class CaseResult {
        @AuraEnabled public Id testCaseId;
        @AuraEnabled public Id resultId;
        @AuraEnabled public String name;
        @AuraEnabled public String subagent;
        @AuraEnabled public Boolean passed;
        @AuraEnabled public String expectedSkills;
        @AuraEnabled public String selectedSkills;
        @AuraEnabled public String enabledTools;
        @AuraEnabled public String missingTools;
        @AuraEnabled public String reason;
        @AuraEnabled public String warnings;
    }

    // Blank subagentName returns every case for the agent.
    @AuraEnabled
    public static List<Agent_Skill_Test_Case__c> listCases(String agentName, String subagentName) {
        List<Agent_Skill_Test_Case__c> cases = [
            SELECT Id, Name, Agent_Developer_Name__c, Subagent__c, Utterance__c, Expected_Skills__c, Expected_Tools__c,
                Expected_Outcome__c, Active__c, Last_Status__c, Last_Run__c
            FROM Agent_Skill_Test_Case__c
            WHERE Agent_Developer_Name__c = :agentName
            WITH USER_MODE
            ORDER BY Subagent__c NULLS FIRST, Name
            LIMIT 500
        ];
        if (String.isBlank(subagentName)) {
            return cases;
        }
        List<Agent_Skill_Test_Case__c> matching = new List<Agent_Skill_Test_Case__c>();
        for (Agent_Skill_Test_Case__c tc : cases) {
            if (String.isNotBlank(tc.Subagent__c) && tc.Subagent__c.trim().equalsIgnoreCase(subagentName.trim())) {
                matching.add(tc);
            }
        }
        return matching;
    }

    @AuraEnabled
    public static CaseResult runCase(Id testCaseId, String runId) {
        List<Agent_Skill_Test_Case__c> found = [
            SELECT Id, Name, Agent_Developer_Name__c, Subagent__c, Utterance__c, Expected_Skills__c, Expected_Tools__c
            FROM Agent_Skill_Test_Case__c
            WHERE Id = :testCaseId
            WITH USER_MODE
        ];
        if (found.isEmpty()) {
            throw new AuraHandledException('Test case not found.');
        }
        Agent_Skill_Test_Case__c tc = found[0];
        if (String.isBlank(tc.Utterance__c)) {
            throw new AuraHandledException('Test case "' + tc.Name + '" has no utterance.');
        }

        Agent_Skill_State.recordUsage = false;
        List<String> warnings = new List<String>();
        Agent_Skill_State.SkillState baseline = resolveState(tc.Agent_Developer_Name__c, tc.Subagent__c, '');

        String raw;
        try {
            raw = routeOverride != null
                ? routeOverride
                : invokeTemplate(baseline.skill_menu, baseline.active_skills, tc.Utterance__c);
        } catch (Exception ex) {
            throw new AuraHandledException('Routing prompt failed: ' + ex.getMessage());
        }
        Map<String, Object> routing = parseJson(raw);
        List<String> chosen = new List<String>();
        String reason;
        if (routing == null) {
            warnings.add('Router response was not JSON: ' + raw.abbreviate(200));
        } else {
            reason = routing.get('reason') == null ? null : String.valueOf(routing.get('reason'));
            if (routing.get('skills') instanceof List<Object>) {
                for (Object o : (List<Object>) routing.get('skills')) {
                    if (o != null && String.isNotBlank(String.valueOf(o))) {
                        chosen.add(String.valueOf(o).trim());
                    }
                }
            }
        }

        Agent_Skill_State.SkillState state = resolveState(tc.Agent_Developer_Name__c, tc.Subagent__c, String.join(chosen, ','));
        if (String.isNotBlank(state.skill_warnings)) {
            warnings.add(state.skill_warnings);
        }

        Set<String> expected = csvSet(tc.Expected_Skills__c);
        Boolean skillsMatch = expected.isEmpty() || expected.equals(csvSet(state.active_skills));
        List<String> enabled = new List<String>();
        for (String tool : state.tools.keySet()) {
            if (state.tools.get(tool) == true) {
                enabled.add(tool);
            }
        }
        enabled.sort();
        List<String> missing = new List<String>();
        for (String tool : csvSet(tc.Expected_Tools__c)) {
            if (state.tools.get(tool) != true) {
                missing.add(tool);
            }
        }
        missing.sort();

        CaseResult result = new CaseResult();
        result.testCaseId = tc.Id;
        result.name = tc.Name;
        result.subagent = tc.Subagent__c;
        result.passed = routing != null && skillsMatch && missing.isEmpty();
        result.expectedSkills = tc.Expected_Skills__c;
        result.selectedSkills = state.active_skills;
        result.enabledTools = String.join(enabled, ',');
        result.missingTools = String.join(missing, ',');
        result.reason = reason;
        result.warnings = String.join(warnings, ' | ');

        Agent_Skill_Test_Result__c rec = new Agent_Skill_Test_Result__c(
            Test_Case__c = tc.Id,
            Run_Id__c = runId == null ? null : runId.left(RUN_ID_LENGTH),
            Agent_Name__c = tc.Agent_Developer_Name__c,
            Subagent__c = tc.Subagent__c,
            Expected_Skills__c = tc.Expected_Skills__c,
            Selected_Skills__c = result.selectedSkills.abbreviate(255),
            Enabled_Tools__c = result.enabledTools,
            Missing_Tools__c = result.missingTools.abbreviate(255),
            Passed__c = result.passed,
            Reason__c = reason == null ? null : reason.abbreviate(4000),
            Warnings__c = result.warnings
        );
        Database.insert(rec, AccessLevel.USER_MODE);
        Database.update(
            new Agent_Skill_Test_Case__c(Id = tc.Id, Last_Status__c = result.passed ? 'Pass' : 'Fail', Last_Run__c = System.now()),
            AccessLevel.USER_MODE
        );
        result.resultId = rec.Id;
        return result;
    }

    @AuraEnabled
    public static String exportTestSpec(String agentName) {
        List<String> lines = new List<String>{
            'name: ' + quote(agentName + ' skill routing'),
            'subjectType: AGENT',
            'subjectName: ' + agentName,
            'testCases:'
        };
        for (Agent_Skill_Test_Case__c tc : listCases(agentName, null)) {
            if (!tc.Active__c || String.isBlank(tc.Utterance__c)) {
                continue;
            }
            lines.add('  - utterance: ' + quote(tc.Utterance__c));
            String topic = expectedSubagent(tc);
            if (String.isNotBlank(topic)) {
                lines.add('    expectedTopic: ' + topic);
            }
            Set<String> tools = csvSet(tc.Expected_Tools__c);
            if (!tools.isEmpty()) {
                lines.add('    expectedActions:');
                for (String tool : tools) {
                    lines.add('      - ' + tool);
                }
            }
            if (String.isNotBlank(tc.Expected_Outcome__c)) {
                lines.add('    expectedOutcome: ' + quote(tc.Expected_Outcome__c));
            }
        }
        return String.join(lines, '\n') + '\n';
    }

    private static String expectedSubagent(Agent_Skill_Test_Case__c tc) {
        if (String.isNotBlank(tc.Subagent__c)) {
            return tc.Subagent__c.trim();
        }
        Agent_Skill_State.Wiring wiring = Agent_Skill_State.loadWiring(tc.Agent_Developer_Name__c, null);
        return wiring == null ? null : wiring.subagent;
    }

    private static Agent_Skill_State.SkillState resolveState(String agentName, String subagentName, String requestedSkills) {
        Agent_Skill_State.Request req = new Agent_Skill_State.Request();
        req.agentName = agentName;
        req.subagentName = subagentName;
        req.requestedSkills = requestedSkills;
        return Agent_Skill_State.resolve(new List<Agent_Skill_State.Request>{ req })[0].skillState;
    }

    private static String invokeTemplate(String skillMenu, String defaultSkills, String utterance) {
        ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        Map<String, ConnectApi.WrappedValue> params = new Map<String, ConnectApi.WrappedValue>();
        params.put('Input:skillMenu', wrap(String.isBlank(skillMenu) ? '(none)' : skillMenu));
        params.put('Input:defaultSkills', wrap(defaultSkills));
        params.put('Input:utterance', wrap(utterance));
        input.inputParams = params;
        input.isPreview = false;
        input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';

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
        Integer startIdx = raw.indexOf('{');
        Integer endIdx = raw.lastIndexOf('}');
        if (startIdx < 0 || endIdx <= startIdx) {
            return null;
        }
        try {
            Object o = JSON.deserializeUntyped(raw.substring(startIdx, endIdx + 1));
            return (o instanceof Map<String, Object>) ? (Map<String, Object>) o : null;
        } catch (Exception e) {
            return null;
        }
    }

    private static Set<String> csvSet(String csv) {
        Set<String> values = new Set<String>();
        if (String.isBlank(csv)) {
            return values;
        }
        for (String part : csv.split(',')) {
            if (String.isNotBlank(part)) {
                values.add(part.trim());
            }
        }
        return values;
    }

    private static String quote(String value) {
        String v = value == null ? '' : value;
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"').replace('\r', '').replace('\n', '\\n') + '"';
    }
}
