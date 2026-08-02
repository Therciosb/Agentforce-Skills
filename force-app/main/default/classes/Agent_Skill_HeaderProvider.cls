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
