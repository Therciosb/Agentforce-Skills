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
            String serialized = JSON.serialize(parsed);
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

    global class RenderDataInput {
        @InvocableVariable(
            required=true
            label='Data'
            description='JSON string following schema for the display type'
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