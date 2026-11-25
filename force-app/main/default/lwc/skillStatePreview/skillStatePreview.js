import { LightningElement, api } from 'lwc';
import getWiringSummary from '@salesforce/apex/Agent_Skill_Binding_Controller.getWiringSummary';
import previewState from '@salesforce/apex/Agent_Skill_Binding_Controller.previewState';

// lightning-combobox cannot select an empty value, so the agent-level wiring gets a stand-in value.
const AGENT_LEVEL = '__agent__';

function errorMessage(error) {
    return (error && error.body && error.body.message) || (error && error.message) || 'Something went wrong.';
}

function toValue(subagent) {
    return subagent ? subagent : AGENT_LEVEL;
}

export default class SkillStatePreview extends LightningElement {
    @api disabledReason;

    _agentName;
    _subagent = '';
    _subagents = [];
    summary;
    selectedSkills = [];
    preview;
    loading = false;
    previewing = false;
    error;

    @api
    get agentName() {
        return this._agentName;
    }
    set agentName(value) {
        if (value !== this._agentName) {
            this._agentName = value;
            this.reload();
        }
    }

    // Subagent developer name; blank selects the agent-level wiring.
    @api
    get subagent() {
        return this._subagent;
    }
    set subagent(value) {
        this.applySubagent(value);
    }

    // Subagent names to offer; '' stands for the agent-level wiring.
    @api
    get subagents() {
        return this._subagents;
    }
    set subagents(value) {
        this._subagents = value || [];
    }

    get subagentOptions() {
        const names = new Set(this._subagents);
        names.add(this._subagent);
        return [...names]
            .sort((a, b) => (a === '' ? -1 : b === '' ? 1 : a.localeCompare(b)))
            .map((name) => ({ label: name || 'All subagents (agent level)', value: toValue(name) }));
    }

    get subagentValue() {
        return toValue(this._subagent);
    }

    get subagentLabel() {
        return this._subagent || 'all subagents (agent level)';
    }

    get fallbackNotice() {
        if (!this.summary || !this.summary.found || !this._subagent || this.summary.bindingSubagent) {
            return '';
        }
        return `${this._subagent} has no wiring of its own, so it uses the agent-level wiring.`;
    }

    get notWired() {
        return this.summary && !this.summary.found;
    }

    get skillOptions() {
        if (!this.summary) {
            return [];
        }
        const defaults = new Set(this.summary.defaults);
        return this.summary.selectable.map((name) => ({ label: defaults.has(name) ? `${name} (default)` : name, value: name }));
    }

    get hasSkillOptions() {
        return this.skillOptions.length > 0;
    }

    get alwaysDisplay() {
        return this.summary && this.summary.always.length ? this.summary.always.join(', ') : 'None';
    }

    get selectionHint() {
        return this.selectedSkills.length ? '' : 'Nothing selected: the agent loads its default skills.';
    }

    get previewDisabled() {
        return this.previewing || this.loading || !!this.disabledReason || !this._agentName || this.notWired;
    }

    get previewChars() {
        return this.preview && this.preview.skill_instructions ? this.preview.skill_instructions.length : 0;
    }

    get previewTools() {
        const tools = (this.preview && this.preview.tools) || {};
        const enabled = Object.keys(tools)
            .filter((t) => tools[t])
            .sort();
        return enabled.length ? enabled.join(', ') : 'None';
    }

    @api
    refresh() {
        this.reload();
    }

    applySubagent(value) {
        const next = value || '';
        if (next !== this._subagent) {
            this._subagent = next;
            this.reload();
        }
    }

    async reload() {
        const request = (this._request || 0) + 1;
        this._request = request;
        this.summary = undefined;
        this.preview = undefined;
        this.selectedSkills = [];
        this.error = undefined;
        if (!this._agentName) {
            return;
        }
        this.loading = true;
        try {
            const summary = await getWiringSummary({ agentName: this._agentName, subagentName: this._subagent });
            if (request === this._request) {
                this.summary = summary;
                this.selectedSkills = [...(summary.defaults || [])];
            }
        } catch (e) {
            if (request === this._request) {
                this.error = errorMessage(e);
            }
        } finally {
            if (request === this._request) {
                this.loading = false;
            }
        }
    }

    handleSubagent(event) {
        const value = event.detail.value === AGENT_LEVEL ? '' : event.detail.value;
        this.applySubagent(value);
        this.dispatchEvent(new CustomEvent('subagentchange', { detail: { subagent: value } }));
    }

    handleSkills(event) {
        this.selectedSkills = event.detail.value;
        this.preview = undefined;
    }

    async handlePreview() {
        this.previewing = true;
        this.error = undefined;
        try {
            this.preview = await previewState({
                agentName: this._agentName,
                subagentName: this._subagent,
                requestedSkills: this.selectedSkills.join(',')
            });
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.previewing = false;
        }
    }
}
