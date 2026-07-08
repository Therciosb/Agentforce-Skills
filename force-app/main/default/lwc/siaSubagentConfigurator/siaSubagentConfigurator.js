import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSubagentConfigs from '@salesforce/apex/SiaConfigController.getSubagentConfigs';
import upsertSubagentConfig from '@salesforce/apex/SiaConfigController.upsertSubagentConfig';

const OUTCOME_OPTIONS = [
    { label: 'Success', value: 'success' },
    { label: 'Partial', value: 'partial' },
    { label: 'Failure', value: 'failure' }
];

const DEFAULT_TRIGGER_OPTIONS = [
    { label: 'After any failure', value: 'failure' },
    { label: 'After success below optimal', value: 'below_optimal' },
    { label: 'After novel scenario', value: 'novel' }
];

export default class SiaSubagentConfigurator extends LightningElement {
    _agentApiName;

    @api
    get agentApiName() { return this._agentApiName; }
    set agentApiName(value) {
        if (value && value !== this._agentApiName) {
            this._agentApiName = value;
            this.loadData();
        }
    }

    configs = [];
    _connected = false;
    isLoading = false;
    outcomeOptions = OUTCOME_OPTIONS;

    connectedCallback() {
        this._connected = true;
        if (this.agentApiName) this.loadData();
    }

    get hasNoAgent() {
        return !this.agentApiName;
    }

    get activeSections() {
        return this.configs.map(c => c.Id);
    }

    async loadData() {
        if (!this.agentApiName) return;
        try {
            this.isLoading = true;
            const rawConfigs = await getSubagentConfigs({ agentApiName: this.agentApiName });
            this.configs = rawConfigs.map(config => this.enrichConfig(config));
        } catch (error) {
            this.showToast('Error', 'Failed to load subagent configs: ' + this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    enrichConfig(config) {
        let parsedOutcomeMapping = [];
        try {
            const json = JSON.parse(config.outcome_mapping_json__c || '[]');
            if (Array.isArray(json)) {
                parsedOutcomeMapping = json.map((item, idx) => ({
                    key: `${config.Id}-mapping-${idx}`,
                    event: item.domain_event || '',
                    outcome: item.maps_to || 'success'
                }));
            }
        } catch (e) {
            parsedOutcomeMapping = [];
        }

        const triggers = (config.significant_outcome_triggers__c || '').split(';').filter(Boolean).map(t => t.trim());

        return {
            ...config,
            parsedOutcomeMapping,
            triggerOptions: DEFAULT_TRIGGER_OPTIONS,
            selectedTriggers: triggers
        };
    }

    handleFieldChange(event) {
        const configId = event.target.dataset.id;
        const field = event.target.dataset.field;
        const value = event.target.value;
        this.configs = this.configs.map(c =>
            c.Id === configId ? { ...c, [field]: value } : c
        );
    }

    handleMappingChange(event) {
        const configId = event.target.dataset.id;
        const mappingKey = event.target.dataset.mappingKey;
        const mappingField = event.target.dataset.mappingField;
        const value = event.detail.value || event.target.value;

        this.configs = this.configs.map(c => {
            if (c.Id !== configId) return c;
            const parsedOutcomeMapping = c.parsedOutcomeMapping.map(m =>
                m.key === mappingKey ? { ...m, [mappingField]: value } : m
            );
            return { ...c, parsedOutcomeMapping };
        });
    }

    handleAddMapping(event) {
        const configId = event.target.dataset.id;
        this.configs = this.configs.map(c => {
            if (c.Id !== configId) return c;
            const newKey = `${configId}-mapping-${c.parsedOutcomeMapping.length}`;
            const parsedOutcomeMapping = [...c.parsedOutcomeMapping, { key: newKey, event: '', outcome: 'success' }];
            return { ...c, parsedOutcomeMapping };
        });
    }

    handleTriggerChange(event) {
        const configId = event.target.dataset.id;
        const selectedTriggers = event.detail.value;
        this.configs = this.configs.map(c =>
            c.Id === configId ? { ...c, selectedTriggers } : c
        );
    }

    async handleSave(event) {
        const configId = event.target.dataset.id;
        const config = this.configs.find(c => c.Id === configId);
        if (!config) return;

        const outcomeMapping = config.parsedOutcomeMapping
            .filter(m => m.event)
            .map(m => ({ domain_event: m.event, maps_to: m.outcome }));

        const record = {
            Id: config.Id,
            optimal_actions__c: parseInt(config.optimal_actions__c, 10),
            outcome_mapping_json__c: JSON.stringify(outcomeMapping),
            significant_outcome_triggers__c: config.selectedTriggers.join(';')
        };

        try {
            this.isLoading = true;
            await upsertSubagentConfig({ config: record });
            this.showToast('Success', `${config.Name} saved successfully.`, 'success');
            await this.loadData();
        } catch (error) {
            this.showToast('Error', 'Failed to save: ' + this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return JSON.stringify(error);
    }
}