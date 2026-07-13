/**
 * Test GenericRenderAction with the exact format the agent produces
 * (from core-skill-render-data-format).
 * Run: sf apex run --file scripts/apex/test_generic_render_action.apex --target-org <org>
 */
System.debug('=== GenericRenderAction Test: Agent Format (4 LWC Types) ===\n');

// 1. TABLE - Agent format: array of objects (from skill example)
System.debug('--- 1. TABLE ---');
GenericRenderAction.RenderDataInput tableInput = new GenericRenderAction.RenderDataInput();
tableInput.data = '[{"Case ID":"C-001","Title":"Sample Case Alpha","Status":"Open"},{"Case ID":"C-002","Title":"Sample Case Beta","Status":"In Progress"},{"Case ID":"C-003","Title":"Sample Case Gamma","Status":"Closed"}]';
tableInput.display_type = 'table';

List<GenericRenderAction.RenderDataResponse> tableResults = GenericRenderAction.renderData(new List<GenericRenderAction.RenderDataInput>{ tableInput });
GenericRenderOutput tableOut = tableResults[0].result;
System.debug('Input (agent format): ' + tableInput.data);
System.debug('success: ' + tableOut.success + ' | displayType: ' + tableOut.displayType + ' | errorMessage: ' + tableOut.errorMessage);
System.debug('jsonData (LWC format): ' + tableOut.jsonData);
System.debug(tableOut.success ? 'PASS' : 'FAIL: ' + tableOut.errorMessage);
System.debug('');

// 2. CARD - Agent format: object with title and flat key-value pairs
System.debug('--- 2. CARD ---');
GenericRenderAction.RenderDataInput cardInput = new GenericRenderAction.RenderDataInput();
cardInput.data = '{"title":"Case 00001001","Subject":"Wi-Fi not connecting","Status":"In Progress","Priority":"High"}';
cardInput.display_type = 'card';

List<GenericRenderAction.RenderDataResponse> cardResults = GenericRenderAction.renderData(new List<GenericRenderAction.RenderDataInput>{ cardInput });
GenericRenderOutput cardOut = cardResults[0].result;
System.debug('Input (agent format): ' + cardInput.data);
System.debug('success: ' + cardOut.success + ' | displayType: ' + cardOut.displayType + ' | errorMessage: ' + cardOut.errorMessage);
System.debug('jsonData (LWC format): ' + cardOut.jsonData);
System.debug(cardOut.success ? 'PASS' : 'FAIL: ' + cardOut.errorMessage);
System.debug('');

// 3. LIST - Agent format: array of strings
System.debug('--- 3. LIST ---');
GenericRenderAction.RenderDataInput listInput = new GenericRenderAction.RenderDataInput();
listInput.data = '["Power cycle the modem","Wait 2 minutes","Check LED status"]';
listInput.display_type = 'list';

List<GenericRenderAction.RenderDataResponse> listResults = GenericRenderAction.renderData(new List<GenericRenderAction.RenderDataInput>{ listInput });
GenericRenderOutput listOut = listResults[0].result;
System.debug('Input (agent format): ' + listInput.data);
System.debug('success: ' + listOut.success + ' | displayType: ' + listOut.displayType + ' | errorMessage: ' + listOut.errorMessage);
System.debug('jsonData (LWC format): ' + listOut.jsonData);
System.debug(listOut.success ? 'PASS' : 'FAIL: ' + listOut.errorMessage);
System.debug('');

// 4. KEY-VALUE - Agent format: flat object
System.debug('--- 4. KEY-VALUE ---');
GenericRenderAction.RenderDataInput kvInput = new GenericRenderAction.RenderDataInput();
kvInput.data = '{"Account":"Acme Corp","Contact":"Jane Smith","Case":"00001001"}';
kvInput.display_type = 'key-value';

List<GenericRenderAction.RenderDataResponse> kvResults = GenericRenderAction.renderData(new List<GenericRenderAction.RenderDataInput>{ kvInput });
GenericRenderOutput kvOut = kvResults[0].result;
System.debug('Input (agent format): ' + kvInput.data);
System.debug('success: ' + kvOut.success + ' | displayType: ' + kvOut.displayType + ' | errorMessage: ' + kvOut.errorMessage);
System.debug('jsonData (LWC format): ' + kvOut.jsonData);
System.debug(kvOut.success ? 'PASS' : 'FAIL: ' + kvOut.errorMessage);
System.debug('');

// Summary
Integer allPass = (tableOut.success ? 1 : 0) + (cardOut.success ? 1 : 0) + (listOut.success ? 1 : 0) + (kvOut.success ? 1 : 0);
System.debug('=== SUMMARY ===');
System.debug('All 4 types: ' + allPass + '/4 PASS');
System.debug(allPass == 4 ? 'Apex correctly converts agent format to LWC format for all display types.' : 'Some types failed.');
