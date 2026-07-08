import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRegisteredAgents from '@salesforce/apex/SiaConfigController.getRegisteredAgents';
import getAesTrends from '@salesforce/apex/SiaMetricsController.getAesTrends';
import getAgentSummaries from '@salesforce/apex/SiaMetricsController.getAgentSummaries';

const COLORS = ['#0D9488', '#0176d3', '#9b59b6', '#e67e22', '#e74c3c', '#2ecc71', '#3498db', '#f39c12'];

const SUMMARY_COLUMNS = [
    { label: 'Agent', fieldName: 'agentApiName', type: 'text' },
    { label: 'AES', fieldName: 'aesAvg', type: 'number' },
    { label: 'Improvement %', fieldName: 'improvementRate', type: 'number' },
    { label: 'Yield %', fieldName: 'yield', type: 'number' },
    { label: 'Utilization %', fieldName: 'utilization', type: 'number' },
    { label: 'Accuracy %', fieldName: 'accuracy', type: 'number' }
];

export default class SiaAgentComparison extends LightningElement {
    @track agentOptions = [];
    @track selectedAgents = [];
    @track trendData = {};
    @track summaries = [];
    @track legendItems = [];
    isLoading = false;
    periodWeeks = 12;
    _chartDrawn = false;

    summaryColumns = SUMMARY_COLUMNS;

    @wire(getRegisteredAgents)
    wiredAgents({ data, error }) {
        if (data) {
            this.agentOptions = data.map(name => ({ label: name, value: name }));
            if (this.selectedAgents.length === 0 && data.length > 0) {
                this.selectedAgents = [...data];
                this.loadComparisonData();
            }
        } else if (error) {
            console.error('Error loading agents', error);
        }
    }

    get hasSelection() {
        return !this.isLoading && this.selectedAgents.length > 0;
    }

    get noSelection() {
        return !this.isLoading && this.selectedAgents.length === 0;
    }

    get hasSummaries() {
        return this.summaries && this.summaries.length > 0;
    }

    handleAgentSelection(event) {
        this.selectedAgents = event.detail.value;
        this._chartDrawn = false;
        if (this.selectedAgents.length > 0) {
            this.loadComparisonData();
        }
    }

    async loadComparisonData() {
        this.isLoading = true;
        this._chartDrawn = false;
        try {
            const [trends, sums] = await Promise.all([
                getAesTrends({ agentApiNames: this.selectedAgents, periodWeeks: this.periodWeeks }),
                getAgentSummaries({ agentApiNames: this.selectedAgents })
            ]);
            this.trendData = trends;
            this.summaries = sums;
            this.legendItems = this.selectedAgents.map((agent, idx) => ({
                agent,
                dotStyle: `background-color: ${COLORS[idx % COLORS.length]}`
            }));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error loading comparison data',
                message: error?.body?.message || 'Unknown error',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    renderedCallback() {
        if (!this._chartDrawn && this.trendData && Object.keys(this.trendData).length > 0) {
            // Only latch _chartDrawn when the draw actually ran. The canvas lives under an
            // lwc:if and is briefly removed/unsized on agent or period changes; latching
            // unconditionally would skip the real redraw and blank the chart.
            const drawn = this.drawComparisonChart();
            if (drawn) this._chartDrawn = true;
        }
    }

    drawComparisonChart() {
        const canvas = this.refs.comparisonCanvas;
        if (!canvas) return false;
        const ctx = canvas.getContext('2d');
        const width = canvas.parentElement.clientWidth || 0;
        if (!width) return false;
        const height = 250;
        canvas.width = width;
        canvas.height = height;

        const padding = { top: 20, right: 20, bottom: 30, left: 40 };
        const chartWidth = width - padding.left - padding.right;
        const chartHeight = height - padding.top - padding.bottom;

        ctx.clearRect(0, 0, width, height);

        // Axes
        ctx.strokeStyle = '#e5e5e5';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(padding.left, padding.top);
        ctx.lineTo(padding.left, height - padding.bottom);
        ctx.lineTo(width - padding.right, height - padding.bottom);
        ctx.stroke();

        // Dynamic Y-axis: AES is cumulative (no fixed ceiling). Scale to the peak across
        // ALL agents' series so every line stays in-frame and remains comparable.
        const yMax = this.computeYAxisMax();

        // Y-axis labels (0 .. yMax)
        ctx.fillStyle = '#706e6b';
        ctx.font = '11px sans-serif';
        ctx.textAlign = 'right';
        for (let i = 0; i <= 4; i++) {
            const val = (yMax / 4) * i;
            const y = height - padding.bottom - (val / yMax) * chartHeight;
            ctx.fillText(this.formatAxisLabel(val), padding.left - 5, y + 4);
        }

        // Draw a line for each agent
        const agents = Object.keys(this.trendData);
        agents.forEach((agent, agentIdx) => {
            const points = this.trendData[agent];
            if (!points || points.length < 2) return;
            const stepX = chartWidth / (points.length - 1);

            ctx.beginPath();
            ctx.strokeStyle = COLORS[agentIdx % COLORS.length];
            ctx.lineWidth = 2;
            ctx.lineJoin = 'round';

            points.forEach((point, idx) => {
                const x = padding.left + idx * stepX;
                const y = height - padding.bottom - (point.aesAvg / yMax) * chartHeight;
                if (idx === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            });
            ctx.stroke();
        });
        return true;
    }

    // "Nice" Y-axis max across every agent's series; cumulative AES has no fixed ceiling.
    computeYAxisMax() {
        let peak = 0;
        Object.keys(this.trendData || {}).forEach((agent) => {
            (this.trendData[agent] || []).forEach((p) => {
                peak = Math.max(peak, Number(p.aesAvg) || 0);
            });
        });
        if (peak <= 100) return 100;
        const target = peak * 1.1;
        const magnitude = Math.pow(10, Math.floor(Math.log10(target)));
        const steps = [1, 2, 2.5, 5, 10];
        for (const s of steps) {
            const candidate = s * magnitude;
            if (candidate >= target) return candidate;
        }
        return 10 * magnitude;
    }

    formatAxisLabel(val) {
        return Number.isInteger(val) ? String(val) : val.toFixed(1);
    }
}