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
        // Keys MUST use the template's input reference-name prefix ("Input:<apiName>").
        // Bare apiName keys ("skillType") fail with INVALID_INPUT: "Required input is
        // missing for parameter Input:skillType." (verified against myDevOrg).
        Map<String, ConnectApi.WrappedValue> params = new Map<String, ConnectApi.WrappedValue>();
        params.put('Input:intent', wrap(intent));
        params.put('Input:skillType', wrap(skillType));
        params.put('Input:referenceText', wrap(String.isBlank(referenceText) ? '' : referenceText));
        input.inputParams = params;
        input.isPreview = false;
        // Required: the backend uses applicationName to resolve the generation context.
        // Without it, generateMessagesForPromptTemplate fails with the opaque
        // "Failed to generate Einstein LLM generations response" for ALL templates
        // (verified against myDevOrg; matches the working Agentforce-SelfImproving pattern).
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
        // extract the first {...} block to tolerate stray prose around the JSON
        Integer startIdx = raw.indexOf('{');
        Integer endIdx = raw.lastIndexOf('}');
        if (startIdx < 0 || endIdx <= startIdx) {
            return null;
        }
        String jsonBlock = raw.substring(startIdx, endIdx + 1);
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
