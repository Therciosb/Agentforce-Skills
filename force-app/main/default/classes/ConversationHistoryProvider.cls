public with sharing class ConversationHistoryProvider {

    public class HistoryRequest {
        @InvocableVariable(required=true)
        public String conversationId;
    }

    public class HistoryResult {
        @InvocableVariable
        public String conversationHistory;

        @InvocableVariable
        public Boolean hasContent;
    }

    @InvocableMethod(label='Get Conversation History' description='Queries ConversationEntry records for a given ConversationId and returns formatted transcript')
    public static List<HistoryResult> getConversationHistory(List<HistoryRequest> requests) {
        List<HistoryResult> results = new List<HistoryResult>();
        for (HistoryRequest req : requests) {
            results.add(buildHistory(req.conversationId));
        }
        return results;
    }

    private static HistoryResult buildHistory(String conversationId) {
        HistoryResult result = new HistoryResult();
        result.conversationHistory = '';
        result.hasContent = false;

        if (String.isBlank(conversationId)) {
            return result;
        }

        try {
            List<ConversationEntry> entries = [
                SELECT Message, ActorType, ActorName, Seq, EntryType
                FROM ConversationEntry
                WHERE ConversationId = :conversationId
                AND EntryType = 'Text'
                ORDER BY Seq ASC
                LIMIT 50
            ];

            if (entries.isEmpty()) {
                return result;
            }

            String history = '';
            for (ConversationEntry e : entries) {
                String actor = e.ActorType == 'EndUser' ? 'User' : 'Agent';
                history += actor + ': ' + e.Message + '\n';
            }

            result.conversationHistory = history;
            result.hasContent = true;
        } catch (Exception e) {
            result.conversationHistory = '';
            result.hasContent = false;
        }

        return result;
    }
}