trigger AgentRewardTrigger on AgentReward__e (after insert) {
    AgentRewardHandler.processRewards(Trigger.new);
}