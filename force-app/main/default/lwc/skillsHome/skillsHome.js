import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSummary from '@salesforce/apex/Agent_Skills_Home_Controller.getSummary';

const TYPE_META = {
    Role: { badge: 'Role', icon: 'utility:user' },
    Core_Skill: { badge: 'Core', icon: 'utility:layers' },
    Skill: { badge: 'Skill', icon: 'utility:knowledge_base' },
    Workflow: { badge: 'Workflow', icon: 'utility:flow' }
};

export default class SkillsHome extends NavigationMixin(LightningElement) {
    summary;
    error;
    loading = true;

    @wire(getSummary)
    wiredSummary({ data, error }) {
        if (data) {
            this.summary = data;
            this.error = undefined;
        } else if (error) {
            this.error = (error.body && error.body.message) || 'Unable to load the skills overview.';
        }
        this.loading = false;
    }

    get hasData() {
        return !this.loading && !this.error && this.summary;
    }

    get isEmpty() {
        return this.hasData && this.summary.total === 0;
    }

    get typeCards() {
        if (!this.summary) {
            return [];
        }
        return this.summary.byType.map((t) => {
            const meta = TYPE_META[t.type] || { badge: t.label, icon: 'utility:record' };
            return {
                key: t.type,
                label: t.label,
                icon: meta.icon,
                total: t.total,
                active: t.active,
                caption: `${t.active} active`,
                muted: t.total === 0
            };
        });
    }

    get recentSkills() {
        if (!this.summary) {
            return [];
        }
        return this.summary.recent.map((r) => {
            const meta = TYPE_META[r.type] || { badge: r.type, icon: 'utility:record' };
            const isActive = r.status === 'active';
            return {
                ...r,
                badge: meta.badge,
                icon: meta.icon,
                statusClass: isActive
                    ? 'status-dot status-dot_active'
                    : 'status-dot status-dot_draft',
                statusLabel: isActive ? 'Active' : r.status
            };
        });
    }

    get draftBadge() {
        return this.summary && this.summary.draftTotal > 0 ? String(this.summary.draftTotal) : null;
    }

    handleOpen(event) {
        const recordId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Agent_Skills_Repo__c',
                actionName: 'view'
            }
        });
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Agent_Skills_Repo__c',
                actionName: 'list'
            },
            state: { filterName: 'Recent' }
        });
    }

    handleFocusBuilder() {
        const builder = this.template.querySelector('c-skill-builder');
        if (builder) {
            builder.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }
}
