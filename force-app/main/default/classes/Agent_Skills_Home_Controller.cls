public with sharing class Agent_Skills_Home_Controller {
    public class TypeStat {
        @AuraEnabled public String type;
        @AuraEnabled public String label;
        @AuraEnabled public Integer total;
        @AuraEnabled public Integer active;
    }

    public class RecentSkill {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String type;
        @AuraEnabled public String status;
        @AuraEnabled public String whenToUse;
        @AuraEnabled public Datetime lastModified;
    }

    public class HomeSummary {
        @AuraEnabled public Integer total;
        @AuraEnabled public Integer activeTotal;
        @AuraEnabled public Integer draftTotal;
        @AuraEnabled public List<TypeStat> byType;
        @AuraEnabled public List<RecentSkill> recent;
    }

    private static final Map<String, String> TYPE_LABELS = new Map<String, String>{
        'Role' => 'Roles',
        'Core_Skill' => 'Core skills',
        'Skill' => 'Skills',
        'Workflow' => 'Workflows'
    };

    @AuraEnabled(cacheable=true)
    public static HomeSummary getSummary() {
        HomeSummary summary = new HomeSummary();
        summary.byType = new List<TypeStat>();
        summary.recent = new List<RecentSkill>();

        Map<String, TypeStat> statsByType = new Map<String, TypeStat>();
        for (String t : TYPE_LABELS.keySet()) {
            TypeStat s = new TypeStat();
            s.type = t;
            s.label = TYPE_LABELS.get(t);
            s.total = 0;
            s.active = 0;
            statsByType.put(t, s);
        }

        Integer total = 0;
        Integer activeTotal = 0;
        Integer draftTotal = 0;
        for (AggregateResult ar : [
            SELECT Type__c type, Status__c status, COUNT(Id) cnt
            FROM Agent_Skills_Repo__c
            GROUP BY Type__c, Status__c
        ]) {
            String t = (String) ar.get('type');
            String st = (String) ar.get('status');
            Integer c = (Integer) ar.get('cnt');
            total += c;
            if (st == 'active') {
                activeTotal += c;
            }
            if (st == 'Draft') {
                draftTotal += c;
            }
            TypeStat s = statsByType.get(t);
            if (s != null) {
                s.total += c;
                if (st == 'active') {
                    s.active += c;
                }
            }
        }

        summary.total = total;
        summary.activeTotal = activeTotal;
        summary.draftTotal = draftTotal;
        // Preserve taxonomy order: Role -> Core_Skill -> Skill -> Workflow.
        for (String t : new List<String>{ 'Role', 'Core_Skill', 'Skill', 'Workflow' }) {
            summary.byType.add(statsByType.get(t));
        }

        for (Agent_Skills_Repo__c rec : [
            SELECT Id, Name, Type__c, Status__c, WhenToUse__c, LastModifiedDate
            FROM Agent_Skills_Repo__c
            ORDER BY LastModifiedDate DESC
            LIMIT 6
        ]) {
            RecentSkill r = new RecentSkill();
            r.recordId = rec.Id;
            r.name = rec.Name;
            r.type = rec.Type__c;
            r.status = rec.Status__c;
            r.whenToUse = rec.WhenToUse__c;
            r.lastModified = rec.LastModifiedDate;
            summary.recent.add(r);
        }

        return summary;
    }
}
