package com.gridgrizzly.api.model;

public record CreateFastenerRequest(
        FastenerType type,
        String title,
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
) {}
