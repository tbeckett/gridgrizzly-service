package com.gridgrizzly.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.gridgrizzly.api.model.CreateFastenerRequest;
import com.gridgrizzly.api.model.Fastener;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;

import java.util.Map;

public class UpdateFastenerHandler
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

        String body = event.getBody();
        if (body == null || body.isBlank()) {
            return error(400, "Request body is required");
        }

        try {
            JsonNode node = MAPPER.readTree(body);
            if (node.has("id")) {
                return error(400, "'id' must not be provided — it is assigned by the server");
            }

            CreateFastenerRequest req = MAPPER.treeToValue(node, CreateFastenerRequest.class);
            validate(req);

            Map<String, AttributeValue> existing = FastenerStore.findById(fastenerId);
            if (existing == null) {
                return error(404, "Fastener not found");
            }

            if (!userId.equals(existing.get("userId").s())) {
                return error(403, "Access denied");
            }

            String createdAt = existing.get("createdAt").s();
            FastenerStore.putItem(FastenerStore.buildItem(userId, fastenerId, createdAt, req));

            Fastener fastener = new Fastener(
                    fastenerId, req.type(), req.title(), req.unitOfMeasure(),
                    req.description(), req.usageDescription(), req.finish(),
                    req.material(), req.details(), req.retailData());

            return new APIGatewayProxyResponseEvent()
                    .withStatusCode(200)
                    .withHeaders(Map.of("Content-Type", "application/json"))
                    .withBody(MAPPER.writeValueAsString(fastener));

        } catch (IllegalArgumentException e) {
            return error(400, e.getMessage());
        } catch (Exception e) {
            context.getLogger().log("Unexpected error: " + e.getMessage());
            return error(500, "Internal server error");
        }
    }

    private void validate(CreateFastenerRequest req) {
        if (req.type() == null)
            throw new IllegalArgumentException("'type' is required");
        if (req.title() == null || req.title().isBlank())
            throw new IllegalArgumentException("'title' is required");
        if (req.unitOfMeasure() == null)
            throw new IllegalArgumentException("'unitOfMeasure' is required");
        if (req.description() == null || req.description().isBlank())
            throw new IllegalArgumentException("'description' is required");
        if (req.usageDescription() == null || req.usageDescription().isBlank())
            throw new IllegalArgumentException("'usageDescription' is required");
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
