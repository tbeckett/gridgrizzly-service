package com.gridgrizzly.api.model;

public record Fastener(
        String id,
        FastenerType type,
        String title,
        UnitOfMeasure unitOfMeasure,
        String description,
        String usageDescription,
        String finish,
        String material,
        FastenerDetails details,
        RetailData retailData
) {}
