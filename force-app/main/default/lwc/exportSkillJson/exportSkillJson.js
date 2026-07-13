import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import NAME_FIELD from '@salesforce/schema/Agent_Skills_Repo__c.Name';
import DESCRIPTION_FIELD from '@salesforce/schema/Agent_Skills_Repo__c.Description__c';
import TYPE_FIELD from '@salesforce/schema/Agent_Skills_Repo__c.Type__c';
import STATUS_FIELD from '@salesforce/schema/Agent_Skills_Repo__c.Status__c';
import INSTRUCTION_BODY_FIELD from '@salesforce/schema/Agent_Skills_Repo__c.InstructionBody__c';
import WHEN_TO_USE_FIELD from '@salesforce/schema/Agent_Skills_Repo__c.WhenToUse__c';
import REFERENCES_FIELD from '@salesforce/schema/Agent_Skills_Repo__c.References__c';
import EXTERNAL_ID_FIELD from '@salesforce/schema/Agent_Skills_Repo__c.ExternalId__c';
import VERSION_FIELD from '@salesforce/schema/Agent_Skills_Repo__c.Version__c';
import LOCALE_FIELD from '@salesforce/schema/Agent_Skills_Repo__c.Locale__c';

const FIELDS = [
    NAME_FIELD,
    DESCRIPTION_FIELD,
    TYPE_FIELD,
    STATUS_FIELD,
    INSTRUCTION_BODY_FIELD,
    WHEN_TO_USE_FIELD,
    REFERENCES_FIELD,
    EXTERNAL_ID_FIELD,
    VERSION_FIELD,
    LOCALE_FIELD
];

export default class ExportSkillJson extends LightningElement {
    @api recordId;
    _recordData;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ error, data }) {
        if (data) {
            this._recordData = data;
        } else if (error) {
            this._recordData = null;
        }
    }

    @api invoke() {
        if (!this.recordId) {
            this.showError('No record selected');
            return Promise.resolve();
        }
        if (!this._recordData || !this._recordData.fields) {
            this.showError('Record data not loaded yet. Please try again.');
            return Promise.resolve();
        }
        const data = {};
        Object.keys(this._recordData.fields).forEach((key) => {
            const f = this._recordData.fields[key];
            if (f.displayValue !== undefined) {
                data[key] = f.displayValue;
            } else if (f.value !== undefined) {
                data[key] = f.value;
            }
        });
        const json = JSON.stringify(data, null, 2);
        const blob = new Blob([json], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        const name = (data.Name || data.name || this.recordId || 'skill').toString();
        a.download = `skill-${name.replace(/[^a-zA-Z0-9_.-]/g, '_')}.json`;
        a.click();
        URL.revokeObjectURL(url);
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Exported',
                message: 'Skill exported as JSON',
                variant: 'success'
            })
        );
        return Promise.resolve();
    }

    showError(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message,
                variant: 'error'
            })
        );
    }
}
