import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLessons from '@salesforce/apex/SiaKnowledgeController.getLessons';
import getSubagentConfigs from '@salesforce/apex/SiaConfigController.getSubagentConfigs';

const COLUMNS = [
    {
        label: 'Status',
        fieldName: 'status',
        type: 'text',
        initialWidth: 100
    },
    {
        label: 'Lesson',
        fieldName: 'lesson_text__c',
        type: 'text',
        wrapText: true
    },
    {
        label: 'Confidence',
        fieldName: 'confidence_score__c',
        type: 'number',
        initialWidth: 110,
        cellAttributes: { alignment: 'center' }
    },
    {
        label: 'Refs',
        fieldName: 'times_referenced__c',
        type: 'number',
        initialWidth: 80,
        cellAttributes: { alignment: 'center' }
    },
    {
        label: 'Subagent',
        fieldName: 'topic_area__c',
        type: 'text',
        initialWidth: 130
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [{ label: 'View Detail', name: 'view' }]
        }
    }
];

export default class SiaKnowledgeExplorer extends LightningElement {
    _agentApiName;

    @api
    get agentApiName() { return this._agentApiName; }
    set agentApiName(value) {
        if (value && value !== this._agentApiName) {
            this._agentApiName = value;
            this.loadData();
        }
    }

    selectedSubagent = '';
    selectedStatus = '';
    searchTerm = '';
    @track lessons = [];
    subagentOptions = [];
    isLoading = false;

    columns = COLUMNS;

    statusOptions = [
        { label: 'All', value: '' },
        { label: 'Promoted', value: 'promoted' },
        { label: 'Active', value: 'active' },
        { label: 'Hidden', value: 'hidden' },
        { label: 'Archived', value: 'archived' }
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
        await this.loadLessons();
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

    async loadLessons() {
        if (!this.agentApiName) return;
        this.isLoading = true;
        try {
            const raw = await getLessons({
                agentApiName: this.agentApiName,
                topicArea: this.selectedSubagent || null,
                status: this.selectedStatus || null
            });
            this.lessons = raw.map(r => ({
                ...r,
                id: r.Id,
                status: r.is_promoted__c
                    ? '★ Promoted'
                    : r.is_archived__c
                        ? '✕ Archived'
                        : r.confidence_score__c < 0.30
                            ? '▼ Hidden'
                            : '○ Active',
                lesson_text__c: r.lesson_text__c,
                confidence_score__c: r.confidence_score__c,
                times_referenced__c: r.times_referenced__c,
                topic_area__c: r.topic_area__c
            }));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error loading lessons',
                message: error?.body?.message || 'Unknown error',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    get filteredLessons() {
        if (!this.searchTerm) return this.lessons;
        const term = this.searchTerm.toLowerCase();
        return this.lessons.filter(l =>
            (l.lesson_text__c && l.lesson_text__c.toLowerCase().includes(term)) ||
            (l.topic_area__c && l.topic_area__c.toLowerCase().includes(term))
        );
    }

    get hasLessons() {
        return !this.isLoading && this.filteredLessons.length > 0;
    }

    get noResults() {
        return !this.isLoading && this.lessons.length > 0 && this.filteredLessons.length === 0;
    }

    handleSubagentChange(event) {
        this.selectedSubagent = event.detail.value;
        this.loadLessons();
    }

    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
        this.loadLessons();
    }

    handleSearchChange(event) {
        this.searchTerm = event.detail.value;
    }

    handleRowClick(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        if (action.name === 'view') {
            this.dispatchEvent(new CustomEvent('lessonselected', {
                detail: { lessonId: row.Id }
            }));
        }
    }
}