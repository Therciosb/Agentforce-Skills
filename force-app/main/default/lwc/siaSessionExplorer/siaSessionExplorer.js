import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSessions from '@salesforce/apex/SiaSessionController.getSessions';
import getSessionActions from '@salesforce/apex/SiaSessionController.getSessionActions';
import getSubagentConfigs from '@salesforce/apex/SiaConfigController.getSubagentConfigs';

const COLUMNS = [
    { label: 'Session ID', fieldName: 'session_id__c', type: 'text' },
    { label: 'Outcome', fieldName: 'final_outcome__c', type: 'text', initialWidth: 110 },
    { label: 'AES', fieldName: 'aes_score__c', type: 'number', initialWidth: 80 },
    { label: 'Points', fieldName: 'final_points__c', type: 'number', initialWidth: 90 },
    { label: 'Actions', fieldName: 'actions_taken__c', type: 'number', initialWidth: 90 },
    { label: 'Lessons', fieldName: 'lessons_applied__c', type: 'number', initialWidth: 90 },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [{ label: 'View Timeline', name: 'timeline' }]
        }
    }
];

export default class SiaSessionExplorer extends LightningElement {
    _agentApiName;

    @api
    get agentApiName() { return this._agentApiName; }
    set agentApiName(value) {
        if (value && value !== this._agentApiName) {
            this._agentApiName = value;
            this.loadData();
        }
    }

    periodWeeks = '12';
    selectedOutcome = '';
    selectedSubagent = '';
    @track sessions = [];
    @track sessionActions = [];
    subagentOptions = [];
    isLoading = false;
    isLoadingTimeline = false;
    selectedSessionId = null;

    columns = COLUMNS;

    periodOptions = [
        { label: '4 Weeks', value: '4' },
        { label: '8 Weeks', value: '8' },
        { label: '12 Weeks', value: '12' },
        { label: '24 Weeks', value: '24' }
    ];

    outcomeOptions = [
        { label: 'All', value: '' },
        { label: 'Success', value: 'Success' },
        { label: 'Partial', value: 'Partial' },
        { label: 'Failure', value: 'Failure' }
    ];

    _connected = false;

    connectedCallback() {
        this._connected = true;
        if (this.agentApiName) {
            this.loadData();
        }
    }

    async loadData() {
        if (!this._connected) return;
        if (!this.agentApiName) return;
        await this.loadSubagents();
        await this.loadSessions();
    }

    async loadSubagents() {
        try {
            const configs = await getSubagentConfigs({ agentApiName: this.agentApiName });
            this.subagentOptions = [
                { label: 'All', value: '' },
                ...configs.map(c => ({ label: c.topic_area__c, value: c.topic_area__c }))
            ];
        } catch (error) {
            console.error('Error loading subagents', error);
        }
    }

    async loadSessions() {
        if (!this.agentApiName) return;
        this.isLoading = true;
        this.selectedSessionId = null;
        try {
            const weeks = parseInt(this.periodWeeks, 10);
            const days = weeks * 7;
            this.sessions = await getSessions({
                agentApiName: this.agentApiName,
                filters: {
                    period: days + 'd',
                    outcome: this.selectedOutcome || null,
                    topicArea: this.selectedSubagent || null
                }
            });
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error loading sessions',
                message: error?.body?.message || 'Unknown error',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    async loadTimeline(sessionId) {
        this.isLoadingTimeline = true;
        try {
            const actions = await getSessionActions({ sessionId });
            this.sessionActions = actions.map(a => ({
                ...a,
                id: a.Id,
                actionName: a.action_name__c,
                timestamp: a.timestamp__c,
                outcome: a.outcome__c,
                points: a.reward_points__c,
                lessonRef: a.lesson_linked__c || null,
                outcomeClass: a.outcome__c === 'Success'
                    ? 'slds-badge slds-badge_success'
                    : a.outcome__c === 'Failure'
                        ? 'slds-badge slds-badge_error'
                        : 'slds-badge'
            }));
        } catch (error) {
            console.error('Error loading timeline', error);
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: 'Failed to load action timeline', variant: 'error' }));
        } finally {
            this.isLoadingTimeline = false;
        }
    }

    get hasSessions() {
        return !this.isLoading && this.sessions.length > 0;
    }

    get showTimeline() {
        return this.selectedSessionId != null;
    }

    get hasActions() {
        return !this.isLoadingTimeline && this.sessionActions.length > 0;
    }

    handlePeriodChange(event) {
        this.periodWeeks = event.detail.value;
        this.loadSessions();
    }

    handleOutcomeChange(event) {
        this.selectedOutcome = event.detail.value;
        this.loadSessions();
    }

    handleSubagentChange(event) {
        this.selectedSubagent = event.detail.value;
        this.loadSessions();
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        if (action.name === 'timeline') {
            this.selectedSessionId = row.session_id__c || row.Id;
            this.loadTimeline(this.selectedSessionId);
        }
    }
}