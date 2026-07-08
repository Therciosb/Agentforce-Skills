import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getThresholdConfig from '@salesforce/apex/SiaConfigController.getThresholdConfig';
import upsertThresholdConfig from '@salesforce/apex/SiaConfigController.upsertThresholdConfig';

export default class SiaThresholdEditor extends LightningElement {
    _agentApiName;

    @api
    get agentApiName() { return this._agentApiName; }
    set agentApiName(value) {
        if (value && value !== this._agentApiName) {
            this._agentApiName = value;
            this.loadData();
        }
    }

    config = {};
    isLoading = false;

    get hasNoAgent() {
        return !this.agentApiName;
    }

    async loadData() {
        if (!this.agentApiName) return;
        try {
            this.isLoading = true;
            const result = await getThresholdConfig({ agentApiName: this.agentApiName });
            this.config = { ...result };
        } catch (error) {
            this.showToast('Error', 'Failed to load threshold config: ' + this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleChange(event) {
        const field = event.target.dataset.field;
        this.config = { ...this.config, [field]: event.target.value };
    }

    handleToggleChange(event) {
        const field = event.target.dataset.field;
        this.config = { ...this.config, [field]: event.target.checked };
    }

    async handleSave() {
        try {
            this.isLoading = true;
            const record = {
                ...this.config,
                agent_api_name__c: this.agentApiName
            };
            await upsertThresholdConfig({ config: record });
            this.showToast('Success', 'Threshold configuration saved.', 'success');
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