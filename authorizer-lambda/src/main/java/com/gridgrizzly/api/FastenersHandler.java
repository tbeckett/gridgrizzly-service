package com.gridgrizzly.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent;

import java.util.Map;

public class FastenersHandler
        implements RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {

    private static final String BODY = """
            [
              {"id": "F001", "name": "Placeholder Fastener 1",  "type": "placeholder"},
              {"id": "F002", "name": "Placeholder Fastener 2",  "type": "placeholder"},
              {"id": "F003", "name": "Placeholder Fastener 3",  "type": "placeholder"},
              {"id": "F004", "name": "Placeholder Fastener 4",  "type": "placeholder"},
              {"id": "F005", "name": "Placeholder Fastener 5",  "type": "placeholder"},
              {"id": "F006", "name": "Placeholder Fastener 6",  "type": "placeholder"},
              {"id": "F007", "name": "Placeholder Fastener 7",  "type": "placeholder"},
              {"id": "F008", "name": "Placeholder Fastener 8",  "type": "placeholder"},
              {"id": "F009", "name": "Placeholder Fastener 9",  "type": "placeholder"},
              {"id": "F010", "name": "Placeholder Fastener 10", "type": "placeholder"}
            ]
            """;

    @Override
    public APIGatewayProxyResponseEvent handleRequest(APIGatewayProxyRequestEvent event, Context context) {
        return new APIGatewayProxyResponseEvent()
                .withStatusCode(200)
                .withHeaders(Map.of("Content-Type", "application/json"))
                .withBody(BODY);
    }
}
