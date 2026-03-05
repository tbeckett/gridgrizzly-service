package com.gridgrizzly.api.model;

public record FastenerDetails(
        String subType,
        String driveType,
        HeadType headType,
        String threadPitch,
        ThreadType threadType,
        String length,
        String outsideDiameter,
        String insideDiameter,
        String thickness,
        String gauge,
        String finish,
        String material
) {}
