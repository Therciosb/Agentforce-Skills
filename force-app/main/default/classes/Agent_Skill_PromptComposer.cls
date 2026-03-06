public with sharing class Agent_Skill_PromptComposer {
    private static final String LINE_SEPARATOR = '#############################################';

    public class ComposerRequest {
        @InvocableVariable(
            required=true
            label='Instruction Bundle JSON'
            description='Loaded instruction bundle JSON from Agent_Skill_Loader.'
        )
        public String instructionBundle;

        @InvocableVariable(
            label='Required Names CSV'
            description='CSV of skill/workflow seed names to include in composed output.'
        )
        public String requiredNames;

        @InvocableVariable(
            label='Include Reference Expansion (optional, default true)'
            description='Whether to recursively expand references.'
        )
        public Boolean includeReferenceExpansion;

        @InvocableVariable(
            label='Max Reference Depth (optional, default 4)'
            description='Maximum depth for reference expansion.'
        )
        public Integer maxReferenceDepth;

        @InvocableVariable(
            label='Include Deprecated (optional, default false)'
            description='Whether to include deprecated instructions.'
        )
        public Boolean includeDeprecated;
    }

    public class ComposerResponse {
        @InvocableVariable(
            label='Composed Instructions'
            description='Prompt-ready concatenated instruction text.'
        )
        public String composedInstructions;

        @InvocableVariable(
            label='Resolved Names'
            description='CSV of instruction names that were resolved and included.'
        )
        public String resolvedNames;

        @InvocableVariable(
            label='Missing Names'
            description='CSV of requested names that were not found in the bundle.'
        )
        public String missingNames;

        @InvocableVariable(
            label='Warnings'
            description='Warning messages if any requested instructions were missing.'
        )
        public String warnings;
    }

    private class BundleEntry {
        String name;
        String status;
        String instructions;
        String references;
    }

    @InvocableMethod(
        label='Agent Skill Prompt Composer'
        description='Builds final prompt instructions from loaded instruction bundle and skill/workflow dependencies.'
    )
    public static List<ComposerResponse> compose(List<ComposerRequest> requests) {
        List<ComposerResponse> responses = new List<ComposerResponse>();
        for (ComposerRequest requestItem : requests) {
            responses.add(processRequest(requestItem));
        }
        return responses;
    }

    private static ComposerResponse processRequest(ComposerRequest requestItem) {
        ComposerResponse response = new ComposerResponse();
        Map<String, BundleEntry> entriesByName = parseBundle(requestItem.instructionBundle);
        Set<String> required = parseCsv(requestItem.requiredNames);
        Boolean includeDeprecated = requestItem.includeDeprecated == true;
        Boolean expandRefs = requestItem.includeReferenceExpansion == null ? true : requestItem.includeReferenceExpansion;
        Integer maxDepth = requestItem.maxReferenceDepth == null ? 4 : requestItem.maxReferenceDepth;

        // Always include global role/core instructions present in the bundle.
        Set<String> includeNames = new Set<String>();
        for (String keyName : entriesByName.keySet()) {
            if (keyName.startsWith('role-') || keyName.startsWith('core-skill-')) {
                includeNames.add(keyName);
            }
        }

        includeNames.addAll(required);

        if (expandRefs && !required.isEmpty()) {
            expandDependencies(required, includeNames, includeDeprecated, maxDepth, entriesByName);
        }

        List<String> missing = new List<String>();
        List<String> warnings = new List<String>();
        List<String> ordered = new List<String>();
        for (String candidate : includeNames) {
            BundleEntry entry = entriesByName.get(candidate);
            if (entry == null) {
                missing.add(candidate);
                continue;
            }
            if (!includeDeprecated && entry.status == 'deprecated') {
                warnings.add('Skipping deprecated instruction: ' + candidate);
                continue;
            }
            ordered.add(candidate);
        }
        ordered.sort();
        ordered.sort(new PrefixOrderComparator());

        List<String> blocks = new List<String>();
        for (String name : ordered) {
            BundleEntry entry = entriesByName.get(name);
            if (entry != null && !String.isBlank(entry.instructions)) {
                String block = '[Instruction: ' + name + ']\n' + entry.instructions.trim();
                blocks.add(block);
            }
        }

        String separatorBlock = '\n\n\n' + LINE_SEPARATOR + '\n\n';
        response.composedInstructions = String.join(blocks, separatorBlock);

        missing.sort();
        warnings.sort();
        response.resolvedNames = String.join(ordered, ',');
        response.missingNames = String.join(missing, ',');
        response.warnings = String.join(warnings, ' | ');
        return response;
    }

    private static void expandDependencies(
        Set<String> seeds,
        Set<String> includeNames,
        Boolean includeDeprecated,
        Integer maxDepth,
        Map<String, BundleEntry> entriesByName
    ) {
        Integer depth = 0;
        Set<String> frontier = new Set<String>();
        frontier.addAll(seeds);
        Set<String> visited = new Set<String>();
        visited.addAll(seeds);

        while (!frontier.isEmpty() && depth < maxDepth) {
            Set<String> nextFrontier = new Set<String>();
            for (String sourceName : frontier) {
                BundleEntry entry = entriesByName.get(sourceName);
                if (entry == null || String.isBlank(entry.references)) {
                    continue;
                }
                for (String target : parseCsv(entry.references)) {
                    if (String.isBlank(target) || visited.contains(target)) {
                        continue;
                    }
                    if (!isLoadableInstruction(target)) {
                        continue;
                    }
                    visited.add(target);
                    includeNames.add(target);
                    nextFrontier.add(target);

                    if (!entriesByName.containsKey(target)) {
                        BundleEntry fetched = fetchActiveEntry(target, includeDeprecated);
                        if (fetched != null) {
                            entriesByName.put(target, fetched);
                        }
                    }
                }
            }
            frontier = nextFrontier;
            depth++;
        }
    }

    private static Boolean isLoadableInstruction(String name) {
        return name != null && (
            name.startsWith('role-') || name.startsWith('skill-') || name.startsWith('workflow-') ||
            name.startsWith('core-skill-')
        );
    }

    private static BundleEntry fetchActiveEntry(String name, Boolean includeDeprecated) {
        for (Agent_Skills_Repo__c rec : [
            SELECT Name, Status__c, InstructionBody__c, References__c
            FROM Agent_Skills_Repo__c
            WHERE Name = :name
            LIMIT 1
        ]) {
            if (rec.Status__c == 'active' || includeDeprecated) {
                return toEntry(rec.Name, rec.Status__c, rec.InstructionBody__c, rec.References__c);
            }
        }
        return null;
    }

    private static Map<String, BundleEntry> parseBundle(String jsonBundle) {
        Map<String, BundleEntry> outMap = new Map<String, BundleEntry>();
        if (String.isBlank(jsonBundle)) {
            return outMap;
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonBundle);
        if (!parsed.containsKey('bundles')) {
            return outMap;
        }

        List<Object> bundles = (List<Object>) parsed.get('bundles');
        for (Object bundleObj : bundles) {
            Map<String, Object> itemMap = (Map<String, Object>) bundleObj;
            Map<String, Object> metadata = (Map<String, Object>) itemMap.get('metadata');
            if (metadata == null || !metadata.containsKey('name')) {
                continue;
            }
            String name = (String) metadata.get('name');
            String status = (String) metadata.get('status');
            String instructions = (String) itemMap.get('instructions');
            String references = metadata.get('references') != null ? String.valueOf(metadata.get('references')) : null;
            outMap.put(name, toEntry(name, status, instructions, references));
        }
        return outMap;
    }

    private static BundleEntry toEntry(String name, String status, String instructions, String references) {
        BundleEntry entry = new BundleEntry();
        entry.name = name;
        entry.status = status;
        entry.instructions = instructions;
        entry.references = references;
        return entry;
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

    private class PrefixOrderComparator implements Comparator<String> {
        public Integer compare(String leftValue, String rightValue) {
            Integer leftRank = rank(leftValue);
            Integer rightRank = rank(rightValue);
            if (leftRank != rightRank) {
                return leftRank < rightRank ? -1 : 1;
            }
            return leftValue.toLowerCase().compareTo(rightValue.toLowerCase());
        }

        private Integer rank(String nameValue) {
            if (nameValue == null) {
                return 99;
            }
            if (nameValue.startsWith('role-')) {
                return 1;
            }
            if (nameValue.startsWith('core-skill-')) {
                return 2;
            }
            if (nameValue.startsWith('skill-')) {
                return 3;
            }
            if (nameValue.startsWith('workflow-')) {
                return 4;
            }
            return 10;
        }
    }
}
