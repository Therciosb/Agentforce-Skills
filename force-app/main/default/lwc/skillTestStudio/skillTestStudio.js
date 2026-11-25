import { LightningElement, wire } from 'lwc';
import { deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listBindings from '@salesforce/apex/Agent_Skill_Binding_Controller.listBindings';
import getWiringSummary from '@salesforce/apex/Agent_Skill_Binding_Controller.getWiringSummary';
import listCases from '@salesforce/apex/Agent_Skill_Test_Runner.listCases';
import runCase from '@salesforce/apex/Agent_Skill_Test_Runner.runCase';
import exportTestSpec from '@salesforce/apex/Agent_Skill_Test_Runner.exportTestSpec';

// lightning-combobox cannot select an empty value, so the agent-level wiring gets a stand-in value.
const AGENT_LEVEL = '__agent__';

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

function sameSubagent(a, b) {
    return (a || '').trim().toLowerCase() === (b || '').trim().toLowerCase();
}

export default class SkillTestStudio extends LightningElement {
    columns = COLUMNS;
    bindings = [];
    agentName;
    subagent = '';
    allCases = [];
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
        const seen = new Map();
        this.bindings.forEach((b) => {
            if (!seen.has(b.agentName)) {
                seen.set(b.agentName, { label: b.agentName, value: b.agentName });
            }
        });
        return [...seen.values()];
    }

    // Subagents wired for the selected agent; '' is the agent-level wiring.
    get subagentNames() {
        const names = this.bindings.filter((b) => b.agentName === this.agentName).map((b) => b.subagent || '');
        this.allCases.forEach((c) => names.push(c.Subagent__c || ''));
        return [...new Set(names)];
    }

    get subagentOptions() {
        return this.subagentNames
            .sort((a, b) => (a === '' ? -1 : b === '' ? 1 : a.localeCompare(b)))
            .map((name) => {
                const count = this.allCases.filter((c) => sameSubagent(c.Subagent__c, name)).length;
                return { label: `${name || 'All subagents (agent level)'} · ${count} case${count === 1 ? '' : 's'}`, value: name || AGENT_LEVEL };
            });
    }

    get subagentValue() {
        return this.subagent || AGENT_LEVEL;
    }

    get subagentLabel() {
        return this.subagent || 'agent level';
    }

    get cases() {
        return this.allCases.filter((c) => sameSubagent(c.Subagent__c, this.subagent));
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
        return this.allCases.length === 0;
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
        return this.editId ? 'Edit test case' : `New test case for ${this.subagentLabel}`;
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
            subagentDisplay: r.subagent || 'agent level',
            expectedDisplay: r.expectedSkills || 'Not checked',
            selectedDisplay: r.selectedSkills || 'None',
            toolsDisplay: r.enabledTools || 'None'
        }));
    }

    async handleAgent(event) {
        this.agentName = event.detail.value;
        this.resetPanels();
        await this.loadCases();
        const names = this.subagentNames;
        this.subagent = names.includes(this.subagent) ? this.subagent : names.find((n) => n) || names[0] || '';
        await this.loadSelectable();
    }

    async handleSubagent(event) {
        this.setSubagent(event.detail.value === AGENT_LEVEL ? '' : event.detail.value);
    }

    handlePreviewSubagent(event) {
        this.setSubagent(event.detail.subagent);
    }

    async setSubagent(value) {
        if (value === this.subagent) {
            return;
        }
        this.subagent = value;
        this.resetPanels();
        await this.loadSelectable();
    }

    resetPanels() {
        this.results = [];
        this.selectedIds = [];
        this.spec = undefined;
        this.editing = false;
    }

    async loadCases() {
        try {
            this.allCases = await listCases({ agentName: this.agentName, subagentName: null });
            this.error = undefined;
        } catch (e) {
            this.error = errorMessage(e);
        }
    }

    async loadSelectable() {
        try {
            const summary = await getWiringSummary({ agentName: this.agentName, subagentName: this.subagent });
            this.selectable = summary.found ? summary.selectable.join(', ') : '';
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
        if (!this.editId) {
            fields.Subagent__c = this.subagent || null;
        }
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
        const runId = `run-${Date.now()}`;
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
                const tc = this.allCases.find((c) => c.Id === id);
                results.push({ testCaseId: id, name: tc ? tc.Name : id, subagent: tc ? tc.Subagent__c : '', passed: false, warnings: errorMessage(e) });
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
