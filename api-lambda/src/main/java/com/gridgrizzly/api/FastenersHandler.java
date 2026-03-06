package com.gridgrizzly.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.gridgrizzly.api.model.*;

import java.util.List;
import java.util.Map;

public class FastenersHandler
        implements RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {

    private static final ObjectMapper MAPPER = new ObjectMapper()
            .setSerializationInclusion(JsonInclude.Include.NON_NULL);

    private static final List<Fastener> FASTENERS = List.of(
            new Fastener("f00000000001", FastenerType.BOLT, "Placeholder Bolt 1", UnitOfMeasure.IMPERIAL,
                    "Placeholder description", "Placeholder usage description",
                    new FastenerDetails("Hex", null, null, null, null, null, null, null, null, null, null, null),
                    new RetailData(null, "BOLT-001", "Placeholder Co.")),

            new Fastener("f00000000002", FastenerType.BOLT, "Placeholder Bolt 2", UnitOfMeasure.METRIC,
                    "Placeholder description", "Placeholder usage description",
                    new FastenerDetails("Carriage", null, null, null, null, null, null, null, null, null, null, null),
                    new RetailData(null, "BOLT-002", "Placeholder Co.")),

            new Fastener("f00000000003", FastenerType.SCREW, "Placeholder Screw 1", UnitOfMeasure.IMPERIAL,
                    "Placeholder description", "Placeholder usage description",
                    new FastenerDetails("Machine", DriveType.PHILLIPS, null, null, null, null, null, null, null, null, null, null),
                    new RetailData(null, "SCRW-001", "Placeholder Co.")),

            new Fastener("f00000000004", FastenerType.SCREW, "Placeholder Screw 2", UnitOfMeasure.IMPERIAL,
                    "Placeholder description", "Placeholder usage description",
                    new FastenerDetails("Wood", DriveType.SLOTTED, null, null, null, null, null, null, null, null, null, null),
                    new RetailData(null, "SCRW-002", "Placeholder Co.")),

            new Fastener("f00000000005", FastenerType.SCREW, "Placeholder Screw 3", UnitOfMeasure.METRIC,
                    "Placeholder description", "Placeholder usage description",
                    new FastenerDetails("Sheet Metal", DriveType.HEX, null, null, null, null, null, null, null, null, null, null),
                    new RetailData(null, "SCRW-003", "Placeholder Co.")),

            new Fastener("f00000000006", FastenerType.NUT, "Placeholder Nut 1", UnitOfMeasure.IMPERIAL,
                    "Placeholder description", "Placeholder usage description",
                    new FastenerDetails("Hex", null, null, null, null, null, null, null, null, null, null, null),
                    new RetailData(null, "NUT-001", "Placeholder Co.")),

            new Fastener("f00000000007", FastenerType.NUT, "Placeholder Nut 2", UnitOfMeasure.METRIC,
                    "Placeholder description", "Placeholder usage description",
                    new FastenerDetails("Lock", null, null, null, null, null, null, null, null, null, null, null),
                    new RetailData(null, "NUT-002", "Placeholder Co.")),

            new Fastener("f00000000008", FastenerType.WASHER, "Placeholder Washer 1", UnitOfMeasure.IMPERIAL,
                    "Placeholder description", "Placeholder usage description",
                    new FastenerDetails("Flat", null, null, null, null, null, null, null, null, null, null, null),
                    new RetailData(null, "WSHR-001", "Placeholder Co.")),

            new Fastener("f00000000009", FastenerType.WASHER, "Placeholder Washer 2", UnitOfMeasure.METRIC,
                    "Placeholder description", "Placeholder usage description",
                    new FastenerDetails("Lock", null, null, null, null, null, null, null, null, null, null, null),
                    new RetailData(null, "WSHR-002", "Placeholder Co.")),

            new Fastener("f00000000010", FastenerType.NAIL, "Placeholder Nail 1", UnitOfMeasure.IMPERIAL,
                    "Placeholder description", "Placeholder usage description",
                    new FastenerDetails("Common", null, null, null, null, null, null, null, null, null, null, null),
                    new RetailData(null, "NAIL-001", "Placeholder Co."))
    );

    @Override
    public APIGatewayProxyResponseEvent handleRequest(APIGatewayProxyRequestEvent event, Context context) {
        try {
            return new APIGatewayProxyResponseEvent()
                    .withStatusCode(200)
                    .withHeaders(Map.of("Content-Type", "application/json"))
                    .withBody(MAPPER.writeValueAsString(FASTENERS));
        } catch (Exception e) {
            return new APIGatewayProxyResponseEvent()
                    .withStatusCode(500)
                    .withBody("{\"message\":\"Internal server error\"}");
        }
    }
}
