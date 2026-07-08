/**
 * Classifies a subagent's domain outcome event into the framework's outcome
 * CLASS (success / failure / partial) using the per-subagent configuration in
 * AgentSubagentConfig__c.outcome_mapping_json__c — instead of hardcoding event
 * names in the agent script.
 *
 * This lets the self-learning framework work for ANY subagent: each subagent
 * declares, in the SIA console, which domain events map to success vs. failure.
 * The agent script then branches only on the neutral class, never on a literal
 * event name like "resolved".
 *
 * outcome_mapping_json__c shape (JSON array):
 *   [{"domain_event":"resolved","maps_to":"success"},
 *    {"domain_event":"unresolved","maps_to":"failure"}]
 *
 * significant_outcome_triggers__c shape (semicolon list), e.g. "failure;below_optimal".
 */
public with sharing class ClassifyAgentOutcome {

    public class Request {
        @InvocableVariable(required=true)
        public String agent_api_name;

        @InvocableVariable(required=true)
        public String topic_area;

        // The domain event the subagent recorded this turn (e.g. "resolved").
        @InvocableVariable(required=true)
        public String domain_event;
    }

    public class Result {
        // Neutral class the agent script branches on: success / failure / partial / unknown / '' (none).
        @InvocableVariable
        public String outcome_class;

        // True when the resolved class is listed in significant_outcome_triggers__c.
        @InvocableVariable
        public Boolean is_significant;
    }

    @InvocableMethod(label='Classify Agent Outcome' description='Maps a subagent domain event to success/failure/partial using AgentSubagentConfig outcome_mapping_json')
    public static List<Result> classify(List<Request> requests) {
        List<Result> out = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return out;
        }

        // Collect keys for a single bulk query (one row per agent+topic).
        Set<String> agentNames = new Set<String>();
        Set<String> topics = new Set<String>();
        for (Request req : requests) {
            if (req.agent_api_name != null) agentNames.add(req.agent_api_name);
            if (req.topic_area != null) topics.add(req.topic_area);
        }

        Map<String, AgentSubagentConfig__c> cfgByKey = new Map<String, AgentSubagentConfig__c>();
        for (AgentSubagentConfig__c c : [
            SELECT agent_api_name__c, topic_area__c,
                   outcome_mapping_json__c, significant_outcome_triggers__c
            FROM AgentSubagentConfig__c
            WHERE agent_api_name__c IN :agentNames
              AND topic_area__c IN :topics
            WITH USER_MODE
        ]) {
            cfgByKey.put(buildKey(c.agent_api_name__c, c.topic_area__c), c);
        }

        for (Request req : requests) {
            out.add(classifyOne(req, cfgByKey.get(buildKey(req.agent_api_name, req.topic_area))));
        }
        return out;
    }

    private static String buildKey(String agent, String topic) {
        return (agent == null ? '' : agent) + '|' + (topic == null ? '' : topic);
    }

    private static Result classifyOne(Request req, AgentSubagentConfig__c cfg) {
        Result res = new Result();
        res.outcome_class = 'unknown';
        res.is_significant = false;

        String event = req.domain_event == null ? '' : req.domain_event.trim();
        if (String.isBlank(event)) {
            // No event recorded yet — neutral, not a failure.
            res.outcome_class = '';
            return res;
        }

        // Map the event -> class via the configured mapping (case-insensitive).
        if (cfg != null && String.isNotBlank(cfg.outcome_mapping_json__c)) {
            try {
                Object parsed = JSON.deserializeUntyped(cfg.outcome_mapping_json__c);
                if (parsed instanceof List<Object>) {
                    for (Object o : (List<Object>) parsed) {
                        if (!(o instanceof Map<String, Object>)) continue;
                        Map<String, Object> m = (Map<String, Object>) o;
                        Object deObj = m.get('domain_event');
                        Object mtObj = m.get('maps_to');
                        String de = deObj == null ? null : String.valueOf(deObj);
                        String mt = mtObj == null ? null : String.valueOf(mtObj);
                        if (de != null && de.equalsIgnoreCase(event) && String.isNotBlank(mt)) {
                            res.outcome_class = mt.toLowerCase();
                            break;
                        }
                    }
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                    'ClassifyAgentOutcome|bad outcome_mapping_json for ' + req.agent_api_name
                    + '/' + req.topic_area + ': ' + e.getMessage());
            }
        }

        // is_significant: is the resolved class listed among significant triggers?
        if (cfg != null && String.isNotBlank(cfg.significant_outcome_triggers__c)
                && res.outcome_class != 'unknown' && String.isNotBlank(res.outcome_class)) {
            for (String trig : cfg.significant_outcome_triggers__c.split(';')) {
                if (trig != null && trig.trim().equalsIgnoreCase(res.outcome_class)) {
                    res.is_significant = true;
                    break;
                }
            }
        }

        return res;
    }
}