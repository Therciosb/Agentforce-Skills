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
        for (LoadAndComposeRequest req : requests) {
            responses.add(processRequest(req));
        }
        return responses;
    }

    private static LoadAndComposeResponse processRequest(LoadAndComposeRequest req) {
        LoadAndComposeResponse response = new LoadAndComposeResponse();
        response.instructionsBundle = '';
        response.loadedInstructionBundle = '';
        response.skillsLoadedCount = 0;
        response.composeRan = false;
        response.warnings = '';

        Agent_Skill_Loader.LoaderRequest loaderReq = new Agent_Skill_Loader.LoaderRequest();
        loaderReq.instructionNames = req.instructionNames != null ? req.instructionNames : '';
        loaderReq.existingInstructionBundle = req.existingInstructionBundle;
        loaderReq.includeReferences = req.includeReferences == null ? true : req.includeReferences;

        List<Agent_Skill_Loader.LoaderResponse> loaderRes = Agent_Skill_Loader.load(
            new List<Agent_Skill_Loader.LoaderRequest>{ loaderReq }
        );
        Agent_Skill_Loader.LoaderResponse loadOut = loaderRes[0];

        response.loadedInstructionBundle = loadOut.loadedInstructionBundle;
        response.skillsLoadedCount = loadOut.skillsLoadedCount != null ? loadOut.skillsLoadedCount : 0;

        List<String> warnParts = new List<String>();
        if (String.isNotBlank(loadOut.warnings)) {
            warnParts.add(loadOut.warnings);
        }

        Boolean loadSuccess = String.isNotBlank(loadOut.loadedInstructionBundle)
            && response.skillsLoadedCount > 0;

        if (loadSuccess) {
            Agent_Skill_PromptComposer.ComposerRequest composerReq = new Agent_Skill_PromptComposer.ComposerRequest();
            composerReq.instructionBundle = loadOut.loadedInstructionBundle;
            composerReq.requiredNames = req.instructionNames != null ? req.instructionNames : '';
            composerReq.maxReferenceDepth = req.maxReferenceDepth != null ? req.maxReferenceDepth : 4;
            composerReq.includeReferenceExpansion = req.includeReferenceExpansion == null
                ? true
                : req.includeReferenceExpansion;

            List<Agent_Skill_PromptComposer.ComposerResponse> composerRes =
                Agent_Skill_PromptComposer.compose(
                    new List<Agent_Skill_PromptComposer.ComposerRequest>{ composerReq }
                );
            Agent_Skill_PromptComposer.ComposerResponse composeOut = composerRes[0];

            response.instructionsBundle = composeOut.composedInstructions != null
                ? composeOut.composedInstructions
                : '';
            response.composeRan = true;

            if (String.isNotBlank(composeOut.warnings)) {
                warnParts.add(composeOut.warnings);
            }
        }

        response.warnings = String.join(warnParts, ' | ');
        return response;
    }
}
