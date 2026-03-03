package com.gridgrizzly.api.model;

public record FastenerDetails(
        String subType,
        String driveType,
        String threadPitch,
        String length,
        String outsideDiameter,
        String insideDiameter,
        String thickness,
        String gauge,
        String finish,
        String material
) {}
