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

    public class SkillRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String type;
        @AuraEnabled public String status;
        @AuraEnabled public String whenToUse;
        @AuraEnabled public Decimal priority;
        @AuraEnabled public Datetime lastModified;
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

    @AuraEnabled(cacheable=true)
    public static List<SkillRow> listSkills(String searchTerm, String typeFilter) {
        String filters = 'WHERE Name != null';
        Map<String, Object> binds = new Map<String, Object>();

        if (String.isNotBlank(typeFilter) && typeFilter != 'All') {
            filters += ' AND Type__c = :typeFilter';
            binds.put('typeFilter', typeFilter);
        }
        if (String.isNotBlank(searchTerm)) {
            // WhenToUse__c / Description__c are LongTextArea and cannot be filtered
            // in SOQL; search the (filterable) Name field only.
            binds.put('term', '%' + searchTerm.trim() + '%');
            filters += ' AND Name LIKE :term';
        }

        String soql =
            'SELECT Id, Name, Type__c, Status__c, WhenToUse__c, Priority__c, LastModifiedDate ' +
            'FROM Agent_Skills_Repo__c ' + filters + ' ' +
            'ORDER BY Type__c, Name LIMIT 200';

        List<SkillRow> rows = new List<SkillRow>();
        List<Agent_Skills_Repo__c> records = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
        for (Agent_Skills_Repo__c rec : records) {
            SkillRow row = new SkillRow();
            row.recordId = rec.Id;
            row.name = rec.Name;
            row.type = rec.Type__c;
            row.status = rec.Status__c;
            row.whenToUse = rec.WhenToUse__c;
            row.priority = rec.Priority__c;
            row.lastModified = rec.LastModifiedDate;
            rows.add(row);
        }
        return rows;
    }
}
