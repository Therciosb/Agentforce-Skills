@IsTest
private class Agent_Skill_SeedService_Test {
    private static final Pattern RECORD_NAME = Pattern.compile('\\b(?:role|core-skill|skill|workflow)-[A-Za-z0-9-]+');

    @IsTest
    static void seedsWellFormedCustomerSupportRecords() {
        Agent_Skill_SeedService.seedCustomerSupportDemo();
        Agent_Skill_SeedService.seedCustomerSupportDemo();

        List<Agent_Skills_Repo__c> records = [SELECT Name, InstructionBody__c, References__c FROM Agent_Skills_Repo__c];
        Assert.areEqual(18, records.size(), 'Re-running the seed upserts instead of duplicating');

        Set<String> names = new Set<String>();
        for (Agent_Skills_Repo__c r : records) {
            names.add(r.Name);
        }
        for (Agent_Skills_Repo__c r : records) {
            Assert.isTrue(r.InstructionBody__c.startsWith('# '), r.Name + ' starts with one H1 title');
            Assert.isFalse(r.InstructionBody__c.contains('\\n'), r.Name + ' has no literal \\n');
            Set<String> refs = new Set<String>();
            for (String ref : String.isBlank(r.References__c) ? new List<String>() : r.References__c.split(',')) {
                refs.add(ref);
                Assert.isTrue(names.contains(ref), r.Name + ' references a seeded record: ' + ref);
            }
            Set<String> mentioned = new Set<String>();
            Matcher m = RECORD_NAME.matcher(r.InstructionBody__c);
            while (m.find()) {
                if (names.contains(m.group()) && m.group() != r.Name) {
                    mentioned.add(m.group());
                }
            }
            Assert.areEqual(refs, mentioned, r.Name + ' lists exactly the records its body names');
        }
    }
}
