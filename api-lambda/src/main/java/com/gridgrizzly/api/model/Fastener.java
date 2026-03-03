package com.gridgrizzly.api.model;

public record Fastener(
        String id,
        FastenerType type,
        String title,
        UnitOfMeasure unitOfMeasure,
        String description,
        String usageDescription,
        FastenerDetails details,
        RetailData retailData
) {}
