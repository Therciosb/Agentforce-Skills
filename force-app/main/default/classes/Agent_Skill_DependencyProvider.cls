public with sharing class Agent_Skill_DependencyProvider {
    private static final Integer MAX_DEPTH = 6;

    public class TreeNode {
        @AuraEnabled public String name;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean seen;
        @AuraEnabled public List<TreeNode> children;
        public TreeNode(String name, String label, String type, String status) {
            this.name = name;
            this.label = label;
            this.type = type;
            this.status = status;
            this.seen = false;
            this.children = new List<TreeNode>();
        }
    }

    @AuraEnabled(cacheable=true)
    public static TreeNode getTree(Id recordId) {
        Agent_Skills_Repo__c root = [
            SELECT Name, Type__c, Status__c, References__c
            FROM Agent_Skills_Repo__c WHERE Id = :recordId LIMIT 1
        ];
        Map<String, Agent_Skills_Repo__c> activeByName = loadActive();
        TreeNode rootNode = new TreeNode(root.Name, root.Name, root.Type__c, root.Status__c);
        Set<String> visited = new Set<String>{ root.Name };
        expand(rootNode, root.References__c, activeByName, visited, 1);
        return rootNode;
    }

    private static void expand(
        TreeNode parent, String referencesCsv,
        Map<String, Agent_Skills_Repo__c> activeByName, Set<String> visited, Integer depth
    ) {
        if (String.isBlank(referencesCsv) || depth > MAX_DEPTH) {
            return;
        }
        for (String token : referencesCsv.split(',')) {
            String refName = token == null ? null : token.trim();
            if (String.isBlank(refName)) {
                continue;
            }
            Agent_Skills_Repo__c rec = activeByName.get(refName);
            TreeNode child;
            if (rec == null) {
                // referenced name that is not active/not found — show as-is, do not expand
                child = new TreeNode(refName, refName, 'Unknown', 'missing');
            } else {
                child = new TreeNode(rec.Name, rec.Name, rec.Type__c, rec.Status__c);
                if (visited.contains(refName)) {
                    child.seen = true; // cycle/duplicate guard — do not re-expand
                } else {
                    visited.add(refName);
                    expand(child, rec.References__c, activeByName, visited, depth + 1);
                }
            }
            parent.children.add(child);
        }
    }

    private static Map<String, Agent_Skills_Repo__c> loadActive() {
        Map<String, Agent_Skills_Repo__c> byName = new Map<String, Agent_Skills_Repo__c>();
        for (Agent_Skills_Repo__c r : [
            SELECT Name, Type__c, Status__c, References__c
            FROM Agent_Skills_Repo__c WHERE Status__c = 'active'
        ]) {
            byName.put(r.Name, r);
        }
        return byName;
    }

    public class RefOption {
        @AuraEnabled public String name;
        @AuraEnabled public String type;
    }

    // Catalog of active records (excluding the record itself) that can be selected as references.
    @AuraEnabled(cacheable=true)
    public static List<RefOption> getReferenceOptions(Id recordId) {
        String selfName;
        for (Agent_Skills_Repo__c r : [
            SELECT Name FROM Agent_Skills_Repo__c WHERE Id = :recordId WITH USER_MODE LIMIT 1
        ]) {
            selfName = r.Name;
        }
        List<RefOption> options = new List<RefOption>();
        for (Agent_Skills_Repo__c r : [
            SELECT Name, Type__c FROM Agent_Skills_Repo__c
            WHERE Status__c = 'active' AND Name != null
            WITH USER_MODE
            ORDER BY Type__c, Name
            LIMIT 2000
        ]) {
            if (r.Name == selfName) {
                continue;
            }
            RefOption o = new RefOption();
            o.name = r.Name;
            o.type = r.Type__c;
            options.add(o);
        }
        return options;
    }

    // Persist a validated, de-duplicated, no-spaces CSV of references onto the record.
    // Only names that resolve to a real active record are kept.
    @AuraEnabled
    public static String saveReferences(Id recordId, List<String> names) {
        Map<String, Agent_Skills_Repo__c> active = loadActive();
        Agent_Skills_Repo__c self = [
            SELECT Name FROM Agent_Skills_Repo__c WHERE Id = :recordId WITH USER_MODE LIMIT 1
        ];
        List<String> clean = new List<String>();
        Set<String> seen = new Set<String>();
        if (names != null) {
            for (String n : names) {
                String v = n == null ? null : n.trim();
                if (String.isBlank(v) || seen.contains(v) || v == self.Name) {
                    continue;
                }
                if (active.containsKey(v)) {
                    seen.add(v);
                    clean.add(v);
                }
            }
        }
        String csv = clean.isEmpty() ? null : String.join(clean, ',');
        Agent_Skills_Repo__c toUpdate = new Agent_Skills_Repo__c(Id = recordId, References__c = csv);
        update as user toUpdate;
        return csv;
    }
}
