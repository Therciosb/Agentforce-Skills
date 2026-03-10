/**
 * Output wrapper for GenericRenderAction.
 * Used by Custom Lightning Type and LWC for rendering.
 */
@JsonAccess(serializable='always' deserializable='always')
global class GenericRenderOutput {
    @AuraEnabled
    @InvocableVariable(
        label='JSON Data'
        description='Valid JSON string for LWC to render'
    )
    global String jsonData;

    @AuraEnabled
    @InvocableVariable(
        label='Display Type'
        description='One of: table, card, list, key-value'
    )
    global String displayType;

    @AuraEnabled
    @InvocableVariable(
        label='Success'
        description='True if validation passed'
    )
    global Boolean success;

    @AuraEnabled
    @InvocableVariable(
        label='Error Message'
        description='Error message when success is false'
    )
    global String errorMessage;
}
