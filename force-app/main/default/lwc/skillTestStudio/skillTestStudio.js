import { LightningElement, wire } from 'lwc';
import { deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listBindings from '@salesforce/apex/Agent_Skill_Binding_Controller.listBindings';
import previewState from '@salesforce/apex/Agent_Skill_Binding_Controller.previewState';
import listCases from '@salesforce/apex/Agent_Skill_Test_Runner.listCases';
import runCase from '@salesforce/apex/Agent_Skill_Test_Runner.runCase';
import exportTestSpec from '@salesforce/apex/Agent_Skill_Test_Runner.exportTestSpec';

const COLUMNS = [
    { label: 'Name', fieldName: 'Name' },
    { label: 'Utterance', fieldName: 'Utterance__c', wrapText: true },
    { label: 'Expected skills', fieldName: 'Expected_Skills__c' },
    { label: 'Expected tools', fieldName: 'Expected_Tools__c' },
    { label: 'Last status', fieldName: 'Last_Status__c', initialWidth: 110, cellAttributes: { class: { fieldName: 'statusClass' } } },
    { label: 'Last run', fieldName: 'Last_Run__c', type: 'date', initialWidth: 170, typeAttributes: { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' } },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Run', name: 'run' },
                { label: 'Edit', name: 'edit' },
                { label: 'Delete', name: 'delete' }
            ]
        }
    }
];

function errorMessage(error) {
    return (error && error.body && error.body.message) || (error && error.message) || 'Something went wrong.';
}

export default class SkillTestStudio extends LightningElement {
    columns = COLUMNS;
    bindings = [];
    agentName;
    cases = [];
    selectedIds = [];
    selectable = '';
    editing = false;
    editId;
    results = [];
    running = false;
    runDone = 0;
    runTotal = 0;
    spec;
    error;

    @wire(listBindings)
    wiredBindings({ data, error }) {
        if (data) {
            this.bindings = data;
        } else if (error) {
            this.error = errorMessage(error);
        }
    }

    get agentOptions() {
        return this.bindings.map((b) => ({ label: `${b.name} (${b.agentName})`, value: b.agentName }));
    }

    get caseRows() {
        return this.cases.map((c) => ({
            ...c,
            statusClass: c.Last_Status__c === 'Pass' ? 'slds-text-color_success' : c.Last_Status__c === 'Fail' ? 'slds-text-color_error' : ''
        }));
    }

    get hasCases() {
        return this.cases.length > 0;
    }

    get noCases() {
        return !this.hasCases;
    }

    get activeCaseIds() {
        return this.cases.filter((c) => c.Active__c).map((c) => c.Id);
    }

    get runAllDisabled() {
        return this.running || this.activeCaseIds.length === 0;
    }

    get runSelectedDisabled() {
        return this.running || this.selectedIds.length === 0;
    }

    get progress() {
        return this.runTotal ? Math.round((this.runDone / this.runTotal) * 100) : 0;
    }

    get editTitle() {
        return this.editId ? 'Edit test case' : 'New test case';
    }

    get selectableHint() {
        return this.selectable || 'none';
    }

    get hasResults() {
        return this.results.length > 0;
    }

    get resultCount() {
        return this.results.length;
    }

    get passCount() {
        return this.results.filter((r) => r.passed).length;
    }

    get summaryClass() {
        return this.passCount === this.resultCount ? 'badge badge--pass' : 'badge badge--fail';
    }

    get resultRows() {
        return this.results.map((r) => ({
            ...r,
            status: r.passed ? 'Pass' : 'Fail',
            badgeClass: r.passed ? 'badge badge--pass' : 'badge badge--fail',
            expectedDisplay: r.expectedSkills || 'Not checked',
            toolsDisplay: r.enabledTools || 'None'
        }));
    }

    async handleAgent(event) {
        this.agentName = event.detail.value;
        this.results = [];
        this.spec = undefined;
        this.editing = false;
        await Promise.all([this.loadCases(), this.loadSelectable()]);
    }

    async loadCases() {
        try {
            this.cases = await listCases({ agentName: this.agentName });
            this.error = undefined;
        } catch (e) {
            this.error = errorMessage(e);
        }
    }

    async loadSelectable() {
        try {
            const state = await previewState({ agentName: this.agentName, requestedSkills: '' });
            const names = (state.skill_menu || '').match(/skill-[a-z0-9-]+/g) || [];
            this.selectable = [...new Set(names)].join(', ');
        } catch (e) {
            this.selectable = '';
        }
    }

    handleSelection(event) {
        this.selectedIds = event.detail.selectedRows.map((r) => r.Id);
    }

    handleNew() {
        this.editId = undefined;
        this.editing = true;
    }

    handleCancel() {
        this.editing = false;
    }

    handleSubmit(event) {
        event.preventDefault();
        const fields = { ...event.detail.fields, Agent_Developer_Name__c: this.agentName };
        this.template.querySelector('lightning-record-edit-form').submit(fields);
    }

    async handleSaved() {
        this.editing = false;
        this.toast('Saved', 'Test case saved.', 'success');
        await this.loadCases();
    }

    handleFormError(event) {
        this.error = (event.detail && event.detail.detail) || 'The test case could not be saved.';
    }

    async handleRowAction(event) {
        const { name } = event.detail.action;
        const row = event.detail.row;
        if (name === 'run') {
            await this.runCases([row.Id]);
        } else if (name === 'edit') {
            this.editId = row.Id;
            this.editing = true;
        } else if (name === 'delete') {
            try {
                await deleteRecord(row.Id);
                await this.loadCases();
            } catch (e) {
                this.error = errorMessage(e);
            }
        }
    }

    handleRunAll() {
        this.runCases(this.activeCaseIds);
    }

    handleRunSelected() {
        this.runCases(this.selectedIds);
    }

    // One case per server call keeps each LLM request within its own transaction limits and lets progress render.
    async runCases(ids) {
        const runId = `${this.agentName}-${Date.now()}`;
        this.running = true;
        this.runDone = 0;
        this.runTotal = ids.length;
        this.results = [];
        this.error = undefined;
        const results = [];
        for (const id of ids) {
            try {
                // eslint-disable-next-line no-await-in-loop
                results.push(await runCase({ testCaseId: id, runId }));
            } catch (e) {
                const tc = this.cases.find((c) => c.Id === id);
                results.push({ testCaseId: id, name: tc ? tc.Name : id, passed: false, warnings: errorMessage(e) });
            }
            this.runDone += 1;
            this.results = [...results];
        }
        this.running = false;
        await this.loadCases();
    }

    async handleExport() {
        try {
            this.spec = await exportTestSpec({ agentName: this.agentName });
        } catch (e) {
            this.error = errorMessage(e);
        }
    }

    async handleCopy() {
        try {
            await navigator.clipboard.writeText(this.spec);
            this.toast('Copied', 'Testing Center spec copied to the clipboard.', 'success');
        } catch (e) {
            this.toast('Copy failed', 'Select the spec text and copy it manually.', 'warning');
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
