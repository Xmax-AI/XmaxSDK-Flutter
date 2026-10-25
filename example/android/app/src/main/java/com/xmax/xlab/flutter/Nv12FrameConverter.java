package com.xmax.xlab.flutter;

import java.nio.ByteBuffer;

/** Packs cropped YUV planes into upright NV12 with reusable scaling and rotation maps. */
final class Nv12FrameConverter {
    private final int outputWidth;
    private final int outputHeight;
    private final PlaneCache[] caches = {new PlaneCache(), new PlaneCache(), new PlaneCache()};

    Nv12FrameConverter(int outputWidth, int outputHeight) {
        if (outputWidth < 2 || outputHeight < 2 || (outputWidth | outputHeight) % 2 != 0) {
            throw new IllegalArgumentException("NV12 output dimensions must be positive and even");
        }
        this.outputWidth = outputWidth;
        this.outputHeight = outputHeight;
    }

    /** A decoded plane whose position, row padding, and pixel stride remain caller-owned. */
    static final class Plane {
        final ByteBuffer buffer;
        final int rowStride;
        final int pixelStride;

        Plane(ByteBuffer buffer, int rowStride, int pixelStride) {
            this.buffer = buffer;
            this.rowStride = rowStride;
            this.pixelStride = pixelStride;
        }
    }

    /** Returns owned frame bytes without changing the decoded buffers' positions or limits. */
    byte[] convert(Plane[] planes, int left, int top, int width, int height, int rotation) {
        if (planes.length != 3 || left < 0 || top < 0 || width < 2 || height < 2 ||
                (rotation != 0 && rotation != 90 && rotation != 180 && rotation != 270)) {
            throw new IllegalArgumentException("Invalid decoded YUV layout or rotation");
        }
        width = width / 2 * 2;
        height = height / 2 * 2;
        byte[] result = new byte[outputWidth * outputHeight * 3 / 2];

        for (int index = 0; index < 3; index++) {
            Plane plane = planes[index];
            if (plane.rowStride <= 0 || plane.pixelStride <= 0) {
                throw new IllegalArgumentException("Invalid decoded plane stride");
            }
            int divisor = index == 0 ? 1 : 2;
            int sourceWidth = width / divisor;
            int sourceHeight = height / divisor;
            int targetWidth = outputWidth / divisor;
            int targetHeight = outputHeight / divisor;
            int base = top / divisor * plane.rowStride + left / divisor * plane.pixelStride;
            ByteBuffer input = plane.buffer.duplicate();

            if (index == 0 && rotation == 0 && plane.pixelStride == 1 &&
                    sourceWidth == targetWidth && sourceHeight == targetHeight) {
                // Bulk-copy luma rows instead of calling a direct buffer once per pixel.
                int origin = input.position() + base;
                for (int y = 0; y < targetHeight; y++) {
                    input.position(origin + y * plane.rowStride);
                    input.get(result, y * targetWidth, targetWidth);
                }
                continue;
            }

            PlaneCache cache = caches[index];
            cache.configure(sourceWidth, sourceHeight, targetWidth, targetHeight,
                    plane.rowStride, plane.pixelStride, rotation);
            int size = input.remaining();
            if (base + cache.maximumOffset >= size) {
                throw new IllegalArgumentException("Decoded plane does not contain the requested crop");
            }
            if (cache.pixels.length < size) cache.pixels = new byte[size];
            input.get(cache.pixels, 0, size);

            int step = index == 0 ? 1 : 2;
            int destination = index == 0 ? 0 : outputWidth * outputHeight + index - 1;
            for (int y = 0; y < targetHeight; y++) {
                int row = base + cache.yOffsets[y];
                for (int x = 0; x < targetWidth; x++) {
                    result[destination + x * step] = cache.pixels[row + cache.xOffsets[x]];
                }
                destination += targetWidth * step;
            }
        }
        return result;
    }

    /** Retains scratch storage and separable pixel mappings while the decoded layout is unchanged. */
    private static final class PlaneCache {
        byte[] pixels = new byte[0];
        int[] xOffsets = new int[0];
        int[] yOffsets = new int[0];
        int width, height, rowStride, pixelStride, rotation, maximumOffset;

        void configure(int width, int height, int targetWidth, int targetHeight,
                int rowStride, int pixelStride, int rotation) {
            if (this.width == width && this.height == height && this.rowStride == rowStride &&
                    this.pixelStride == pixelStride && this.rotation == rotation &&
                    xOffsets.length == targetWidth && yOffsets.length == targetHeight) return;

            this.width = width;
            this.height = height;
            this.rowStride = rowStride;
            this.pixelStride = pixelStride;
            this.rotation = rotation;
            xOffsets = new int[targetWidth];
            yOffsets = new int[targetHeight];
            boolean quarterTurn = rotation == 90 || rotation == 270;
            int orientedWidth = quarterTurn ? height : width;
            int orientedHeight = quarterTurn ? width : height;
            int maxX = 0, maxY = 0;
            for (int x = 0; x < targetWidth; x++) {
                int coordinate = (int) ((long) x * orientedWidth / targetWidth);
                xOffsets[x] = rotation == 90 ? (height - 1 - coordinate) * rowStride
                        : rotation == 270 ? coordinate * rowStride
                        : (rotation == 180 ? width - 1 - coordinate : coordinate) * pixelStride;
                maxX = Math.max(maxX, xOffsets[x]);
            }
            for (int y = 0; y < targetHeight; y++) {
                int coordinate = (int) ((long) y * orientedHeight / targetHeight);
                yOffsets[y] = rotation == 90 ? coordinate * pixelStride
                        : rotation == 270 ? (width - 1 - coordinate) * pixelStride
                        : (rotation == 180 ? height - 1 - coordinate : coordinate) * rowStride;
                maxY = Math.max(maxY, yOffsets[y]);
            }
            maximumOffset = maxX + maxY;
        }
    }
}
