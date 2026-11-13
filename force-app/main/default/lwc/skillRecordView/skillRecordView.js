import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import NAME from '@salesforce/schema/Agent_Skills_Repo__c.Name';
import TYPE from '@salesforce/schema/Agent_Skills_Repo__c.Type__c';
import STATUS from '@salesforce/schema/Agent_Skills_Repo__c.Status__c';
import VERSION from '@salesforce/schema/Agent_Skills_Repo__c.Version__c';
import LOCALE from '@salesforce/schema/Agent_Skills_Repo__c.Locale__c';
import PRIORITY from '@salesforce/schema/Agent_Skills_Repo__c.Priority__c';
import DESCRIPTION from '@salesforce/schema/Agent_Skills_Repo__c.Description__c';
import WHEN_TO_USE from '@salesforce/schema/Agent_Skills_Repo__c.WhenToUse__c';
import INSTRUCTION_BODY from '@salesforce/schema/Agent_Skills_Repo__c.InstructionBody__c';
import REFERENCES from '@salesforce/schema/Agent_Skills_Repo__c.References__c';

const FIELDS = [
    NAME, TYPE, STATUS, VERSION, LOCALE, PRIORITY,
    DESCRIPTION, WHEN_TO_USE, INSTRUCTION_BODY, REFERENCES
];

const TYPE_META = {
    Role: { label: 'Role', icon: 'utility:user' },
    Core_Skill: { label: 'Core skill', icon: 'utility:layers' },
    Skill: { label: 'Skill', icon: 'utility:knowledge_base' },
    Workflow: { label: 'Workflow', icon: 'utility:flow' }
};

export default class SkillRecordView extends LightningElement {
    @api recordId;
    record;
    error;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            this.record = data;
            this.error = undefined;
        } else if (error) {
            this.error = (error.body && error.body.message) || 'Unable to load this skill.';
        }
    }

    get loaded() {
        return this.record != null;
    }

    get name() {
        return getFieldValue(this.record, NAME);
    }

    get typeMeta() {
        const t = getFieldValue(this.record, TYPE);
        return TYPE_META[t] || { label: t || 'Record', icon: 'utility:record' };
    }

    get isActive() {
        return getFieldValue(this.record, STATUS) === 'active';
    }

    get statusLabel() {
        const s = getFieldValue(this.record, STATUS);
        return this.isActive ? 'Active' : s || 'Unknown';
    }

    get statusClass() {
        return this.isActive ? 'pill pill--active' : 'pill pill--draft';
    }

    get metaItems() {
        return [
            { key: 'version', label: 'Version', value: getFieldValue(this.record, VERSION) || '—' },
            { key: 'locale', label: 'Locale', value: getFieldValue(this.record, LOCALE) || '—' },
            {
                key: 'priority',
                label: 'Priority',
                value: this.formatPriority(getFieldValue(this.record, PRIORITY))
            }
        ];
    }

    formatPriority(p) {
        return p === null || p === undefined ? '—' : String(p);
    }

    get description() {
        return getFieldValue(this.record, DESCRIPTION);
    }

    get whenToUse() {
        return getFieldValue(this.record, WHEN_TO_USE);
    }

    get instructionBody() {
        return getFieldValue(this.record, INSTRUCTION_BODY);
    }

    get references() {
        const raw = getFieldValue(this.record, REFERENCES);
        if (!raw) {
            return [];
        }
        return raw
            .split(',')
            .map((r) => r.trim())
            .filter((r) => r.length > 0)
            .map((r) => ({ name: r }));
    }

    get hasReferences() {
        return this.references.length > 0;
    }
}
