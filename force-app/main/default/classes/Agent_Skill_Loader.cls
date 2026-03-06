public with sharing class Agent_Skill_Loader {
    public class LoaderRequest {
        @InvocableVariable(
            required=true
            label='Instruction Names CSV'
            description='CSV list of role/skill/workflow names to load.'
        )
        public String instructionNames;

        @InvocableVariable(
            label='Include References (optional, default true)'
            description='Whether to expand and include referenced instructions.'
        )
        public Boolean includeReferences;

        @InvocableVariable(
            label='Version (optional, uses latest if omitted)'
            description='Version filter; uses latest if omitted.'
        )
        public String version;

        @InvocableVariable(
            label='Locale (optional, default en-US)'
            description='Locale for instruction resolution (e.g. en-US).'
        )
        public String locale;

        @InvocableVariable(
            label='Existing Instruction Bundle JSON'
            description='Existing bundle JSON to merge with newly loaded instructions.'
        )
        public String existingInstructionBundle;
    }

    public class LoaderResponse {
        @InvocableVariable(
            label='Loaded Instruction Bundle'
            description='Aggregated instruction bundle JSON.'
        )
        public String loadedInstructionBundle;

        @InvocableVariable(
            label='Skills Loaded Count'
            description='Number of instruction bundles loaded.'
        )
        public Integer skillsLoadedCount;

        @InvocableVariable(
            label='Timestamp'
            description='ISO-8601 UTC timestamp of the load.'
        )
        public String timestamp;

        @InvocableVariable(
            label='Missing Names'
            description='CSV of requested names that were not found or inactive.'
        )
        public String missingNames;

        @InvocableVariable(
            label='Warnings'
            description='Warning messages if any requested instructions were missing.'
        )
        public String warnings;
    }

    private class InstructionMetadata {
        public String version;
        public String name;
        public String status;
        public String references;
    }

    private class InstructionBundleItem {
        public InstructionMetadata metadata;
        public String instructions;
    }

    private class LoadedInstructionBundle {
        public Integer skillsLoadedCount;
        public String timestamp;
        public List<InstructionBundleItem> bundles = new List<InstructionBundleItem>();
    }

    @InvocableMethod(
        label='Agent Skill Loader'
        description='Loads role/skill/workflow instruction bundle filtered to active records.'
    )
    public static List<LoaderResponse> load(List<LoaderRequest> requests) {
        List<LoaderResponse> responses = new List<LoaderResponse>();
        for (LoaderRequest requestItem : requests) {
            responses.add(processRequest(requestItem));
        }
        return responses;
    }

    private static LoaderResponse processRequest(LoaderRequest requestItem) {
        LoaderResponse response = new LoaderResponse();
        Map<String, InstructionBundleItem> loadedByName = new Map<String, InstructionBundleItem>();

        String existing = requestItem.existingInstructionBundle != null ? requestItem.existingInstructionBundle : '';
        loadedByName.putAll(parseExistingBundle(existing));

        Set<String> seedNames = parseCsv(requestItem.instructionNames);
        Set<String> allNames = new Set<String>();
        allNames.addAll(seedNames);

        Boolean includeRefs = requestItem.includeReferences == null || requestItem.includeReferences;
        String effectiveVersion = String.isBlank(requestItem.version) ? null : requestItem.version;
        String effectiveLocale = String.isBlank(requestItem.locale) ? 'en-US' : requestItem.locale;

        if (includeRefs) {
            expandReferencesFromLoaded(seedNames, allNames, effectiveVersion, effectiveLocale);
        }

        // Topic-scoped pruning: when merging with existing bundle, remove topic-specific
        // (skill-*, workflow-*) items that are not in the current InstructionNames list.
        // Always keep role-* and core-skill-*.
        if (!loadedByName.isEmpty() && !allNames.isEmpty()) {
            List<String> keysToRemove = new List<String>();
            for (String name : loadedByName.keySet()) {
                if (isTopicSpecific(name) && !allNames.contains(name)) {
                    keysToRemove.add(name);
                }
            }
            for (String name : keysToRemove) {
                loadedByName.remove(name);
            }
        }

        loadedByName.putAll(loadFromRepo(allNames, effectiveVersion, effectiveLocale));

        List<String> sortedNames = new List<String>(loadedByName.keySet());
        sortedNames.sort();

        LoadedInstructionBundle bundle = new LoadedInstructionBundle();
        bundle.timestamp = Datetime.now().formatGMT('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        for (String name : sortedNames) {
            bundle.bundles.add(loadedByName.get(name));
        }
        bundle.skillsLoadedCount = bundle.bundles.size();

        Set<String> missing = new Set<String>();
        for (String candidate : allNames) {
            if (!loadedByName.containsKey(candidate)) {
                missing.add(candidate);
            }
        }
        List<String> missingList = new List<String>(missing);
        missingList.sort();

        response.loadedInstructionBundle = JSON.serialize(bundle);
        response.skillsLoadedCount = bundle.skillsLoadedCount;
        response.timestamp = bundle.timestamp;
        response.missingNames = String.join(missingList, ',');
        response.warnings = missingList.isEmpty() ? '' : 'Some requested or referenced instructions were not active or not found.';
        return response;
    }

    private static Map<String, InstructionBundleItem> loadFromRepo(Set<String> names, String version, String locale) {
        Map<String, InstructionBundleItem> outMap = new Map<String, InstructionBundleItem>();
        if (names.isEmpty()) {
            return outMap;
        }
        for (Agent_Skills_Repo__c rec : [
            SELECT Name, Version__c, Status__c, InstructionBody__c, Locale__c, References__c
            FROM Agent_Skills_Repo__c
            WHERE Name IN :names
            AND Status__c = 'active'
            ORDER BY Version__c DESC
        ]) {
            if (!matchesContext(rec.Version__c, rec.Locale__c, version, locale)) {
                continue;
            }
            if (!outMap.containsKey(rec.Name)) {
                outMap.put(rec.Name, toBundleItem(rec.Name, rec.Version__c, rec.Status__c, rec.InstructionBody__c, rec.References__c));
            }
        }
        return outMap;
    }

    private static InstructionBundleItem toBundleItem(String name, String version, String status, String instructions, String references) {
        InstructionMetadata meta = new InstructionMetadata();
        meta.name = name;
        meta.version = version;
        meta.status = status;
        meta.references = references;

        InstructionBundleItem item = new InstructionBundleItem();
        item.metadata = meta;
        item.instructions = instructions;
        return item;
    }

    private static void expandReferencesFromLoaded(
        Set<String> seedNames,
        Set<String> allNames,
        String version,
        String locale
    ) {
        Set<String> frontier = new Set<String>();
        frontier.addAll(seedNames);
        Integer depth = 0;
        while (!frontier.isEmpty() && depth < 6) {
            Set<String> nextFrontier = new Set<String>();
            Set<String> refs = collectReferencesFromNames(frontier, version, locale);
            for (String refName : refs) {
                String trimmed = refName == null ? null : refName.trim();
                if (!String.isBlank(trimmed) && !allNames.contains(trimmed)) {
                    allNames.add(trimmed);
                    nextFrontier.add(trimmed);
                }
            }
            frontier = nextFrontier;
            depth++;
        }
    }

    private static Set<String> collectReferencesFromNames(
        Set<String> names,
        String version,
        String locale
    ) {
        Set<String> refs = new Set<String>();
        for (Agent_Skills_Repo__c rec : [
            SELECT References__c, Version__c, Locale__c FROM Agent_Skills_Repo__c
            WHERE Name IN :names AND Status__c = 'active'
        ]) {
            if (matchesContext(rec.Version__c, rec.Locale__c, version, locale)) {
                refs.addAll(parseCsv(rec.References__c));
            }
        }
        return refs;
    }

    private static Map<String, InstructionBundleItem> parseExistingBundle(String jsonBundle) {
        Map<String, InstructionBundleItem> outMap = new Map<String, InstructionBundleItem>();
        if (String.isBlank(jsonBundle)) {
            return outMap;
        }
        try {
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
                String version = metadata.get('version') != null ? String.valueOf(metadata.get('version')) : null;
                String status = (String) metadata.get('status');
                String instructions = (String) itemMap.get('instructions');
                String references = metadata.get('references') != null ? String.valueOf(metadata.get('references')) : null;
                outMap.put(name, toBundleItem(name, version, status, instructions, references));
            }
        } catch (Exception e) {
            // Return empty on parse error
        }
        return outMap;
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

    private static Boolean matchesContext(String recordVersion, String recordLocale, String requestedVersion, String requestedLocale) {
        Boolean versionMatches = String.isBlank(requestedVersion) || recordVersion == requestedVersion;
        Boolean localeMatches = String.isBlank(requestedLocale) || recordLocale == requestedLocale;
        return versionMatches && localeMatches;
    }

    private static Boolean isTopicSpecific(String name) {
        return name != null && (
            name.startsWith('skill-') || name.startsWith('workflow-')
        );
    }
}
