public with sharing class TrackShipment {
    @InvocableMethod(label='Track Shipment' description='Track a shipment by carrier and tracking number.')
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.carrier = String.isNotBlank(req.carrier) ? req.carrier : 'FedEx';
            res.tracking_number = String.isNotBlank(req.tracking_number) ? req.tracking_number : 'TRK992838472US';
            res.status = 'Out for Delivery';
            res.estimated_delivery = '2026-11-14';
            res.success = true;
            responses.add(res);
        }
        return responses;
    }

    public class Request {
        @InvocableVariable(label='Carrier') public String carrier;
        @InvocableVariable(label='Tracking Number') public String tracking_number;
    }

    public class Response {
        @InvocableVariable(label='Carrier') public String carrier;
        @InvocableVariable(label='Tracking Number') public String tracking_number;
        @InvocableVariable(label='Status') public String status;
        @InvocableVariable(label='Estimated Delivery') public String estimated_delivery;
        @InvocableVariable(label='Success') public Boolean success;
    }
}