public with sharing class GetOrderStatus {
    @InvocableMethod(label='Get Order Status' description='Look up the current status of an order.')
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            if (String.isNotBlank(req.order_id)) {
                res.status = 'Shipped - In Transit';
                res.tracking_number = 'TRK992838472US';
                res.error_code = null;
            } else {
                res.status = null;
                res.tracking_number = null;
                res.error_code = 'INVALID_ORDER_ID';
            }
            responses.add(res);
        }
        return responses;
    }

    public class Request {
        @InvocableVariable(label='Order ID' required=true) public String order_id;
    }

    public class Response {
        @InvocableVariable(label='Status') public String status;
        @InvocableVariable(label='Tracking Number') public String tracking_number;
        @InvocableVariable(label='Error Code') public String error_code;
    }
}