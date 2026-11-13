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
