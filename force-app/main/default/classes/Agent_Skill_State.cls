public with sharing class Agent_Skill_State {
    private static final Pattern ACTION_REF = Pattern.compile('@actions\\.([A-Za-z0-9_]+)');

    public class SkillState {
        @AuraEnabled public String skill_menu;
        @AuraEnabled public String active_skills;
        @AuraEnabled public String skill_instructions;
        @AuraEnabled public String skill_warnings;
        // Action names the active skills reference; agents gate tools with
        // available when @variables.skill_state.tools.<action> == True
        @AuraEnabled public Map<String, Boolean> tools;
    }

    public class Request {
        @InvocableVariable(required=true label='Agent Name' description='Developer name of the calling agent; selects its skill wiring.')
        public String agentName;

        @InvocableVariable(label='Requested Skills' description='CSV of selectable skill names to activate. Blank activates the defaults.')
        public String requestedSkills;
    }

    public class Response {
        @InvocableVariable(label='Skill State' description='Skill menu, active skills, composed instructions, warnings, and tool flags.')
        public SkillState skillState;

        @InvocableVariable(label='Active Skills' description='CSV of the skills actually activated.')
        public String activeSkills;
    }

    public class Wiring {
        public List<String> always = new List<String>();
        public List<String> selectable = new List<String>();
        public List<String> defaults = new List<String>();
        public String locale;
        public Boolean requireApproval = false;
        public String agentTools;
    }

    @InvocableMethod(
        label='Agent Skill State'
        description='Resolves requested skills against the agent wiring and returns the skill state object (menu, active skills, composed instructions, warnings, tool flags).'
    )
    public static List<Response> resolve(List<Request> requests) {
        List<Response> responses = new List<Response>();
        List<Agent_Skill_Usage__e> events = new List<Agent_Skill_Usage__e>();
        for (Request req : requests) {
            Long started = System.currentTimeMillis();
            Response res = resolveOne(req);
            responses.add(res);
            events.add(usageEvent(req, res.skillState, System.currentTimeMillis() - started));
        }
        publish(events);
        return responses;
    }

    private static Response resolveOne(Request req) {
        List<String> warnings = new List<String>();
        SkillState state = new SkillState();
        state.skill_menu = '';
        state.skill_instructions = '';
        state.tools = new Map<String, Boolean>();

        Wiring wiring = loadWiring(req == null ? null : req.agentName);
        if (wiring == null) {
            warnings.add('No skill wiring found for agent: ' + (req == null ? null : req.agentName));
            state.active_skills = '';
            state.skill_warnings = String.join(warnings, ' | ');
            return toResponse(state);
        }

        List<String> active = pickActive(wiring, req.requestedSkills, warnings);
        state.active_skills = String.join(active, ',');
        state.skill_menu = loadMenu(wiring, warnings);
        state.skill_instructions = loadInstructions(wiring, active, warnings);
        state.tools = referencedTools(state.skill_instructions);
        state.skill_warnings = String.join(warnings, ' | ');
        return toResponse(state);
    }

    private static List<String> pickActive(Wiring wiring, String requestedSkills, List<String> warnings) {
        Set<String> allowed = new Set<String>(wiring.selectable);
        List<String> active = new List<String>();
        for (String token : String.isBlank(requestedSkills) ? new List<String>() : requestedSkills.split(',')) {
            String name = token.trim();
            if (String.isBlank(name) || active.contains(name)) {
                continue;
            }
            if (allowed.contains(name)) {
                active.add(name);
            } else {
                warnings.add('Not wired to this agent: ' + name);
            }
        }
        if (active.isEmpty()) {
            active.addAll(wiring.defaults);
        }
        return active;
    }

    private static String loadMenu(Wiring wiring, List<String> warnings) {
        if (wiring.selectable.isEmpty()) {
            return '';
        }
        Agent_Skill_HeaderProvider.HeaderRequest headerReq = new Agent_Skill_HeaderProvider.HeaderRequest();
        headerReq.skillNames = String.join(wiring.selectable, ',');
        headerReq.locale = wiring.locale;
        headerReq.requireApproval = wiring.requireApproval;
        Agent_Skill_HeaderProvider.HeaderResponse headerRes =
            Agent_Skill_HeaderProvider.getHeaders(new List<Agent_Skill_HeaderProvider.HeaderRequest>{ headerReq })[0];
        if (String.isNotBlank(headerRes.warnings)) {
            warnings.add(headerRes.warnings);
        }
        return headerRes.skillHeaders;
    }

    private static String loadInstructions(Wiring wiring, List<String> active, List<String> warnings) {
        List<String> names = new List<String>(wiring.always);
        names.addAll(active);
        if (names.isEmpty()) {
            return '';
        }
        Agent_Skill_LoadAndCompose_v2.LoadAndComposeRequest loadReq = new Agent_Skill_LoadAndCompose_v2.LoadAndComposeRequest();
        loadReq.instructionNames = String.join(names, ',');
        loadReq.locale = wiring.locale;
        loadReq.requireApproval = wiring.requireApproval;
        loadReq.knownActionNames = wiring.agentTools;
        Agent_Skill_LoadAndCompose_v2.LoadAndComposeResponse loadRes =
            Agent_Skill_LoadAndCompose_v2.loadAndCompose(new List<Agent_Skill_LoadAndCompose_v2.LoadAndComposeRequest>{ loadReq })[0];
        if (String.isNotBlank(loadRes.warnings)) {
            warnings.add(loadRes.warnings);
        }
        return loadRes.instructionsBundle;
    }

    private static Map<String, Boolean> referencedTools(String instructions) {
        Map<String, Boolean> tools = new Map<String, Boolean>();
        if (String.isBlank(instructions)) {
            return tools;
        }
        Matcher m = ACTION_REF.matcher(instructions);
        while (m.find()) {
            tools.put(m.group(1), true);
        }
        return tools;
    }

    private static Response toResponse(SkillState state) {
        Response res = new Response();
        res.skillState = state;
        res.activeSkills = state.active_skills;
        return res;
    }

    private static Agent_Skill_Usage__e usageEvent(Request req, SkillState state, Long durationMs) {
        return new Agent_Skill_Usage__e(
            Agent_Name__c = req == null ? null : req.agentName,
            Requested_Skills__c = req == null ? null : (req.requestedSkills == null ? null : req.requestedSkills.left(255)),
            Active_Skills__c = state.active_skills == null ? null : state.active_skills.left(255),
            Warnings__c = state.skill_warnings,
            Instruction_Chars__c = state.skill_instructions == null ? 0 : state.skill_instructions.length(),
            Duration_Ms__c = durationMs
        );
    }

    private static void publish(List<Agent_Skill_Usage__e> events) {
        try {
            EventBus.publish(events);
        } catch (Exception ex) {
            // Telemetry must never block skill loading.
            System.debug(LoggingLevel.WARN, 'Agent skill usage event not published: ' + ex.getMessage());
        }
    }

    public static Wiring loadWiring(String agentName) {
        if (String.isBlank(agentName)) {
            return null;
        }
        List<Agent_Skill_Binding__c> bindings = [
            SELECT Locale__c, Require_Approval__c, Agent_Tools__c,
                (SELECT Skill_Name__c, Mode__c FROM Items__r ORDER BY Order__c NULLS LAST, Skill_Name__c)
            FROM Agent_Skill_Binding__c
            WHERE Agent_Developer_Name__c = :agentName.trim() AND Status__c = 'Active'
            LIMIT 1
        ];
        if (bindings.isEmpty()) {
            return null;
        }
        Wiring wiring = new Wiring();
        wiring.locale = String.isBlank(bindings[0].Locale__c) ? 'en-US' : bindings[0].Locale__c;
        wiring.requireApproval = bindings[0].Require_Approval__c == true;
        wiring.agentTools = bindings[0].Agent_Tools__c == null ? null : bindings[0].Agent_Tools__c.deleteWhitespace();
        for (Agent_Skill_Binding_Item__c item : bindings[0].Items__r) {
            String name = item.Skill_Name__c.trim();
            if (item.Mode__c == 'Always') {
                wiring.always.add(name);
            } else {
                wiring.selectable.add(name);
                if (item.Mode__c == 'Default') {
                    wiring.defaults.add(name);
                }
            }
        }
        return wiring;
    }
}
