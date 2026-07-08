import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const OBJECT_API_NAME = 'Agent_Skills_Repo__c';
const LIST_VIEW_NAME = 'All';

export default class AgentSkillsUtilityBar extends NavigationMixin(LightningElement) {
    @api label = 'Agent Skills';
    handleMenuSelect(event) {
        const value = event.detail.value;
        switch (value) {
            case 'new':
                this.navigateToNewRecord();
                break;
            case 'import':
                this.navigateToImport();
                break;
            case 'export':
                this.navigateToExport();
                break;
            case 'bulkEdit':
                this.navigateToBulkEdit();
                break;
            default:
                break;
        }
    }

    navigateToNewRecord() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: OBJECT_API_NAME,
                actionName: 'new'
            }
        });
    }

    navigateToImport() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: OBJECT_API_NAME,
                actionName: 'list'
            },
            state: {
                filterName: LIST_VIEW_NAME
            }
        });
    }

    navigateToExport() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: OBJECT_API_NAME,
                actionName: 'list'
            },
            state: {
                filterName: LIST_VIEW_NAME
            }
        });
    }

    navigateToBulkEdit() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: OBJECT_API_NAME,
                actionName: 'list'
            },
            state: {
                filterName: LIST_VIEW_NAME
            }
        });
    }
}
