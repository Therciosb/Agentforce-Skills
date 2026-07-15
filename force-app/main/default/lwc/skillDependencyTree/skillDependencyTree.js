import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTree from '@salesforce/apex/Agent_Skill_DependencyProvider.getTree';

export default class SkillDependencyTree extends NavigationMixin(LightningElement) {
    @api recordId;
    treeItems = [];
    error;
    loaded = false;

    @wire(getTree, { recordId: '$recordId' })
    wiredTree({ data, error }) {
        if (data) {
            this.treeItems = [this.toItem(data)];
            this.loaded = true;
            this.error = undefined;
        } else if (error) {
            this.error = (error.body && error.body.message) || 'Failed to load dependencies';
            this.loaded = true;
        }
    }

    toItem(node) {
        const meta = node.seen ? `${node.type} (already shown)` : node.type;
        return {
            label: node.label,
            name: node.name,
            metatext: node.status === 'missing' ? `${node.type} — missing/inactive` : meta,
            expanded: true,
            items: (node.children || []).map((c) => this.toItem(c))
        };
    }

    get hasTree() {
        return this.loaded && !this.error && this.treeItems.length > 0;
    }

    get showEmpty() {
        return this.loaded && !this.error && this.treeItems.length === 0;
    }

    handleSelect(event) {
        const name = event.detail.name;
        // navigate to the referenced skill record by unique Name
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Agent_Skills_Repo__c', actionName: 'list' },
            state: { filterName: 'Recent' }
        });
        // eslint-disable-next-line no-console
        console.log('Selected dependency:', name);
    }
}
