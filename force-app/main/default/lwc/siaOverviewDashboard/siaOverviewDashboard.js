import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAgentMetrics from '@salesforce/apex/SiaMetricsController.getAgentMetrics';
import getAesTrend from '@salesforce/apex/SiaMetricsController.getAesTrend';
import getKnowledgeHealth from '@salesforce/apex/SiaMetricsController.getKnowledgeHealth';

const CIRCUMFERENCE = 2 * Math.PI * 50; // r=50

export default class SiaOverviewDashboard extends LightningElement {
    _agentApiName;

    @api
    get agentApiName() { return this._agentApiName; }
    set agentApiName(value) {
        if (value && value !== this._agentApiName) {
            this._agentApiName = value;
            this.loadData();
        }
    }

    periodWeeks = '12';
    metrics = {};
    trendData = [];
    knowledgeHealth = {};
    isLoading = false;
    _chartDrawn = false;

    periodOptions = [
        { label: '4 Weeks', value: '4' },
        { label: '8 Weeks', value: '8' },
        { label: '12 Weeks', value: '12' },
        { label: '24 Weeks', value: '24' }
    ];

    get hasData() {
        return !this.isLoading && this.metrics && this.metrics.aesAvg !== undefined;
    }

    handlePeriodChange(event) {
        this.periodWeeks = event.detail.value;
        this.loadData();
    }

