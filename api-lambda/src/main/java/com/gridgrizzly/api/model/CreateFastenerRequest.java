package com.gridgrizzly.api.model;

public record CreateFastenerRequest(
        FastenerType type,
        String title,
        UnitOfMeasure unitOfMeasure,
        String description,
        String usageDescription,
        FastenerDetails details,
        RetailData retailData,
        String finish,
        String material
) {}
