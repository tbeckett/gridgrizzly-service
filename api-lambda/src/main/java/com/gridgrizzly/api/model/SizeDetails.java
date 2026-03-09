package com.gridgrizzly.api.model;

public record SizeDetails(
        String length,
        String outsideDiameter,
        String insideDiameter,
        String thickness,
        String gauge
) {
}
