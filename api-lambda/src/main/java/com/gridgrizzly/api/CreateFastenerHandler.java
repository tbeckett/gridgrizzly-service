package com.gridgrizzly.api;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.gridgrizzly.api.model.*;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;

import java.time.Instant;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

public class CreateFastenerHandler
        implements RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {

    private static final String TABLE_NAME = System.getenv("DYNAMODB_TABLE_NAME");

    private static final ObjectMapper MAPPER = new ObjectMapper()
            .setSerializationInclusion(JsonInclude.Include.NON_NULL);

    // Initialised once at cold start; reused across warm invocations.
    private static final DynamoDbClient DDB = DynamoDbClient.create();

    @Override
    public APIGatewayProxyResponseEvent handleRequest(APIGatewayProxyRequestEvent event, Context context) {
        String userId = (String) event.getRequestContext().getAuthorizer().get("userId");

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

            String id        = UUID.randomUUID().toString();
            String createdAt = Instant.now().toString();
            int    binNumber = FastenerStore.nextBinNumber(userId);

            DDB.putItem(PutItemRequest.builder()
                    .tableName(TABLE_NAME)
                    .item(buildItem(userId, id, createdAt, binNumber, req))
                    .build());

            Fastener created = new Fastener(
                    id, req.type(), req.title(), binNumber, req.unitOfMeasure(),
                    req.description(), req.usageDescription(),
                    req.finish(), req.material(),
                    req.fastenerSubTypes(), req.headDetails(), req.sizeDetails(),
                    req.threadDetails(), req.retailData());

            return new APIGatewayProxyResponseEvent()
                    .withStatusCode(201)
                    .withHeaders(Map.of(
                            "Content-Type", "application/json",
                            "Location", "/fasteners/" + id))
                    .withBody(MAPPER.writeValueAsString(created));

        } catch (IllegalArgumentException e) {
            return error(400, e.getMessage());
        } catch (Exception e) {
            context.getLogger().log("Unexpected error: " + e.getMessage());
            return error(500, "Internal server error");
        }
    }

    // ── Validation ────────────────────────────────────────────────────────────

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

    // ── DynamoDB item builder ─────────────────────────────────────────────────

    private Map<String, AttributeValue> buildItem(
            String userId, String id, String createdAt, int binNumber, CreateFastenerRequest req) {

        Map<String, AttributeValue> item = new HashMap<>();

        // Keys
        item.put("userId",      s(userId));
        item.put("resourceId",  s("FASTENER#" + id));
        item.put("fastenerId",  s(id));               // projected into GSI for ID-based queries

        // Scalar fields
        item.put("type",             s(req.type().name()));
        item.put("title",            s(req.title()));
        item.put("binNumber",        AttributeValue.fromN(String.valueOf(binNumber)));
        item.put("unitOfMeasure",    s(req.unitOfMeasure().name()));
        item.put("description",      s(req.description()));
        item.put("usageDescription", s(req.usageDescription()));
        item.put("createdAt",        s(createdAt));

        // Scalar optional fields
        putIfSet(item, "finish",   req.finish());
        putIfSet(item, "material", req.material());

        // Nested objects
        if (req.fastenerSubTypes() != null && req.fastenerSubTypes().length > 0)
            item.put("fastenerSubTypes", AttributeValue.fromSs(Arrays.asList(req.fastenerSubTypes())));
        if (req.headDetails() != null)   item.put("headDetails",   toAttributeMap(req.headDetails()));
        if (req.sizeDetails() != null)   item.put("sizeDetails",   toAttributeMap(req.sizeDetails()));
        if (req.threadDetails() != null) item.put("threadDetails", toAttributeMap(req.threadDetails()));
        if (req.retailData() != null)    item.put("retailData",    toAttributeMap(req.retailData()));

        return item;
    }

    private AttributeValue toAttributeMap(HeadDetails h) {
        Map<String, AttributeValue> m = new HashMap<>();
        putIfSet(m, "driveType",    h.driveType() != null ? h.driveType().name() : null);
        putIfSet(m, "headType",     h.headType() != null ? h.headType().name() : null);
        putIfSet(m, "headDiameter", h.headDiameter());
        return AttributeValue.fromM(m);
    }

    private AttributeValue toAttributeMap(SizeDetails sz) {
        Map<String, AttributeValue> m = new HashMap<>();
        putIfSet(m, "length",          sz.length());
        putIfSet(m, "outsideDiameter", sz.outsideDiameter());
        putIfSet(m, "insideDiameter",  sz.insideDiameter());
        putIfSet(m, "thickness",       sz.thickness());
        putIfSet(m, "gauge",           sz.gauge());
        return AttributeValue.fromM(m);
    }

    private AttributeValue toAttributeMap(ThreadDetails t) {
        Map<String, AttributeValue> m = new HashMap<>();
        putIfSet(m, "threadPitch", t.threadPitch());
        putIfSet(m, "threadType",  t.threadType() != null ? t.threadType().name() : null);
        putIfSet(m, "shankType",   t.shankType() != null ? t.shankType().name() : null);
        return AttributeValue.fromM(m);
    }

    private AttributeValue toAttributeMap(RetailData r) {
    Map<String, AttributeValue> m = new HashMap<>();
        putIfSet(m, "upc",     r.upc());
        putIfSet(m, "sku",     r.sku());
        putIfSet(m, "company", r.company());
        return AttributeValue.fromM(m);
    }

    private void putIfSet(Map<String, AttributeValue> map, String key, String value) {
        if (value != null && !value.isBlank()) map.put(key, s(value));
    }

    private AttributeValue s(String value) {
        return AttributeValue.fromS(value);
    }

    // ── Error helpers ─────────────────────────────────────────────────────────

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
