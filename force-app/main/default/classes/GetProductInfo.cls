public with sharing class GetProductInfo {
    @InvocableMethod(label='Get Product Info' description='Look up product specifications, price, and availability.')
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.in_stock = true;
            res.product_details = 'Widget X is a premium high-performance smart device featuring multi-sensor tracking, 48-hour battery life, water resistance (IP68), and seamless cloud sync. Price: $199.99.';
            responses.add(res);
        }
        return responses;
    }

    public class Request {
        @InvocableVariable(label='Product Name' required=true) public String product_name;
    }

    public class Response {
        @InvocableVariable(label='In Stock') public Boolean in_stock;
        @InvocableVariable(label='Product Details') public String product_details;
    }
}