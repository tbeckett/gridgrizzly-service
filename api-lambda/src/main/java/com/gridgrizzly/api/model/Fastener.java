package com.gridgrizzly.api.model;

public record Fastener(
        String id,
        FastenerType type,
        String title,
        int binNumber,
        UnitOfMeasure unitOfMeasure,
        String description,
        String usageDescription,
        String finish,
        String material,
        String[] fastenerSubTypes,
        HeadDetails headDetails,
        SizeDetails sizeDetails,
        ThreadDetails threadDetails,
        RetailData retailData
) {
}
