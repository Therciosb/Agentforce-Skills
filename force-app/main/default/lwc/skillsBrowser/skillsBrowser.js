import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import listSkills from '@salesforce/apex/Agent_Skills_Home_Controller.listSkills';

const FILTERS = [
    { label: 'All', value: 'All' },
    { label: 'Roles', value: 'Role' },
    { label: 'Core skills', value: 'Core_Skill' },
    { label: 'Skills', value: 'Skill' },
    { label: 'Workflows', value: 'Workflow' }
];

const TYPE_META = {
    Role: { badge: 'Role', icon: 'utility:user' },
    Core_Skill: { badge: 'Core', icon: 'utility:layers' },
    Skill: { badge: 'Skill', icon: 'utility:knowledge_base' },
    Workflow: { badge: 'Workflow', icon: 'utility:flow' }
};

export default class SkillsBrowser extends NavigationMixin(LightningElement) {
    filters = FILTERS;
    activeFilter = 'All';
    searchTerm = '';
    rows = [];
    error;
    loading = true;
    _wired;
    _debounce;

    @wire(listSkills, { searchTerm: '$searchTerm', typeFilter: '$activeFilter' })
    wiredList(result) {
        this._wired = result;
        const { data, error } = result;
        if (data) {
            this.rows = data;
            this.error = undefined;
        } else if (error) {
            this.error = (error.body && error.body.message) || 'Unable to load skills.';
        }
        this.loading = false;
    }

    get filterButtons() {
        return this.filters.map((f) => ({
            ...f,
            isActive: f.value === this.activeFilter,
            cssClass: f.value === this.activeFilter ? 'seg seg--active' : 'seg'
        }));
    }

    get items() {
        return this.rows.map((r) => {
            const meta = TYPE_META[r.type] || { badge: r.type, icon: 'utility:record' };
            const isActive = r.status === 'active';
            return {
                ...r,
                badge: meta.badge,
                icon: meta.icon,
                dotClass: isActive ? 'dot dot--active' : 'dot dot--draft',
                statusLabel: isActive ? 'Active' : r.status
            };
        });
    }

    get resultCount() {
        return this.rows.length;
    }

    get isEmpty() {
        return !this.loading && !this.error && this.rows.length === 0;
    }

    handleFilter(event) {
        this.activeFilter = event.currentTarget.dataset.value;
    }

    handleSearch(event) {
        const value = event.target.value;
        window.clearTimeout(this._debounce);
        // debounce so the cacheable wire re-runs only after the user pauses
        this._debounce = setTimeout(() => {
            this.searchTerm = value;
        }, 300);
    }

    handleOpen(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.currentTarget.dataset.id,
                objectApiName: 'Agent_Skills_Repo__c',
                actionName: 'view'
            }
        });
    }

    handleNew() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Agent_Skills_Repo__c',
                actionName: 'new'
            }
        });
    }

    handleRefresh() {
        if (this._wired) {
            this.loading = true;
            refreshApex(this._wired).finally(() => {
                this.loading = false;
            });
        }
    }
}
