package com.gridgrizzly.api;

import com.gridgrizzly.api.model.*;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.DeleteItemRequest;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;

import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

class FastenerStore {

    static final String TABLE_NAME = System.getenv("DYNAMODB_TABLE_NAME");
    private static final String GSI_NAME = "fastenerId-index";

    private static final DynamoDbClient DDB = DynamoDbClient.create();

    // ── Lookup ────────────────────────────────────────────────────────────────

    /** Returns the raw DynamoDB item for the given fastenerId, or null if not found. */
    static Map<String, AttributeValue> findById(String fastenerId) {
        QueryResponse resp = DDB.query(QueryRequest.builder()
                .tableName(TABLE_NAME)
                .indexName(GSI_NAME)
                .keyConditionExpression("fastenerId = :fid")
                .expressionAttributeValues(Map.of(":fid", s(fastenerId)))
                .build());
        return resp.items().isEmpty() ? null : resp.items().getFirst();
    }

    // ── Mutations ─────────────────────────────────────────────────────────────

    static void putItem(Map<String, AttributeValue> item) {
        DDB.putItem(PutItemRequest.builder()
                .tableName(TABLE_NAME)
                .item(item)
                .build());
    }

    static void deleteItem(String userId, String resourceId) {
        DDB.deleteItem(DeleteItemRequest.builder()
                .tableName(TABLE_NAME)
                .key(Map.of(
                        "userId",     s(userId),
                        "resourceId", s(resourceId)))
                .build());
    }

    // ── Item builder ──────────────────────────────────────────────────────────

    static Map<String, AttributeValue> buildItem(
            String userId, String fastenerId, String createdAt, CreateFastenerRequest req) {

        Map<String, AttributeValue> item = new HashMap<>();
        item.put("userId",           s(userId));
        item.put("resourceId",       s("FASTENER#" + fastenerId));
        item.put("fastenerId",       s(fastenerId));
        item.put("type",             s(req.type().name()));
        item.put("title",            s(req.title()));
        item.put("unitOfMeasure",    s(req.unitOfMeasure().name()));
        item.put("description",      s(req.description()));
        item.put("usageDescription", s(req.usageDescription()));
        item.put("createdAt",        s(createdAt));
        putIfSet(item, "finish",   req.finish());
        putIfSet(item, "material", req.material());
        if (req.fastenerSubTypes() != null && req.fastenerSubTypes().length > 0)
            item.put("fastenerSubTypes", AttributeValue.fromSs(Arrays.asList(req.fastenerSubTypes())));
        if (req.headDetails() != null)   item.put("headDetails",   toAttrMap(req.headDetails()));
        if (req.sizeDetails() != null)   item.put("sizeDetails",   toAttrMap(req.sizeDetails()));
        if (req.threadDetails() != null) item.put("threadDetails", toAttrMap(req.threadDetails()));
        if (req.retailData() != null)    item.put("retailData",    toAttrMap(req.retailData()));
        return item;
    }

    // ── Deserialisation ───────────────────────────────────────────────────────

    static Fastener toFastener(Map<String, AttributeValue> item) {
        String[]      fastenerSubTypes = item.containsKey("fastenerSubTypes")
                ? item.get("fastenerSubTypes").ss().toArray(new String[0]) : null;
        HeadDetails   headDetails      = item.containsKey("headDetails")
                ? toHeadDetails(item.get("headDetails").m()) : null;
        SizeDetails   sizeDetails      = item.containsKey("sizeDetails")
                ? toSizeDetails(item.get("sizeDetails").m()) : null;
        ThreadDetails threadDetails    = item.containsKey("threadDetails")
                ? toThreadDetails(item.get("threadDetails").m()) : null;
        RetailData    retailData       = item.containsKey("retailData")
                ? toRetailData(item.get("retailData").m()) : null;

        return new Fastener(
                item.get("fastenerId").s(),
                FastenerType.valueOf(item.get("type").s()),
                item.get("title").s(),
                UnitOfMeasure.valueOf(item.get("unitOfMeasure").s()),
                item.get("description").s(),
                item.get("usageDescription").s(),
                str(item, "finish"),
                str(item, "material"),
                fastenerSubTypes,
                headDetails,
                sizeDetails,
                threadDetails,
                retailData);
    }

    // ── Attribute value helpers ───────────────────────────────────────────────

    static AttributeValue toAttrMap(HeadDetails h) {
        Map<String, AttributeValue> m = new HashMap<>();
        putIfSet(m, "driveType",    h.driveType() != null ? h.driveType().name() : null);
        putIfSet(m, "headType",     h.headType() != null ? h.headType().name() : null);
        putIfSet(m, "headDiameter", h.headDiameter());
        return AttributeValue.fromM(m);
    }

    static AttributeValue toAttrMap(SizeDetails sz) {
        Map<String, AttributeValue> m = new HashMap<>();
        putIfSet(m, "length",          sz.length());
        putIfSet(m, "outsideDiameter", sz.outsideDiameter());
        putIfSet(m, "insideDiameter",  sz.insideDiameter());
        putIfSet(m, "thickness",       sz.thickness());
        putIfSet(m, "gauge",           sz.gauge());
        return AttributeValue.fromM(m);
    }

    static AttributeValue toAttrMap(ThreadDetails t) {
        Map<String, AttributeValue> m = new HashMap<>();
        putIfSet(m, "threadPitch", t.threadPitch());
        putIfSet(m, "threadType",  t.threadType() != null ? t.threadType().name() : null);
        putIfSet(m, "shankType",   t.shankType() != null ? t.shankType().name() : null);
        return AttributeValue.fromM(m);
    }

    static AttributeValue toAttrMap(RetailData r) {
        Map<String, AttributeValue> m = new HashMap<>();
        putIfSet(m, "upc",     r.upc());
        putIfSet(m, "sku",     r.sku());
        putIfSet(m, "company", r.company());
        return AttributeValue.fromM(m);
    }

    private static HeadDetails toHeadDetails(Map<String, AttributeValue> m) {
        String driveTypeStr = str(m, "driveType");
        String headTypeStr  = str(m, "headType");
        return new HeadDetails(
                driveTypeStr != null ? DriveType.valueOf(driveTypeStr) : null,
                headTypeStr  != null ? HeadType.valueOf(headTypeStr)   : null,
                str(m, "headDiameter"));
    }

    private static SizeDetails toSizeDetails(Map<String, AttributeValue> m) {
        return new SizeDetails(
                str(m, "length"),
                str(m, "outsideDiameter"),
                str(m, "insideDiameter"),
                str(m, "thickness"),
                str(m, "gauge"));
    }

    private static ThreadDetails toThreadDetails(Map<String, AttributeValue> m) {
        String threadTypeStr = str(m, "threadType");
        String shankTypeStr  = str(m, "shankType");
        return new ThreadDetails(
                str(m, "threadPitch"),
                threadTypeStr != null ? ThreadType.valueOf(threadTypeStr) : null,
                shankTypeStr  != null ? ShankType.valueOf(shankTypeStr)   : null);
    }

    private static RetailData toRetailData(Map<String, AttributeValue> m) {
        return new RetailData(str(m, "upc"), str(m, "sku"), str(m, "company"));
    }

    private static String str(Map<String, AttributeValue> m, String key) {
        AttributeValue v = m.get(key);
        return v != null ? v.s() : null;
    }

    private static void putIfSet(Map<String, AttributeValue> m, String key, String value) {
        if (value != null && !value.isBlank()) m.put(key, s(value));
    }

    private static AttributeValue s(String value) {
        return AttributeValue.fromS(value);
    }
}
