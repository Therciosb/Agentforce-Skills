@IsTest
private class GenericRenderActionTest {
    @IsTest
    static void validTableJson_returnsSuccess() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"columns":["Case Number","Status"],"rows":[["00001","Open"]]}';
        input.display_type = 'table';

        Test.startTest();
        List<GenericRenderOutput> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertNotEquals(null, results[0].jsonData);
        System.assertEquals('table', results[0].displayType);
        System.assertEquals(null, results[0].errorMessage);
    }

    @IsTest
    static void validCardJson_returnsSuccess() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"title":"Case 00001","fields":[{"label":"Subject","value":"Wi-Fi issue"}]}';
        input.display_type = 'card';

        Test.startTest();
        List<GenericRenderOutput> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals('card', results[0].displayType);
    }

    @IsTest
    static void validListJson_returnsSuccess() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"items":["Step 1","Step 2","Step 3"]}';
        input.display_type = 'list';

        Test.startTest();
        List<GenericRenderOutput> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals('list', results[0].displayType);
    }

    @IsTest
    static void validKeyValueJson_returnsSuccess() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"pairs":[{"key":"Account","value":"Acme"}]}';
        input.display_type = 'key-value';

        Test.startTest();
        List<GenericRenderOutput> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals('key-value', results[0].displayType);
    }

    @IsTest
    static void invalidJson_returnsError() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"invalid": json}';
        input.display_type = 'table';

        Test.startTest();
        List<GenericRenderOutput> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assert(results[0].errorMessage.contains('Invalid JSON'));
    }

    @IsTest
    static void invalidDisplayType_returnsError() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"items":["a"]}';
        input.display_type = 'invalid';

        Test.startTest();
        List<GenericRenderOutput> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assert(results[0].errorMessage.contains('Invalid display type'));
    }

    @IsTest
    static void blankData_returnsError() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '';
        input.display_type = 'table';

        Test.startTest();
        List<GenericRenderOutput> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assertEquals('Data is required', results[0].errorMessage);
    }

    @IsTest
    static void blankDisplayType_returnsError() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"items":["a"]}';
        input.display_type = '';

        Test.startTest();
        List<GenericRenderOutput> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assertEquals('Display type is required', results[0].errorMessage);
    }

    @IsTest
    static void displayTypeCaseInsensitive() {
        GenericRenderAction.RenderDataInput input = new GenericRenderAction.RenderDataInput();
        input.data = '{"items":["a"]}';
        input.display_type = 'LIST';

        Test.startTest();
        List<GenericRenderOutput> results = GenericRenderAction.renderData(
            new List<GenericRenderAction.RenderDataInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals('list', results[0].displayType);
    }
}
