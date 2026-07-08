import { LightningElement, wire } from 'lwc';
import getRegisteredAgents from '@salesforce/apex/SiaConfigController.getRegisteredAgents';

export default class SiaAgentSwitcher extends LightningElement {
    selectedAgent;
    agentOptions = [];

    @wire(getRegisteredAgents)
    wiredAgents({ data, error }) {
        if (data && data.length > 0) {
            this.agentOptions = data.map(name => ({
                label: name,
                value: name
            }));
            if (!this.selectedAgent) {
                this.selectedAgent = this.agentOptions[0].value;
                this.fireAgentChange();
            }
        } else if (error) {
            console.error('Error loading agents', error);
        }
    }

    get hasAgents() {
        return this.agentOptions.length > 0;
    }

    handleAgentChange(event) {
        this.selectedAgent = event.detail.value;
        this.fireAgentChange();
    }

    fireAgentChange() {
        this.dispatchEvent(new CustomEvent('agentchange', {
            detail: { agentApiName: this.selectedAgent },
            bubbles: true,
            composed: true
        }));
    }
}