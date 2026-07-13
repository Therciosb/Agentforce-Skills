/**
 * Invocable action that validates and returns structured data for LWC rendering.
 * Used by Agentforce agents to display table, card, list, or key-value formats.
 */
global with sharing class GenericRenderAction {
    private static final Set<String> VALID_DISPLAY_TYPES = new Set<String>{
        'table', 'card', 'list', 'key-value'
    };

    @InvocableMethod(
        label='Render Data'
        description='Renders structured data in the agent UI. Validates JSON and display type.'
    )
    public static List<RenderDataResponse> renderData(List<RenderDataInput> inputs) {
        List<RenderDataResponse> results = new List<RenderDataResponse>();
        for (RenderDataInput input : inputs) {
            RenderDataResponse r = new RenderDataResponse();
            r.result = processInput(input);
            results.add(r);
        }
        return results;
    }

    private static GenericRenderOutput processInput(RenderDataInput input) {
        GenericRenderOutput output = new GenericRenderOutput();

        if (String.isBlank(input.data)) {
            output.success = false;
            output.errorMessage = 'Data is required';
            return output;
        }

        if (String.isBlank(input.display_type)) {
            output.success = false;
            output.errorMessage = 'Display type is required';
            return output;
        }

        String displayType = input.display_type.trim().toLowerCase();
        if (!VALID_DISPLAY_TYPES.contains(displayType)) {
            output.success = false;
            output.errorMessage = 'Invalid display type. Use: table, card, list, key-value';
            return output;
        }

        try {
            Object parsed = JSON.deserializeUntyped(input.data);
            String serialized;
            if (displayType == 'table') {
                serialized = convertTable(parsed);
                if (serialized == null) {
                    output.success = false;
                    output.errorMessage = 'Table data must be a JSON array of objects. Example: [{"Col1":"val1","Col2":"val2"},...]';
                    return output;
                }
            } else if (displayType == 'card') {
                serialized = convertCard(parsed);
                if (serialized == null) {
                    output.success = false;
                    output.errorMessage = 'Card data must be a JSON object with "title" and optional key-value pairs. Example: {"title":"Case 00001","Subject":"Wi-Fi","Status":"Open"}';
                    return output;
                }
            } else if (displayType == 'list') {
                serialized = convertList(parsed);
                if (serialized == null) {
                    output.success = false;
                    output.errorMessage = 'List data must be a JSON array of strings. Example: ["item1","item2","item3"]';
                    return output;
                }
            } else if (displayType == 'key-value') {
                serialized = convertKeyValue(parsed);
                if (serialized == null) {
                    output.success = false;
                    output.errorMessage = 'Key-value data must be a JSON object. Example: {"Account":"Acme","Contact":"Jane Smith"}';
                    return output;
                }
            } else {
                serialized = JSON.serialize(parsed);
            }
            output.jsonData = serialized;
            output.displayType = displayType;
            output.success = true;
            output.errorMessage = null;
        } catch (JSONException e) {
            output.success = false;
            output.errorMessage = 'Invalid JSON: ' + e.getMessage();
        }

        return output;
    }

    /**
     * Converts table input to LWC format. Accepts either:
     * - Agent: array of objects -> { columns, rows }
     * - Already LWC: { columns, rows } -> pass through
     */
    private static String convertTable(Object parsed) {
        if (parsed instanceof Map<String, Object>) {
            Map<String, Object> obj = (Map<String, Object>) parsed;
            if (obj.containsKey('columns') && obj.containsKey('rows')) {
                return JSON.serialize(parsed);
            }
        }
        if (!(parsed instanceof List<Object>)) {
            return null;
        }
        List<Object> arr = (List<Object>) parsed;
        if (arr.isEmpty()) {
            return JSON.serialize(new Map<String, Object>{
                'columns' => new List<String>(),
                'rows' => new List<List<String>>()
            });
        }
        // Collect all unique column names across objects
        Set<String> columnSet = new Set<String>();
        for (Object item : arr) {
            if (!(item instanceof Map<String, Object>)) {
                return null;
            }
            columnSet.addAll(((Map<String, Object>) item).keySet());
        }
        List<String> columns = new List<String>(columnSet);
        columns.sort();
        // Build rows as arrays of values in column order
        List<List<String>> rows = new List<List<String>>();
        for (Object item : arr) {
            Map<String, Object> row = (Map<String, Object>) item;
            List<String> vals = new List<String>();
            for (String col : columns) {
                Object v = row.get(col);
                vals.add(v != null ? String.valueOf(v) : '');
            }
            rows.add(vals);
        }
        Map<String, Object> result = new Map<String, Object>{
            'columns' => columns,
            'rows' => rows
        };
        return JSON.serialize(result);
    }

    /**
     * Converts card input to LWC format. Accepts either:
     * - Simple: { title, key1, key2, ... } -> { title, fields: [{label, value}, ...] }
     * - Already LWC: { title, fields: [{label, value}, ...] } -> pass through
     */
    private static String convertCard(Object parsed) {
        if (!(parsed instanceof Map<String, Object>)) {
            return null;
        }
        Map<String, Object> obj = (Map<String, Object>) parsed;
        if (obj.containsKey('fields') && obj.get('fields') instanceof List<Object>) {
            return JSON.serialize(parsed);
        }
        String title = obj.containsKey('title') && obj.get('title') != null
            ? String.valueOf(obj.get('title')) : '';
        List<String> keys = new List<String>(obj.keySet());
        keys.sort();
        List<Map<String, String>> fields = new List<Map<String, String>>();
        for (String k : keys) {
            if (k != 'title') {
                Object v = obj.get(k);
                fields.add(new Map<String, String>{
                    'label' => k,
                    'value' => v != null ? String.valueOf(v) : ''
                });
            }
        }
        Map<String, Object> result = new Map<String, Object>{
            'title' => title,
            'fields' => fields
        };
        return JSON.serialize(result);
    }

    /**
     * Converts list input to LWC format. Accepts either:
     * - Simple: ["item1", "item2", ...] -> { items: [...] }
     * - Already LWC: { items: [...] } -> pass through
     */
    private static String convertList(Object parsed) {
        if (parsed instanceof Map<String, Object>) {
            Map<String, Object> obj = (Map<String, Object>) parsed;
            if (obj.containsKey('items') && obj.get('items') instanceof List<Object>) {
                return JSON.serialize(parsed);
            }
        }
        if (!(parsed instanceof List<Object>)) {
            return null;
        }
        List<Object> arr = (List<Object>) parsed;
        List<String> items = new List<String>();
        for (Object item : arr) {
            items.add(item != null ? String.valueOf(item) : '');
        }
        Map<String, Object> result = new Map<String, Object>{ 'items' => items };
        return JSON.serialize(result);
    }

    /**
     * Converts key-value input to LWC format. Accepts either:
     * - Simple: { key1: val1, key2: val2, ... } -> { pairs: [{key, value}, ...] }
     * - Already LWC: { pairs: [{key, value}, ...] } -> pass through
     */
    private static String convertKeyValue(Object parsed) {
        if (!(parsed instanceof Map<String, Object>)) {
            return null;
        }
        Map<String, Object> obj = (Map<String, Object>) parsed;
        if (obj.containsKey('pairs') && obj.get('pairs') instanceof List<Object>) {
            return JSON.serialize(parsed);
        }
        List<String> keys = new List<String>(obj.keySet());
        keys.sort();
        List<Map<String, String>> pairs = new List<Map<String, String>>();
        for (String k : keys) {
            Object v = obj.get(k);
            pairs.add(new Map<String, String>{
                'key' => k,
                'value' => v != null ? String.valueOf(v) : ''
            });
        }
        Map<String, Object> result = new Map<String, Object>{ 'pairs' => pairs };
        return JSON.serialize(result);
    }

    global class RenderDataInput {
        @InvocableVariable(
            required=true
            label='Data'
            description='Data structure per display type (platform serializes to JSON). table=array of objects, card=object with title, list=array of strings, key-value=flat object.'
        )
        global String data;

        @InvocableVariable(
            required=true
            label='Display Type'
            description='One of: table, card, list, key-value'
        )
        global String display_type;
    }

    /**
     * Wrapper so the platform exposes a single complex output (GenericRenderOutput)
     * instead of flattening to primitives. Required for Custom Lightning Type to
     * appear in Agent Action Output Rendering.
     */
    global class RenderDataResponse {
        @InvocableVariable(
            label='Result'
            description='Render output for LWC display'
        )
        global GenericRenderOutput result;
    }
}