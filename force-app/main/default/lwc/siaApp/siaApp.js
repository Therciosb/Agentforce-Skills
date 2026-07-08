import { LightningElement, track } from 'lwc';

export default class SiaApp extends LightningElement {
    @track activeView = 'overview';
    @track agentApiName = '';
    selectedLessonId = null;

    get isOverview() { return this.activeView === 'overview'; }
    get isKnowledge() { return this.activeView === 'knowledge'; }
    get isLessonDetail() { return this.activeView === 'lesson-detail'; }
    get isSessions() { return this.activeView === 'sessions'; }
    get isCompare() { return this.activeView === 'compare'; }
    get isRewardRules() { return this.activeView === 'reward-rules'; }
    get isSubagents() { return this.activeView === 'subagents'; }
    get isThresholds() { return this.activeView === 'thresholds'; }

    get hasAgent() { return !!this.agentApiName; }

    handleAgentChange(event) {
        this.agentApiName = event.detail.agentApiName;
    }

    handleNavSelect(event) {
        this.activeView = event.detail.name;
        this.selectedLessonId = null;
    }

    handleLessonSelected(event) {
        this.selectedLessonId = event.detail.lessonId;
        this.activeView = 'lesson-detail';
    }

    handleBackToKnowledge() {
        this.selectedLessonId = null;
        // Force re-mount by briefly setting to null then back to knowledge
        this.activeView = '';
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => {
            this.activeView = 'knowledge';
        });
    }
}