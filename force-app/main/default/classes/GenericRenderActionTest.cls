@IsTest
private class GenericRenderActionTest {
    @IsTest
    static void validTableJson_returnsSuccess() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"columns":["Case Number","Status"],"rows":[["00001","Open"]]}';
        input.display_type = 'table';

        Test.startTest();
        List<GenericRenderAction.RenderDataResponse> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        GenericRenderOutput out = results[0].result;
        System.assertEquals(true, out.success);
        System.assertNotEquals(null, out.jsonData);
        System.assertEquals('table', out.displayType);
        System.assertEquals(null, out.errorMessage);
    }

    @IsTest
    static void validCardJson_returnsSuccess() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"title":"Case 00001","fields":[{"label":"Subject","value":"Wi-Fi issue"}]}';
        input.display_type = 'card';

        Test.startTest();
        List<GenericRenderAction.RenderDataResponse> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].result.success);
        System.assertEquals('card', results[0].result.displayType);
    }

    @IsTest
    static void validListJson_returnsSuccess() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"items":["Step 1","Step 2","Step 3"]}';
        input.display_type = 'list';

        Test.startTest();
        List<GenericRenderAction.RenderDataResponse> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].result.success);
        System.assertEquals('list', results[0].result.displayType);
    }

    @IsTest
    static void validKeyValueJson_returnsSuccess() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"pairs":[{"key":"Account","value":"Acme"}]}';
        input.display_type = 'key-value';

        Test.startTest();
        List<GenericRenderAction.RenderDataResponse> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].result.success);
        System.assertEquals('key-value', results[0].result.displayType);
    }

    @IsTest
    static void invalidJson_returnsError() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"invalid": json}';
        input.display_type = 'table';

        Test.startTest();
        List<GenericRenderAction.RenderDataResponse> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].result.success);
        System.assert(results[0].result.errorMessage.contains('Invalid JSON'));
    }

    @IsTest
    static void invalidDisplayType_returnsError() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"items":["a"]}';
        input.display_type = 'invalid';

        Test.startTest();
        List<GenericRenderAction.RenderDataResponse> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].result.success);
        System.assert(results[0].result.errorMessage.contains('Invalid display type'));
    }

    @IsTest
    static void blankData_returnsError() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '';
        input.display_type = 'table';

        Test.startTest();
        List<GenericRenderAction.RenderDataResponse> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].result.success);
        System.assertEquals('Data is required', results[0].result.errorMessage);
    }

    @IsTest
    static void blankDisplayType_returnsError() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"items":["a"]}';
        input.display_type = '';

        Test.startTest();
        List<GenericRenderAction.RenderDataResponse> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].result.success);
        System.assertEquals('Display type is required', results[0].result.errorMessage);
    }

    @IsTest
    static void displayTypeCaseInsensitive() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '["a"]';
        input.display_type = 'LIST';

        Test.startTest();
        List<GenericRenderAction.RenderDataResponse> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].result.success);
        System.assertEquals('list', results[0].result.displayType);
    }

    // --- Agent syntax → LWC format conversion tests ---

    @IsTest
    static void tableAgentSyntax_convertsToColumnsRows() {
        String agentData = '[{"Case ID":"C-001","Title":"Sample Alpha","Status":"Open"},{"Case ID":"C-002","Title":"Sample Beta","Status":"Closed"}]';
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = agentData;
        input.display_type = 'table';

        Test.startTest();
        List<GenericRenderAction.RenderDataResponse> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        GenericRenderOutput out = results[0].result;
        System.assertEquals(true, out.success, 'Expected success');
        System.assertNotEquals(null, out.jsonData, 'jsonData should be set');

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(out.jsonData);
        List<Object> columns = (List<Object>) parsed.get('columns');
        List<Object> rows = (List<Object>) parsed.get('rows');

        System.assertNotEquals(null, columns, 'Should have columns');
        System.assertNotEquals(null, rows, 'Should have rows');
        System.assertEquals(3, columns.size(), 'Should have 3 columns: Case ID, Status, Title (sorted)');
        System.assertEquals(2, rows.size(), 'Should have 2 rows');

        List<String> colStrs = new List<String>();
        for (Object c : columns) { colStrs.add((String) c); }
        System.assert(colStrs.contains('Case ID'), 'Should include Case ID');
        System.assert(colStrs.contains('Title'), 'Should include Title');
        System.assert(colStrs.contains('Status'), 'Should include Status');

        List<Object> row1 = (List<Object>) rows[0];
        System.assertEquals(3, row1.size(), 'Each row should have 3 values');
    }

    @IsTest
    static void cardAgentSyntax_convertsToFields() {
        String agentData = '{"title":"Case 00001001","Subject":"Wi-Fi not connecting","Status":"In Progress","Priority":"High"}';
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = agentData;
        input.display_type = 'card';

        Test.startTest();
        List<GenericRenderAction.RenderDataResponse> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        GenericRenderOutput out = results[0].result;
        System.assertEquals(true, out.success, 'Expected success');

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(out.jsonData);
        System.assertEquals('Case 00001001', parsed.get('title'), 'Title should be preserved');

        List<Object> fields = (List<Object>) parsed.get('fields');
        System.assertNotEquals(null, fields, 'Should have fields array');
        System.assertEquals(3, fields.size(), 'Should have 3 fields: Priority, Status, Subject (sorted)');

        Map<String, Object> firstField = (Map<String, Object>) fields[0];
        System.assert(firstField.containsKey('label'), 'Each field should have label');
        System.assert(firstField.containsKey('value'), 'Each field should have value');
    }

    @IsTest
    static void listAgentSyntax_convertsToItems() {
        String agentData = '["Power cycle the modem","Wait 2 minutes","Check LED status"]';
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = agentData;
        input.display_type = 'list';

        Test.startTest();
        List<GenericRenderAction.RenderDataResponse> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        GenericRenderOutput out = results[0].result;
        System.assertEquals(true, out.success, 'Expected success');

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(out.jsonData);
        List<Object> items = (List<Object>) parsed.get('items');
        System.assertNotEquals(null, items, 'Should have items array');
        System.assertEquals(3, items.size(), 'Should have 3 items');
        System.assertEquals('Power cycle the modem', items[0], 'First item should match');
        System.assertEquals('Wait 2 minutes', items[1], 'Second item should match');
        System.assertEquals('Check LED status', items[2], 'Third item should match');
    }

    @IsTest
    static void keyValueAgentSyntax_convertsToPairs() {
        String agentData = '{"Account":"Acme Corp","Contact":"Jane Smith","Case":"00001001"}';
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = agentData;
        input.display_type = 'key-value';

        Test.startTest();
        List<GenericRenderAction.RenderDataResponse> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        GenericRenderOutput out = results[0].result;
        System.assertEquals(true, out.success, 'Expected success');

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(out.jsonData);
        List<Object> pairs = (List<Object>) parsed.get('pairs');
        System.assertNotEquals(null, pairs, 'Should have pairs array');
        System.assertEquals(3, pairs.size(), 'Should have 3 pairs');

        Map<String, Object> pair0 = (Map<String, Object>) pairs[0];
        System.assert(pair0.containsKey('key'), 'Each pair should have key');
        System.assert(pair0.containsKey('value'), 'Each pair should have value');
    }

    @IsTest
    static void tableInvalidInput_returnsError() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"not":"array"}';
        input.display_type = 'table';

        List<GenericRenderAction.RenderDataResponse> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );

        System.assertEquals(false, results[0].result.success);
        System.assert(results[0].result.errorMessage.contains('array of objects'));
    }

    @IsTest
    static void listInvalidInput_returnsError() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"not":"array"}';
        input.display_type = 'list';

        List<GenericRenderAction.RenderDataResponse> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );

        System.assertEquals(false, results[0].result.success);
        System.assert(results[0].result.errorMessage.contains('array of strings'));
    }
}
