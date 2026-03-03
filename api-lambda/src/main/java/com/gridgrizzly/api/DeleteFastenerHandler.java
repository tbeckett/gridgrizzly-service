package com.gridgrizzly.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.databind.ObjectMapper;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;

import java.util.Map;

public class DeleteFastenerHandler
        implements RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {

    private static final ObjectMapper MAPPER = new ObjectMapper()
            .setSerializationInclusion(JsonInclude.Include.NON_NULL);

    @Override
    public APIGatewayProxyResponseEvent handleRequest(APIGatewayProxyRequestEvent event, Context context) {
        String userId     = (String) event.getRequestContext().getAuthorizer().get("userId");
        Map<String, String> pathParams = event.getPathParameters();
        if (pathParams == null || !pathParams.containsKey("id")) {
            return error(400, "Missing path parameter: id");
        }
        String fastenerId = pathParams.get("id");

        try {
            Map<String, AttributeValue> item = FastenerStore.findById(fastenerId);
            if (item == null) {
                return error(404, "Fastener not found");
            }

            if (!userId.equals(item.get("userId").s())) {
                return error(403, "Access denied");
            }

            FastenerStore.deleteItem(
                    item.get("userId").s(),
                    item.get("resourceId").s());

            return new APIGatewayProxyResponseEvent().withStatusCode(204);

        } catch (Exception e) {
            context.getLogger().log("Unexpected error: " + e.getMessage());
            return error(500, "Internal server error");
        }
    }

    private APIGatewayProxyResponseEvent error(int status, String message) {
        try {
            return new APIGatewayProxyResponseEvent()
                    .withStatusCode(status)
                    .withHeaders(Map.of("Content-Type", "application/json"))
                    .withBody(MAPPER.writeValueAsString(Map.of("message", message)));
        } catch (Exception e) {
            return new APIGatewayProxyResponseEvent()
                    .withStatusCode(status)
                    .withBody("{\"message\":\"" + message + "\"}");
        }
    }
}
