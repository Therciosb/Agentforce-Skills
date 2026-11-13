import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import generateSkill from '@salesforce/apex/Agent_Skill_Builder.generateSkill';

const TYPE_OPTIONS = [
    { label: 'Skill', value: 'Skill' },
    { label: 'Workflow', value: 'Workflow' },
    { label: 'Core skill', value: 'Core_Skill' },
    { label: 'Role', value: 'Role' }
];

export default class SkillBuilder extends NavigationMixin(LightningElement) {
    @track skillType = 'Skill';
    @track intent = '';
    contentVersionId;
    uploadedName;
    loading = false;
    typeOptions = TYPE_OPTIONS;

    get acceptedFormats() {
        return ['.txt', '.md', '.markdown', '.html', '.csv', '.xml'];
    }
    get generateDisabled() {
        return this.loading || !this.intent || this.intent.trim().length === 0;
    }

    handleType(e) { this.skillType = e.detail.value; }
    handleIntent(e) { this.intent = e.target.value; }

    handleUpload(event) {
        const files = event.detail.files;
        if (files && files.length > 0) {
            this.contentVersionId = files[0].contentVersionId;
            this.uploadedName = files[0].name;
        }
    }

    async handleGenerate() {
        this.loading = true;
        try {
            const res = await generateSkill({
                intent: this.intent,
                skillType: this.skillType,
                contentVersionId: this.contentVersionId
            });
            if (res.success) {
                if (res.warnings) {
                    this.toast('Draft created with notes', res.warnings, 'warning');
                } else {
                    this.toast('Draft skill created', res.name, 'success');
                }
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: res.recordId,
                        objectApiName: 'Agent_Skills_Repo__c',
                        actionName: 'view'
                    }
                });
            } else {
                this.toast('Could not generate skill', res.warnings || 'Unknown error', 'error');
            }
        } catch (e) {
            this.toast('Error', (e.body && e.body.message) || 'Generation failed', 'error');
        } finally {
            this.loading = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
