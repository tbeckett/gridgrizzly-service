package com.gridgrizzly.api.model;

public record HeadDetails(
        DriveType driveType,
        HeadType headType,
        String headDiameter
) {
}