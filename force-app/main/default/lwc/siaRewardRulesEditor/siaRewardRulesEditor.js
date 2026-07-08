import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRewardConfigs from '@salesforce/apex/SiaConfigController.getRewardConfigs';
import upsertRewardConfigs from '@salesforce/apex/SiaConfigController.upsertRewardConfigs';

export default class SiaRewardRulesEditor extends LightningElement {
    _agentApiName;
    _connected = false;

    @api
    get agentApiName() { return this._agentApiName; }
    set agentApiName(value) {
        if (value && value !== this._agentApiName) {
            this._agentApiName = value;
            if (this._connected) this.loadData();
        }
    }

    @track rules = [];
    isLoading = false;
    showAddForm = false;
    _dirty = false;
    newRule = { name: '', topicArea: '', points: 0 };

    connectedCallback() {
        this._connected = true;
        console.log('[SIA-RewardRules] connectedCallback, agent=' + this.agentApiName);
        if (this.agentApiName) this.loadData();
    }

    get hasNoAgent() {
        return !this.agentApiName;
    }

    get hasRules() {
        return !this.isLoading && !this.hasNoAgent && this.rules.length > 0;
    }

    get groupedRules() {
        const groups = {};
        this.rules.forEach(rule => {
            const key = rule.topic_area__c || 'Global';
            if (!groups[key]) {
                groups[key] = {
                    key,
                    label: key === 'Global' ? 'Global (applies to all subagents)' : key + ' (overrides global)',
                    records: []
                };
            }
            groups[key].records.push(rule);
        });
        const sorted = Object.values(groups);
        sorted.sort((a, b) => a.key === 'Global' ? -1 : b.key === 'Global' ? 1 : a.key.localeCompare(b.key));
        return sorted;
    }

    async loadData() {
        console.log('[SIA-RewardRules] loadData called, agent=' + this.agentApiName);
        if (!this.agentApiName) return;
        this.isLoading = true;
        try {
            this.rules = await getRewardConfigs({ agentApiName: this.agentApiName });
            console.log('[SIA-RewardRules] loaded ' + this.rules.length + ' rules');
            this._dirty = false;
        } catch (error) {
            this.showToast('Error', 'Failed to load reward rules: ' + this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleFieldChange(event) {
        const ruleId = event.target.dataset.id;
        const value = event.target.value;
        this.rules = this.rules.map(r =>
            r.Id === ruleId ? { ...r, points__c: parseInt(value, 10) } : r
        );
        this._dirty = true;
    }

    handleToggleChange(event) {
        const ruleId = event.target.dataset.id;
        const checked = event.target.checked;
        this.rules = this.rules.map(r =>
            r.Id === ruleId ? { ...r, is_active__c: checked } : r
        );
        this._dirty = true;
    }

    handleRemoveRule(event) {
        const ruleId = event.target.dataset.id;
        this.rules = this.rules.filter(r => r.Id !== ruleId);
        this._dirty = true;
    }

    async handleSaveAll() {
        this.isLoading = true;
        try {
            await upsertRewardConfigs({ configs: this.rules });
            this._dirty = false;
            this.showToast('Success', 'Reward rules saved.', 'success');
            await this.loadData();
        } catch (error) {
            this.showToast('Error', 'Failed to save: ' + this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleAddRule() {
        this.showAddForm = true;
    }

    handleCancelAdd() {
        this.showAddForm = false;
        this.newRule = { name: '', topicArea: '', points: 0 };
    }

    handleNewRuleName(event) {
        this.newRule = { ...this.newRule, name: event.target.value };
    }

    handleNewRuleTopicArea(event) {
        this.newRule = { ...this.newRule, topicArea: event.target.value };
    }

    handleNewRulePoints(event) {
        this.newRule = { ...this.newRule, points: event.target.value };
    }

    async handleConfirmAdd() {
        if (!this.newRule.name) {
            this.showToast('Error', 'Action/Outcome name is required.', 'error');
            return;
        }
        const record = {
            Name: this.newRule.name,
            action_name__c: this.newRule.name,
            topic_area__c: this.newRule.topicArea || null,
            points__c: parseInt(this.newRule.points, 10) || 0,
            is_active__c: true,
            agent_api_name__c: this.agentApiName
        };
        this.isLoading = true;
        try {
            await upsertRewardConfigs({ configs: [record] });
            this.showAddForm = false;
            this.newRule = { name: '', topicArea: '', points: 0 };
            this.showToast('Success', 'New rule added.', 'success');
            await this.loadData();
        } catch (error) {
            this.showToast('Error', 'Failed to add rule: ' + this.reduceError(error), 'error');
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