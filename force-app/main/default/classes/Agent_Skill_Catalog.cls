public with sharing class Agent_Skill_Catalog {
    private static final String PARTITION = 'local.AgentSkills';
    private static final Integer TTL_SECONDS = 3600;
    private static final Pattern DIGITS = Pattern.compile('\\d+');

    public class Entry {
        public String name;
        public String type;
        public String version;
        public String status;
        public String approvalState;
        public Datetime effectiveFrom;
        public Datetime effectiveTo;
        public String instructions;
        public String references;
        public String whenToUse;
    }

    public class Options {
        public String locale;
        public String version;
        public Boolean requireApproval = false;
        public Boolean includeDeprecated = false;
    }

    // locale|name -> every record with that name in that locale; an empty list caches "not found".
    private static Map<String, List<Entry>> transactionCache = new Map<String, List<Entry>>();

    @TestVisible
    private static Integer queryCount = 0;

    @TestVisible
    private static Boolean useOrgCacheInTests = false;

    public static Map<String, Entry> resolve(Set<String> names, Options opts) {
        Options o = opts == null ? new Options() : opts;
        Map<String, Entry> resolved = new Map<String, Entry>();
        if (names == null || names.isEmpty()) {
            return resolved;
        }
        Map<String, List<Entry>> candidatesByName = candidates(names, locale(o.locale));
        Datetime now = Datetime.now();
        for (String name : names) {
            Entry best;
            for (Entry e : candidatesByName.get(name)) {
                if (isLive(e, now, o) && (best == null || compareVersions(e.version, best.version) > 0)) {
                    best = e;
                }
            }
            if (best != null) {
                resolved.put(name, best);
            }
        }
        return resolved;
    }

    public static void invalidate(List<Agent_Skills_Repo__c> records) {
        Set<String> cacheKeys = new Set<String>();
        for (Agent_Skills_Repo__c rec : records) {
            String key = transactionKey(locale(rec.Locale__c), rec.Name);
            transactionCache.remove(key);
            cacheKeys.add(cacheKey(key));
        }
        Cache.OrgPartition p = partition();
        if (p == null) {
            return;
        }
        for (String k : cacheKeys) {
            try {
                p.remove(k);
            } catch (Exception ex) {
                continue;
            }
        }
    }

    public static Integer compareVersions(String left, String right) {
        List<Integer> l = versionParts(left);
        List<Integer> r = versionParts(right);
        for (Integer i = 0; i < Math.max(l.size(), r.size()); i++) {
            Integer a = i < l.size() ? l[i] : 0;
            Integer b = i < r.size() ? r[i] : 0;
            if (a != b) {
                return a < b ? -1 : 1;
            }
        }
        String ls = left == null ? '' : left;
        String rs = right == null ? '' : right;
        return ls.compareTo(rs) < 0 ? -1 : (ls == rs ? 0 : 1);
    }

    private static Boolean isLive(Entry e, Datetime now, Options o) {
        Boolean statusOk = e.status == 'active' || (o.includeDeprecated == true && e.status == 'deprecated');
        Boolean approvalOk = e.approvalState != 'Rejected' && (o.requireApproval != true || e.approvalState == 'Approved');
        Boolean windowOk = (e.effectiveFrom == null || e.effectiveFrom <= now) && (e.effectiveTo == null || e.effectiveTo > now);
        Boolean versionOk = String.isBlank(o.version) || e.version == o.version;
        return statusOk && approvalOk && windowOk && versionOk;
    }

    private static Map<String, List<Entry>> candidates(Set<String> names, String loc) {
        Map<String, List<Entry>> byName = new Map<String, List<Entry>>();
        Set<String> missing = new Set<String>();
        for (String name : names) {
            String key = transactionKey(loc, name);
            if (transactionCache.containsKey(key)) {
                byName.put(name, transactionCache.get(key));
            } else {
                missing.add(name);
            }
        }
        if (!missing.isEmpty()) {
            readOrgCache(missing, loc, byName);
        }
        if (!missing.isEmpty()) {
            queryRepo(missing, loc, byName);
        }
        return byName;
    }

    private static void readOrgCache(Set<String> missing, String loc, Map<String, List<Entry>> byName) {
        Cache.OrgPartition p = partition();
        if (p == null) {
            return;
        }
        Map<String, String> nameByCacheKey = new Map<String, String>();
        for (String name : missing) {
            nameByCacheKey.put(cacheKey(transactionKey(loc, name)), name);
        }
        Map<String, Object> hits;
        try {
            hits = p.get(nameByCacheKey.keySet());
        } catch (Exception ex) {
            return;
        }
        for (String k : hits.keySet()) {
            Object raw = hits.get(k);
            if (raw == null) {
                continue;
            }
            try {
                List<Entry> entries = (List<Entry>) JSON.deserialize((String) raw, List<Entry>.class);
                String name = nameByCacheKey.get(k);
                byName.put(name, entries);
                transactionCache.put(transactionKey(loc, name), entries);
                missing.remove(name);
            } catch (Exception ex) {
                continue;
            }
        }
    }

    private static void queryRepo(Set<String> missing, String loc, Map<String, List<Entry>> byName) {
        Map<String, List<Entry>> found = new Map<String, List<Entry>>();
        for (String name : missing) {
            found.put(name, new List<Entry>());
        }
        queryCount++;
        for (Agent_Skills_Repo__c rec : [
            SELECT Name, Type__c, Version__c, Status__c, ApprovalState__c, EffectiveFrom__c, EffectiveTo__c,
                InstructionBody__c, References__c, WhenToUse__c
            FROM Agent_Skills_Repo__c
            WHERE Name IN :missing AND Locale__c = :loc
        ]) {
            found.get(rec.Name).add(toEntry(rec));
        }
        Cache.OrgPartition p = partition();
        for (String name : found.keySet()) {
            String key = transactionKey(loc, name);
            List<Entry> entries = found.get(name);
            byName.put(name, entries);
            transactionCache.put(key, entries);
            if (p != null) {
                try {
                    p.put(cacheKey(key), JSON.serialize(entries), TTL_SECONDS);
                } catch (Exception ex) {
                    continue;
                }
            }
        }
        missing.clear();
    }

    private static Entry toEntry(Agent_Skills_Repo__c rec) {
        Entry e = new Entry();
        e.name = rec.Name;
        e.type = rec.Type__c;
        e.version = rec.Version__c;
        e.status = rec.Status__c;
        e.approvalState = rec.ApprovalState__c;
        e.effectiveFrom = rec.EffectiveFrom__c;
        e.effectiveTo = rec.EffectiveTo__c;
        e.instructions = rec.InstructionBody__c;
        e.references = rec.References__c;
        e.whenToUse = rec.WhenToUse__c;
        return e;
    }

    private static List<Integer> versionParts(String version) {
        List<Integer> parts = new List<Integer>();
        if (String.isBlank(version)) {
            return parts;
        }
        Matcher m = DIGITS.matcher(version);
        while (m.find()) {
            parts.add(Integer.valueOf(m.group().left(9)));
        }
        return parts;
    }

    private static String locale(String value) {
        return String.isBlank(value) ? 'en-US' : value.trim();
    }

    private static String transactionKey(String loc, String name) {
        return loc + '|' + name;
    }

    private static String cacheKey(String transactionKey) {
        // The org cache is shared with live agents during test runs; test data must never land on real keys.
        String prefix = Test.isRunningTest() ? 't' : 'k';
        return prefix + EncodingUtil.convertToHex(Crypto.generateDigest('MD5', Blob.valueOf(transactionKey)));
    }

    private static Cache.OrgPartition partition() {
        if (Test.isRunningTest() && !useOrgCacheInTests) {
            return null;
        }
        try {
            return Cache.Org.getPartition(PARTITION);
        } catch (Exception ex) {
            return null;
        }
    }
}
