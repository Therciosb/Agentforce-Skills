// Test GenericRenderAction invocable with table display type
GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
input.data = '{"columns":["Case Number","Subject","Status"],"rows":[["00001001","Wi-Fi not connecting","In Progress"],["00001002","Billing question","Closed"],["00001003","Password reset","New"]]}';
input.display_type = 'table';

List<GenericRenderAction.RenderDataResponse> results = GenericRenderAction.renderData(new List<GenericRenderAction.RenderDataInput>{ input });
GenericRenderOutput out = results[0].result;

System.debug('=== GenericRenderAction Test (Table) ===');
System.debug('success: ' + out.success);
System.debug('displayType: ' + out.displayType);
System.debug('errorMessage: ' + out.errorMessage);
System.debug('jsonData: ' + out.jsonData);

if (out.success) {
    System.debug('SUCCESS: Invocable returned valid output for table display.');
    System.debug('Output is ready for LWC rendering when displayed via Agent Action with Custom Lightning Type.');
} else {
    System.debug('FAILED: ' + out.errorMessage);
}
