@IsTest
private class Agent_Skill_Catalog_Test {
    private static Agent_Skills_Repo__c rec(String name, String version, String approval) {
        return new Agent_Skills_Repo__c(
            Name = name,
            Type__c = 'Skill',
            Status__c = 'active',
            Version__c = version,
            Locale__c = 'en-US',
            ExternalId__c = name + ':' + version + ':en-US',
            ApprovalState__c = approval,
            WhenToUse__c = 'When ' + version,
            InstructionBody__c = name + ' ' + version
        );
    }

    private static Agent_Skill_Catalog.Entry resolveOne(String name, Boolean requireApproval) {
        Agent_Skill_Catalog.Options opts = new Agent_Skill_Catalog.Options();
        opts.requireApproval = requireApproval;
        return Agent_Skill_Catalog.resolve(new Set<String>{ name }, opts).get(name);
    }

    @IsTest
    static void picksHighestVersionNumerically() {
        insert new List<Agent_Skills_Repo__c>{ rec('skill-v', 'v9', 'NotSubmitted'), rec('skill-v', 'v10', 'NotSubmitted') };

        Assert.areEqual('v10', resolveOne('skill-v', false).version);
        Assert.areEqual(1, Agent_Skill_Catalog.compareVersions('1.10', '1.9'));
        Assert.areEqual(0, Agent_Skill_Catalog.compareVersions('v2', 'v2'));
    }

    @IsTest
    static void excludesRejectedAndOutOfWindowRecords() {
        Agent_Skills_Repo__c future = rec('skill-w', 'v3', 'NotSubmitted');
        future.EffectiveFrom__c = Datetime.now().addDays(1);
        Agent_Skills_Repo__c expired = rec('skill-w', 'v2', 'NotSubmitted');
        expired.EffectiveTo__c = Datetime.now().addDays(-1);
        insert new List<Agent_Skills_Repo__c>{ future, expired, rec('skill-w', 'v4', 'Rejected'), rec('skill-w', 'v1', 'NotSubmitted') };

        Assert.areEqual('v1', resolveOne('skill-w', false).version);
    }

    @IsTest
    static void requireApprovalLoadsOnlyApproved() {
        insert new List<Agent_Skills_Repo__c>{ rec('skill-a', 'v2', 'NotSubmitted'), rec('skill-a', 'v1', 'Approved') };

        Assert.areEqual('v2', resolveOne('skill-a', false).version);
        Assert.areEqual('v1', resolveOne('skill-a', true).version);
    }

    @IsTest
    static void cachesLookupsAndInvalidatesOnChange() {
        Agent_Skill_Catalog.useOrgCacheInTests = true;
        Agent_Skills_Repo__c r = rec('skill-catalog-cache-probe', 'v1', 'NotSubmitted');
        insert r;

        resolveOne('skill-catalog-cache-probe', false);
        Integer afterFirst = Agent_Skill_Catalog.queryCount;
        resolveOne('skill-catalog-cache-probe', false);
        Assert.areEqual(afterFirst, Agent_Skill_Catalog.queryCount, 'Second lookup should be served from cache');

        r.InstructionBody__c = 'changed body';
        update r;
        Assert.areEqual('changed body', resolveOne('skill-catalog-cache-probe', false).instructions);
        Assert.areEqual(afterFirst + 1, Agent_Skill_Catalog.queryCount, 'Update should invalidate the cached entry');
    }

    @IsTest
    static void unknownNamesResolveToNothing() {
        Assert.isNull(resolveOne('skill-nope', false));
        Assert.isTrue(Agent_Skill_Catalog.resolve(new Set<String>(), null).isEmpty());
    }
}
