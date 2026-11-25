import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listBindings from '@salesforce/apex/Agent_Skill_Binding_Controller.listBindings';
import getBinding from '@salesforce/apex/Agent_Skill_Binding_Controller.getBinding';
import listWireableSkills from '@salesforce/apex/Agent_Skill_Binding_Controller.listWireableSkills';
import listOrgAgents from '@salesforce/apex/Agent_Skill_Binding_Controller.listOrgAgents';
import saveBinding from '@salesforce/apex/Agent_Skill_Binding_Controller.saveBinding';
import deleteBinding from '@salesforce/apex/Agent_Skill_Binding_Controller.deleteBinding';
import previewState from '@salesforce/apex/Agent_Skill_Binding_Controller.previewState';
import getScriptSnippet from '@salesforce/apex/Agent_Skill_Binding_Controller.getScriptSnippet';

const STATUS_OPTIONS = [
    { label: 'Active', value: 'Active' },
    { label: 'Inactive', value: 'Inactive' }
];
const ROLE_MODE_OPTIONS = [{ label: 'Always', value: 'Always' }];
const SKILL_MODE_OPTIONS = [
    { label: 'Always', value: 'Always' },
    { label: 'Selectable', value: 'Selectable' },
    { label: 'Default', value: 'Default' }
];
const TYPE_BADGE = { Role: 'Role', Core_Skill: 'Core', Skill: 'Skill' };

function errorMessage(error) {
    return (error && error.body && error.body.message) || (error && error.message) || 'Something went wrong.';
}

function defaultMode(name) {
    return name.startsWith('skill-') ? 'Selectable' : 'Always';
}

export default class SkillAgentWiring extends LightningElement {
    statusOptions = STATUS_OPTIONS;
    bindings = [];
    skills = [];
    orgAgents = [];
    selectedId;
    draft;
    dirty = false;
    saving = false;
    loadingDetail = false;
    error;
    preview;
    previewing = false;
    previewRequest = '';
    snippet;
    _wiredBindings;

    @wire(listBindings)
    wiredBindings(result) {
        this._wiredBindings = result;
        if (result.data) {
            this.bindings = result.data;
        } else if (result.error) {
            this.error = errorMessage(result.error);
        }
    }

    @wire(listWireableSkills, { locale: '$draftLocale' })
    wiredSkills({ data, error }) {
        if (data) {
            this.skills = data;
        } else if (error) {
            this.error = errorMessage(error);
        }
    }

    @wire(listOrgAgents)
    wiredAgents({ data }) {
        if (data) {
            this.orgAgents = data;
        }
    }

    get draftLocale() {
        return (this.draft && this.draft.locale) || 'en-US';
    }

    get bindingRows() {
        return this.bindings.map((b) => ({
            ...b,
            cssClass: b.id === this.selectedId ? 'agent agent--selected' : 'agent',
            isInactive: b.status !== 'Active'
        }));
    }

    get hasBindings() {
        return this.bindings.length > 0;
    }

    get agentOptions() {
        return this.orgAgents.map((a) => ({ label: `${a.label} (${a.developerName})`, value: a.developerName }));
    }

    get hasOrgAgents() {
        return this.orgAgents.length > 0;
    }

    get skillOptions() {
        const known = new Set(this.skills.map((s) => s.name));
        const options = this.skills.map((s) => ({ label: `${s.name} · ${TYPE_BADGE[s.type] || s.type}`, value: s.name }));
        // keep wired names that are no longer active so they can be seen and removed
        (this.draft ? this.draft.items : []).forEach((i) => {
            if (!known.has(i.skillName)) {
                options.push({ label: `${i.skillName} · not active`, value: i.skillName });
            }
        });
        return options;
    }

    get wiredNames() {
        return this.draft ? this.draft.items.map((i) => i.skillName) : [];
    }

    get itemRows() {
        if (!this.draft) {
            return [];
        }
        const byName = new Map(this.skills.map((s) => [s.name, s]));
        return this.draft.items.map((i, idx) => {
            const meta = byName.get(i.skillName);
            const isSkill = i.skillName.startsWith('skill-');
            return {
                ...i,
                key: i.skillName,
                index: idx,
                position: idx + 1,
                badge: meta ? TYPE_BADGE[meta.type] || meta.type : 'Not active',
                badgeClass: meta ? 'badge' : 'badge badge--warn',
                whenToUse: meta ? meta.whenToUse : 'No active record with this name in this locale.',
                modeOptions: isSkill ? SKILL_MODE_OPTIONS : ROLE_MODE_OPTIONS,
                isFirst: idx === 0,
                isLast: idx === this.draft.items.length - 1
            };
        });
    }

    get hasItems() {
        return this.draft && this.draft.items.length > 0;
    }

