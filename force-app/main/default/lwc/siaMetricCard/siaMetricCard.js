import { LightningElement, api } from 'lwc';

export default class SiaMetricCard extends LightningElement {
    @api label = '';
    @api value = 0;
    @api subtitle = '';
    @api format = 'number'; // number, percent, decimal
    @api delta;
    @api trend; // 'up', 'down', or 'flat'

    get formattedValue() {
        if (this.value === null || this.value === undefined) return '--';
        switch (this.format) {
            case 'percent':
                return `${Number(this.value).toFixed(1)}%`;
            case 'decimal':
                return Number(this.value).toFixed(2);
            default:
                return String(this.value);
        }
    }

    get hasDelta() { return this.delta !== undefined && this.delta !== null; }
    get deltaClass() {
        const base = 'slds-badge ';
        if (this.trend === 'up') return base + 'slds-theme_success';
        if (this.trend === 'down') return base + 'slds-theme_warning';
        return base;
    }
}