    async loadData() {
        if (!this.agentApiName) return;
        this.isLoading = true;
        this._chartDrawn = false;
        try {
            const [metricsResult, trendResult, healthResult] = await Promise.all([
                getAgentMetrics({ agentApiName: this.agentApiName, periodWeeks: parseInt(this.periodWeeks, 10) }),
                getAesTrend({ agentApiName: this.agentApiName, periodWeeks: parseInt(this.periodWeeks, 10) }),
                getKnowledgeHealth({ agentApiName: this.agentApiName })
            ]);
            this.metrics = metricsResult;
            this.trendData = trendResult;
            this.knowledgeHealth = healthResult;
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error loading metrics',
                message: error?.body?.message || 'Unknown error',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    renderedCallback() {
        if (!this._chartDrawn && this.trendData && this.trendData.length > 0) {
            // Only latch _chartDrawn when the draw actually ran. On a period change the
            // canvas is briefly removed (it lives under lwc:if={hasData}); a render can fire
            // while it's absent. If we latched unconditionally, the real redraw would be
            // skipped and the line would vanish for every view except the initial one.
            const drawn = this.drawTrendChart();
            if (drawn) this._chartDrawn = true;
        }
    }

    drawTrendChart() {
        const canvas = this.refs.trendCanvas;
        if (!canvas) return false;
        const ctx = canvas.getContext('2d');
        const width = canvas.parentElement.clientWidth || 0;
        // Canvas can be present but not yet laid out (width 0) right after the lwc:if
        // re-adds it on a period change. Bail and let the next render retry once sized.
        if (!width) return false;
        const height = 200;
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

        // Dynamic Y-axis: AES is now a cumulative score with no fixed ceiling, so scale
        // the axis to the data instead of a hardcoded 100. Round the max up to a "nice"
        // value and keep a sensible minimum so small/early datasets still render well.
        const yMax = this.computeYAxisMax();

        // Y-axis labels (0 .. yMax)
        ctx.fillStyle = '#706e6b';
        ctx.font = '11px sans-serif';
        ctx.textAlign = 'right';
        for (let i = 0; i <= 4; i++) {
            const val = (yMax / 4) * i;
            const y = height - padding.bottom - (val / yMax) * chartHeight;
            ctx.fillText(this.formatAxisLabel(val), padding.left - 5, y + 4);
            ctx.beginPath();
            ctx.strokeStyle = '#f3f3f3';
            ctx.moveTo(padding.left, y);
            ctx.lineTo(width - padding.right, y);
            ctx.stroke();
        }

        // Data line
        if (this.trendData.length < 2) return true;
        const stepX = chartWidth / (this.trendData.length - 1);

        ctx.beginPath();
        ctx.strokeStyle = '#0D9488';
        ctx.lineWidth = 2;
        ctx.lineJoin = 'round';

        this.trendData.forEach((point, idx) => {
            const x = padding.left + idx * stepX;
            const y = height - padding.bottom - (point.aesAvg / yMax) * chartHeight;
            if (idx === 0) ctx.moveTo(x, y);
            else ctx.lineTo(x, y);
        });
        ctx.stroke();

        // X-axis labels
        ctx.fillStyle = '#706e6b';
        ctx.textAlign = 'center';
        this.trendData.forEach((point, idx) => {
            if (idx % Math.ceil(this.trendData.length / 6) === 0 || idx === this.trendData.length - 1) {
                const x = padding.left + idx * stepX;
                ctx.fillText(point.week, x, height - 8);
            }
        });
        return true;
    }

    // Compute a "nice" Y-axis maximum for the cumulative AES trend. Scales to the data's
    // peak (with ~10% headroom), rounds up to a clean step, and never goes below 100 so
    // small/early datasets still render on a reasonable scale.
    computeYAxisMax() {
        const peak = (this.trendData || []).reduce(
            (m, p) => Math.max(m, Number(p.aesAvg) || 0),
            0
        );
        if (peak <= 100) return 100;
        const target = peak * 1.1; // headroom so the top point isn't on the edge
        const magnitude = Math.pow(10, Math.floor(Math.log10(target)));
        // round up to 1x, 2x, 2.5x, 5x, or 10x the magnitude
        const steps = [1, 2, 2.5, 5, 10];
        for (const s of steps) {
            const candidate = s * magnitude;
            if (candidate >= target) return candidate;
        }
        return 10 * magnitude;
    }

    // Y-axis tick label: integers shown plainly, fractional ticks to one decimal.
    formatAxisLabel(val) {
        return Number.isInteger(val) ? String(val) : val.toFixed(1);
    }

    // Coerce a metric value to a finite number. Apex Decimal values can arrive as strings
    // over the wire, so `value || 0` is not enough — `"12.5".toFixed` throws. Always Number().
    num(value) {
        const n = Number(value);
        return Number.isFinite(n) ? n : 0;
    }

    // AES Breakdown bar styles
    get goalBarStyle() {
        const pct = Math.min(100, (this.num(this.metrics?.goalScore) / 40) * 100);
        return `width: ${pct}%`;
    }
    get goalLabel() {
        return `${this.num(this.metrics?.goalScore).toFixed(1)} / 40`;
    }
    get efficiencyBarStyle() {
        const pct = Math.min(100, (this.num(this.metrics?.efficiencyScore) / 30) * 100);
        return `width: ${pct}%`;
    }
    get efficiencyLabel() {
        return `${this.num(this.metrics?.efficiencyScore).toFixed(1)} / 30`;
    }
    get learningBarStyle() {
        const pct = Math.min(100, (this.num(this.metrics?.learningScore) / 30) * 100);
        return `width: ${pct}%`;
    }
    get learningLabel() {
        return `${this.num(this.metrics?.learningScore).toFixed(1)} / 30`;
    }

    // Knowledge Health SVG dasharray
    get yieldPct() { return Math.round(this.knowledgeHealth?.yield || 0); }
    get utilizationPct() { return Math.round(this.knowledgeHealth?.utilization || 0); }
    get accuracyPct() { return Math.round(this.knowledgeHealth?.accuracy || 0); }

    get yieldDashStyle() {
        return this._ringStyle(this.yieldPct);
    }
    get utilizationDashStyle() {
        return this._ringStyle(this.utilizationPct);
    }
    get accuracyDashStyle() {
        return this._ringStyle(this.accuracyPct);
    }

    _ringStyle(percent) {
        const filled = (percent / 100) * CIRCUMFERENCE;
        return `stroke-dasharray: ${filled} ${CIRCUMFERENCE}`;
    }
}