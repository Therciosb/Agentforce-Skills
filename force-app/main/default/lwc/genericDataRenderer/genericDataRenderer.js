import { LightningElement, api } from 'lwc';

export default class GenericDataRenderer extends LightningElement {
    @api value;

    get hasError() {
        return this.value && this.value.success === false && this.value.errorMessage;
    }

    get errorMessage() {
        return this.value?.errorMessage || '';
    }

    get hasData() {
        return this.value && this.value.success === true && this.value.jsonData;
    }

    get displayType() {
        return (this.value?.displayType || '').toLowerCase();
    }

    get isTable() {
        return this.displayType === 'table';
    }

    get isCard() {
        return this.displayType === 'card';
    }

    get isList() {
        return this.displayType === 'list';
    }

    get isKeyValue() {
        return this.displayType === 'key-value';
    }

    get tableColumns() {
        if (!this.hasData || !this.isTable) return [];
        try {
            const parsed = JSON.parse(this.value.jsonData);
            const columns = parsed.columns || [];
            return columns.map((col, idx) => ({
                label: col,
                fieldName: `col${idx}`,
                type: 'text'
            }));
        } catch {
            return [];
        }
    }

    get tableData() {
        if (!this.hasData || !this.isTable) return [];
        try {
            const parsed = JSON.parse(this.value.jsonData);
            const columns = parsed.columns || [];
            const rows = parsed.rows || [];
            return rows.map((row, rowIdx) => {
                const obj = { id: `row-${rowIdx}` };
                columns.forEach((_, colIdx) => {
                    obj[`col${colIdx}`] = row[colIdx] != null ? String(row[colIdx]) : '';
                });
                return obj;
            });
        } catch {
            return [];
        }
    }

    get cardTitle() {
        if (!this.hasData || !this.isCard) return '';
        try {
            const parsed = JSON.parse(this.value.jsonData);
            return parsed.title || '';
        } catch {
            return '';
        }
    }

    get cardFields() {
        if (!this.hasData || !this.isCard) return [];
        try {
            const parsed = JSON.parse(this.value.jsonData);
            const fields = parsed.fields || [];
            return fields.map((f, idx) => ({
                key: `field-${idx}`,
                label: f.label || '',
                value: f.value != null ? String(f.value) : ''
            }));
        } catch {
            return [];
        }
    }

    get listItems() {
        if (!this.hasData || !this.isList) return [];
        try {
            const parsed = JSON.parse(this.value.jsonData);
            const items = parsed.items || [];
            return items.map((item, idx) => ({
                key: `item-${idx}`,
                value: item != null ? String(item) : ''
            }));
        } catch {
            return [];
        }
    }

    get keyValuePairs() {
        if (!this.hasData || !this.isKeyValue) return [];
        try {
            const parsed = JSON.parse(this.value.jsonData);
            const pairs = parsed.pairs || [];
            return pairs.map((p, idx) => ({
                key: `pair-${idx}`,
                keyLabel: p.key != null ? String(p.key) : '',
                value: p.value != null ? String(p.value) : ''
            }));
        } catch {
            return [];
        }
    }
}
