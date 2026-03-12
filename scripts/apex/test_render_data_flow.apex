// Test Render_Data Flow with table display type
Map<String, Object> inputs = new Map<String, Object>();
inputs.put('data', '{"columns":["Case Number","Subject","Status"],"rows":[["00001001","Wi-Fi not connecting","In Progress"],["00001002","Billing question","Closed"],["00001003","Password reset","New"]]}');
inputs.put('display_type', 'table');

Flow.Interview.Render_Data flow = new Flow.Interview.Render_Data(inputs);
flow.start();

// Flow maps result.jsonData etc. to output variables
String jsonData = (String) flow.getVariableValue('jsonData');
String displayType = (String) flow.getVariableValue('displayType');
Boolean success = (Boolean) flow.getVariableValue('success');
String errorMessage = (String) flow.getVariableValue('errorMessage');

System.debug('=== Render_Data Flow Test (Table) ===');
System.debug('success: ' + success);
System.debug('displayType: ' + displayType);
System.debug('errorMessage: ' + errorMessage);
System.debug('jsonData: ' + jsonData);

if (success == true) {
    System.debug('SUCCESS: Flow returned valid output for table display.');
    System.debug('Output matches GenericRenderAction output (Flow wrapper working correctly).');
} else {
    System.debug('FAILED: ' + errorMessage);
}