    get isNew() {
        return this.draft && !this.draft.id;
    }

    get saveDisabled() {
        return this.saving || !this.dirty;
    }

    get previewDisabled() {
        return this.previewing || this.isNew || this.dirty;
    }

    get previewHint() {
        if (this.isNew || this.dirty) {
            return 'Save to preview what the agent receives.';
        }
        return '';
    }

    get previewChars() {
        return this.preview && this.preview.skill_instructions ? this.preview.skill_instructions.length : 0;
    }

    handleSelect(event) {
        this.loadBinding(event.currentTarget.dataset.id);
    }

    async loadBinding(id) {
        this.selectedId = id;
        this.loadingDetail = true;
        this.preview = undefined;
        this.snippet = undefined;
        this.error = undefined;
        try {
            const detail = await getBinding({ bindingId: id });
            this.draft = JSON.parse(JSON.stringify(detail));
            this.draft.items = this.draft.items || [];
            this.dirty = false;
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.loadingDetail = false;
        }
    }

    handleNew() {
        this.selectedId = undefined;
        this.preview = undefined;
        this.snippet = undefined;
        this.error = undefined;
        this.draft = { id: null, name: '', agentName: '', status: 'Active', locale: 'en-US', description: '', items: [] };
        this.dirty = true;
    }

    handleField(event) {
        const field = event.target.dataset.field;
        this.draft = { ...this.draft, [field]: event.detail.value !== undefined ? event.detail.value : event.target.value };
        this.dirty = true;
    }

    handlePickAgent(event) {
        const developerName = event.detail.value;
        const agent = this.orgAgents.find((a) => a.developerName === developerName);
        this.draft = {
            ...this.draft,
            agentName: developerName,
            name: this.draft.name || (agent ? agent.label : developerName)
        };
        this.dirty = true;
    }

    handleSkillsChange(event) {
        const selected = event.detail.value;
        const current = new Map(this.draft.items.map((i) => [i.skillName, i]));
        const kept = this.draft.items.filter((i) => selected.includes(i.skillName));
        selected.forEach((name) => {
            if (!current.has(name)) {
                kept.push({ skillName: name, mode: defaultMode(name), order: null });
            }
        });
        this.setItems(kept);
    }

    handleMode(event) {
        const idx = Number(event.target.dataset.index);
        const items = this.draft.items.map((i, n) => (n === idx ? { ...i, mode: event.detail.value } : i));
        this.setItems(items);
    }

    handleMove(event) {
        const idx = Number(event.currentTarget.dataset.index);
        const target = idx + Number(event.currentTarget.dataset.step);
        const items = [...this.draft.items];
        [items[idx], items[target]] = [items[target], items[idx]];
        this.setItems(items);
    }

    handleRemove(event) {
        const idx = Number(event.currentTarget.dataset.index);
        this.setItems(this.draft.items.filter((_, n) => n !== idx));
    }

    setItems(items) {
        this.draft = { ...this.draft, items: items.map((i, n) => ({ ...i, order: n + 1 })) };
        this.dirty = true;
    }

    async handleSave() {
        this.saving = true;
        this.error = undefined;
        try {
            const id = await saveBinding({ payloadJson: JSON.stringify(this.draft) });
            await refreshApex(this._wiredBindings);
            this.toast('Saved', `Skill wiring for ${this.draft.agentName} saved.`, 'success');
            await this.loadBinding(id);
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.saving = false;
        }
    }

    async handleDelete() {
        // eslint-disable-next-line no-alert
        if (!window.confirm(`Delete the skill wiring for ${this.draft.agentName}? The agent will load no skills.`)) {
            return;
        }
        try {
            await deleteBinding({ bindingId: this.draft.id });
            this.draft = undefined;
            this.selectedId = undefined;
            await refreshApex(this._wiredBindings);
            this.toast('Deleted', 'Skill wiring deleted.', 'success');
        } catch (e) {
            this.error = errorMessage(e);
        }
    }

    handlePreviewRequest(event) {
        this.previewRequest = event.target.value;
    }

    async handlePreview() {
        this.previewing = true;
        try {
            this.preview = await previewState({ agentName: this.draft.agentName, requestedSkills: this.previewRequest });
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.previewing = false;
        }
    }

    async handleSnippet() {
        try {
            this.snippet = await getScriptSnippet({ agentName: this.draft.agentName });
        } catch (e) {
            this.error = errorMessage(e);
        }
    }

    async handleCopy() {
        try {
            await navigator.clipboard.writeText(this.snippet);
            this.toast('Copied', 'Agent Script snippet copied to the clipboard.', 'success');
        } catch (e) {
            this.toast('Copy failed', 'Select the snippet text and copy it manually.', 'warning');
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
