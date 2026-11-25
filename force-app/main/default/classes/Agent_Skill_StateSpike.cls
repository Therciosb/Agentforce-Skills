public with sharing class Agent_Skill_StateSpike {
    // Spike only: the agent binding objects replace these constants.
    private static final String ALWAYS_SKILLS =
        'role-customer-support-agent,core-skill-ltmManagement-service-agent,core-skill-txt-response-guidelines';
    private static final List<String> SELECTABLE_SKILLS = new List<String>{
        'skill-product-information-qa',
        'skill-troubleshooting-support',
        'skill-support-case-management',
        'skill-order-status-support'
    };
    private static final String DEFAULT_SKILLS = 'skill-product-information-qa';

    public class SkillState {
        @AuraEnabled public String skill_menu;
        @AuraEnabled public String active_skills;
        @AuraEnabled public String skill_instructions;
        @AuraEnabled public String skill_warnings;
    }

    public class Request {
        @InvocableVariable(label='Agent Name' description='Developer name of the calling agent.')
        public String agentName;

        @InvocableVariable(label='Requested Skills' description='CSV of skill names to activate. Blank loads the defaults.')
        public String requestedSkills;
    }

    public class Response {
        @InvocableVariable(label='Skill State' description='Menu, active skills, composed instructions, and warnings.')
        public SkillState skillState;

        @InvocableVariable(label='Active Skills' description='CSV of the skills actually activated.')
        public String activeSkills;
    }

    @InvocableMethod(
        label='Agent Skill State (Spike)'
        description='Resolves requested skills against the agent wiring and returns the skill state object.'
    )
    public static List<Response> resolve(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            responses.add(resolveOne(req));
        }
        return responses;
    }

    private static Response resolveOne(Request req) {
        List<String> warnings = new List<String>();
        List<String> active = new List<String>();
        Set<String> allowed = new Set<String>(SELECTABLE_SKILLS);

        for (String token : (req == null || String.isBlank(req.requestedSkills)) ? new List<String>() : req.requestedSkills.split(',')) {
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
            active.addAll(DEFAULT_SKILLS.split(','));
        }

        SkillState state = new SkillState();
        state.active_skills = String.join(active, ',');
        state.skill_menu = loadMenu(warnings);
        state.skill_instructions = loadInstructions(state.active_skills, warnings);
        state.skill_warnings = String.join(warnings, ' | ');

        Response res = new Response();
        res.skillState = state;
        res.activeSkills = state.active_skills;
        return res;
    }

    private static String loadMenu(List<String> warnings) {
        Agent_Skill_HeaderProvider.HeaderRequest headerReq = new Agent_Skill_HeaderProvider.HeaderRequest();
        headerReq.skillNames = String.join(SELECTABLE_SKILLS, ',');
        Agent_Skill_HeaderProvider.HeaderResponse headerRes =
            Agent_Skill_HeaderProvider.getHeaders(new List<Agent_Skill_HeaderProvider.HeaderRequest>{ headerReq })[0];
        if (String.isNotBlank(headerRes.warnings)) {
            warnings.add(headerRes.warnings);
        }
        return headerRes.skillHeaders;
    }

    private static String loadInstructions(String activeSkills, List<String> warnings) {
        Agent_Skill_LoadAndCompose_v2.LoadAndComposeRequest loadReq = new Agent_Skill_LoadAndCompose_v2.LoadAndComposeRequest();
        loadReq.instructionNames = ALWAYS_SKILLS + ',' + activeSkills;
        Agent_Skill_LoadAndCompose_v2.LoadAndComposeResponse loadRes =
            Agent_Skill_LoadAndCompose_v2.loadAndCompose(new List<Agent_Skill_LoadAndCompose_v2.LoadAndComposeRequest>{ loadReq })[0];
        if (String.isNotBlank(loadRes.warnings)) {
            warnings.add(loadRes.warnings);
        }
        return loadRes.instructionsBundle;
    }
}
