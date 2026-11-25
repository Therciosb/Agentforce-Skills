public with sharing class Agent_Skill_LoadAndCompose {

    public class LoadAndComposeRequest {
        @InvocableVariable(
            required=false
            label='Instruction Names CSV'
            description='CSV list of role/skill/workflow names to load. Optional when existingInstructionBundle is provided (merge-only scenario).'
        )
        public String instructionNames;

        @InvocableVariable(
            label='Existing Instruction Bundle JSON'
            description='Existing bundle JSON to merge with newly loaded instructions (optional).'
        )
        public String existingInstructionBundle;

        @InvocableVariable(
            label='Locale (optional, default en-US)'
            description='Locale used to resolve instruction records.'
        )
        public String locale;

        @InvocableVariable(
            label='Require Approval (optional, default false)'
            description='When true, only Approved instruction records load.'
        )
        public Boolean requireApproval;

        @InvocableVariable(
            label='Known Action Names CSV (optional)'
            description='Agent Script action names the agent exposes; validates [[tool:Name]] indicators.'
        )
        public String knownActionNames;

        @InvocableVariable(
            label='Max Reference Depth (optional, default 4)'
            description='Maximum depth for reference expansion in composer.'
        )
        public Integer maxReferenceDepth;

        @InvocableVariable(
            label='Include References (optional, default true)'
            description='Whether loader expands and includes referenced instructions.'
        )
        public Boolean includeReferences;

        @InvocableVariable(
            label='Include Reference Expansion (optional, default true)'
            description='Whether composer recursively expands references.'
        )
        public Boolean includeReferenceExpansion;
    }

    public class LoadAndComposeResponse {
        @InvocableVariable(
            label='Instructions Bundle'
            description='Formatted prompt-ready instruction text from composer (when load succeeds).'
        )
        public String instructionsBundle;

        @InvocableVariable(
            label='Loaded Instruction Bundle'
            description='Raw instruction bundle JSON from loader (for merge scenarios).'
        )
        public String loadedInstructionBundle;

        @InvocableVariable(
            label='Skills Loaded Count'
            description='Number of instruction bundles loaded.'
        )
        public Integer skillsLoadedCount;

        @InvocableVariable(
            label='Compose Ran'
            description='Whether composer was invoked (load succeeded with non-empty bundle).'
        )
        public Boolean composeRan;

        @InvocableVariable(
            label='Warnings'
            description='Combined warning messages from loader and composer.'
        )
        public String warnings;
    }

    @InvocableMethod(
        label='Agent Skill Load And Compose'
        description='Loads role/skill/workflow instructions, then composes prompt-ready text. Aggregates Loader and Composer.'
    )
    public static List<LoadAndComposeResponse> loadAndCompose(List<LoadAndComposeRequest> requests) {
        List<LoadAndComposeResponse> responses = new List<LoadAndComposeResponse>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }

        // Prepare bulk loader requests
        List<Agent_Skill_Loader.LoaderRequest> loaderReqs = new List<Agent_Skill_Loader.LoaderRequest>();
        for (LoadAndComposeRequest req : requests) {
            Agent_Skill_Loader.LoaderRequest loaderReq = new Agent_Skill_Loader.LoaderRequest();
            loaderReq.instructionNames = sanitizeNames(req != null ? req.instructionNames : null);
            loaderReq.existingInstructionBundle = req != null ? req.existingInstructionBundle : null;
            loaderReq.locale = req != null ? req.locale : null;
            loaderReq.requireApproval = req != null && req.requireApproval == true;
            loaderReq.includeReferences = (req != null && req.includeReferences != null) ? req.includeReferences : true;
            loaderReqs.add(loaderReq);
        }

        List<Agent_Skill_Loader.LoaderResponse> loaderResponses;
        try {
            loaderResponses = Agent_Skill_Loader.load(loaderReqs);
        } catch (Exception ex) {
            for (LoadAndComposeRequest req : requests) {
                LoadAndComposeResponse errRes = new LoadAndComposeResponse();
                errRes.instructionsBundle = '';
                errRes.loadedInstructionBundle = '';
                errRes.skillsLoadedCount = 0;
                errRes.composeRan = false;
                errRes.warnings = 'Loader execution error: ' + ex.getMessage();
                responses.add(errRes);
            }
            return responses;
        }

        // Process loader responses and compose in bulk
        for (Integer i = 0; i < requests.size(); i++) {
            LoadAndComposeRequest req = requests[i];
            Agent_Skill_Loader.LoaderResponse loadOut = (loaderResponses != null && loaderResponses.size() > i)
                ? loaderResponses[i]
                : null;

            LoadAndComposeResponse resp = new LoadAndComposeResponse();
            resp.instructionsBundle = '';
            resp.loadedInstructionBundle = (loadOut != null && loadOut.loadedInstructionBundle != null) ? loadOut.loadedInstructionBundle : '';
            resp.skillsLoadedCount = (loadOut != null && loadOut.skillsLoadedCount != null) ? loadOut.skillsLoadedCount : 0;
            resp.composeRan = false;

            List<String> warnParts = new List<String>();
            if (loadOut != null && String.isNotBlank(loadOut.warnings)) {
                warnParts.add(loadOut.warnings);
            }

            Boolean loadSuccess = String.isNotBlank(resp.loadedInstructionBundle) && resp.skillsLoadedCount > 0;
            if (loadSuccess) {
                try {
                    Agent_Skill_PromptComposer.ComposerRequest composerReq = new Agent_Skill_PromptComposer.ComposerRequest();
                    composerReq.instructionBundle = resp.loadedInstructionBundle;
                    composerReq.requiredNames = sanitizeNames(req != null ? req.instructionNames : null);
                    composerReq.maxReferenceDepth = (req != null && req.maxReferenceDepth != null) ? req.maxReferenceDepth : 4;
                    composerReq.includeReferenceExpansion = (req != null && req.includeReferenceExpansion != null) ? req.includeReferenceExpansion : true;
                    composerReq.locale = req != null ? req.locale : null;
                    composerReq.requireApproval = req != null && req.requireApproval == true;
                    composerReq.knownActionNames = req != null ? req.knownActionNames : null;

                    List<Agent_Skill_PromptComposer.ComposerResponse> composerResponses =
                        Agent_Skill_PromptComposer.compose(new List<Agent_Skill_PromptComposer.ComposerRequest>{ composerReq });
                    
                    if (composerResponses != null && !composerResponses.isEmpty()) {
                        Agent_Skill_PromptComposer.ComposerResponse composeOut = composerResponses[0];
                        resp.instructionsBundle = composeOut.composedInstructions != null ? composeOut.composedInstructions : '';
                        resp.composeRan = true;
                        if (String.isNotBlank(composeOut.warnings)) {
                            warnParts.add(composeOut.warnings);
                        }
                    }
                } catch (Exception ex) {
                    warnParts.add('Composer error: ' + ex.getMessage());
                }
            } else if (String.isBlank(resp.loadedInstructionBundle) && req != null && String.isNotBlank(req.instructionNames)) {
                warnParts.add('No instruction bundles resolved for requested names.');
            }

            resp.warnings = String.join(warnParts, ' | ');
            responses.add(resp);
        }

        return responses;
    }

    private static String sanitizeNames(String rawNames) {
        if (String.isBlank(rawNames)) {
            return '';
        }
        List<String> cleanedTokens = new List<String>();
        for (String token : rawNames.split(',')) {
            String trimmed = token.trim();
            if (String.isNotBlank(trimmed)) {
                cleanedTokens.add(trimmed);
            }
        }
        return String.join(cleanedTokens, ',');
    }
}