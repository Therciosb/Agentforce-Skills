import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import REFERENCES from '@salesforce/schema/Agent_Skills_Repo__c.References__c';
import getReferenceOptions from '@salesforce/apex/Agent_Skill_DependencyProvider.getReferenceOptions';
import saveReferences from '@salesforce/apex/Agent_Skill_DependencyProvider.saveReferences';

export default class SkillReferencesEditor extends LightningElement {
    @api recordId;
    selected = [];
    saving = false;
    _optionsWire;
    _recordWire;
    _initialized = false;

    @wire(getRecord, { recordId: '$recordId', fields: [REFERENCES] })
    wiredRecord(result) {
        this._recordWire = result;
        if (result.data && !this._initialized) {
            const raw = getFieldValue(result.data, REFERENCES);
            this.selected = raw
                ? raw.split(',').map((r) => r.trim()).filter((r) => r.length > 0)
                : [];
            this._initialized = true;
        }
    }

    @wire(getReferenceOptions, { recordId: '$recordId' })
    wiredOptions(result) {
        this._optionsWire = result;
    }

    get options() {
        const data = this._optionsWire && this._optionsWire.data;
        if (!data) {
            return [];
        }
        return data.map((o) => ({ label: o.name, value: o.name }));
    }

    get hasOptions() {
        return this.options.length > 0;
    }

    get noOptions() {
        return this._optionsWire && this._optionsWire.data && this.options.length === 0;
    }

    handleChange(event) {
        this.selected = event.detail.value;
    }

    async handleSave() {
        this.saving = true;
        try {
            await saveReferences({ recordId: this.recordId, names: this.selected });
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            if (this._recordWire) {
                await refreshApex(this._recordWire);
            }
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'References saved',
                    message: 'The dependency tree has been updated.',
                    variant: 'success'
                })
            );
        } catch (e) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not save references',
                    message: (e.body && e.body.message) || 'Unknown error',
                    variant: 'error'
                })
            );
        } finally {
            this.saving = false;
        }
    }
}
