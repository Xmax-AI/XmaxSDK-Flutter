package com.xmax.xlab.flutter;

import static org.junit.Assert.*;

import java.nio.ByteBuffer;
import java.util.Arrays;
import org.junit.Test;

public final class Nv12FrameConverterTest {
    @Test public void croppedPaddedAndRotatedPlanesMatchReferencePixels() {
        for (int pixelStride : new int[] {1, 2}) {
            for (int padding : new int[] {0, 5}) {
                for (boolean direct : new boolean[] {false, true}) {
                    Nv12FrameConverter.Plane[] planes = planes(10, 8, padding, pixelStride, direct);
                    for (int rotation : new int[] {0, 90, 180, 270}) {
                        for (int[] size : new int[][] {{6, 4}, {4, 6}, {8, 8}, {2, 2}}) {
                            byte[] actual = new Nv12FrameConverter(size[0], size[1])
                                    .convert(planes, 2, 2, 6, 4, rotation);
                            assertArrayEquals(reference(planes, 2, 2, 6, 4, rotation, size[0], size[1]), actual);
                        }
                    }
                }
            }
        }
    }

    @Test public void identityLumaUsesTheCorrectCroppedRows() {
        Nv12FrameConverter.Plane[] planes = planes(8, 6, 7, 2, true);
        byte[] actual = new Nv12FrameConverter(4, 4).convert(planes, 2, 2, 4, 4, 0);
        assertArrayEquals(reference(planes, 2, 2, 4, 4, 0, 4, 4), actual);
        assertEquals(sample(0, 2, 2), actual[0]);
        assertEquals(sample(0, 5, 5), actual[15]);
    }

    @Test public void interleavedNv21ViewsBecomeNv12WithoutLastRowPadding() {
        byte[] y = new byte[16];
        for (int i = 0; i < y.length; i++) y[i] = (byte) i;
        byte[] vu = {51, 11, 52, 12, 53, 13, 54, 14};
        ByteBuffer u = ByteBuffer.wrap(vu);
        u.position(1);
        Nv12FrameConverter.Plane[] planes = {
            new Nv12FrameConverter.Plane(ByteBuffer.wrap(y), 4, 1),
            new Nv12FrameConverter.Plane(u, 4, 2),
            new Nv12FrameConverter.Plane(ByteBuffer.wrap(vu), 4, 2),
        };
        byte[] actual = new Nv12FrameConverter(4, 4).convert(planes, 0, 0, 4, 4, 0);
        assertArrayEquals(y, Arrays.copyOf(actual, 16));
        assertArrayEquals(new byte[] {11, 51, 12, 52, 13, 53, 14, 54},
                Arrays.copyOfRange(actual, 16, actual.length));
    }

    @Test public void inputPositionsAndLimitsArePreserved() {
        Nv12FrameConverter.Plane[] planes = planes(10, 8, 3, 2, true);
        int[] positions = Arrays.stream(planes).mapToInt(p -> p.buffer.position()).toArray();
        int[] limits = Arrays.stream(planes).mapToInt(p -> p.buffer.limit()).toArray();
        new Nv12FrameConverter(6, 4).convert(planes, 2, 2, 6, 4, 90);
        for (int i = 0; i < planes.length; i++) {
            assertEquals(positions[i], planes[i].buffer.position());
            assertEquals(limits[i], planes[i].buffer.limit());
        }
    }

    @Test public void reusedConverterUpdatesLayoutMapsAndRetainsPreviousOutput() {
        Nv12FrameConverter converter = new Nv12FrameConverter(6, 4);
        Nv12FrameConverter.Plane[] first = planes(10, 8, 3, 2, true);
        byte[] previous = converter.convert(first, 2, 2, 6, 4, 90);
        byte[] snapshot = previous.clone();
        for (int rotation : new int[] {0, 180, 270, 90}) {
            Nv12FrameConverter.Plane[] next = planes(12, 10, 7, 1, false);
            byte[] actual = converter.convert(next, 4, 2, 8, 6, rotation);
            assertArrayEquals(reference(next, 4, 2, 8, 6, rotation, 6, 4), actual);
            assertNotSame(previous, actual);
            assertArrayEquals(snapshot, previous);
        }
    }

    @Test public void invalidDimensionsRotationAndTruncatedPlanesAreRejected() {
        assertThrows(IllegalArgumentException.class, () -> new Nv12FrameConverter(3, 4));
        assertThrows(IllegalArgumentException.class, () -> new Nv12FrameConverter(0, 4));
        Nv12FrameConverter converter = new Nv12FrameConverter(4, 4);
        Nv12FrameConverter.Plane[] planes = planes(4, 4, 0, 1, false);
        assertThrows(IllegalArgumentException.class, () -> converter.convert(planes, 0, 0, 4, 4, 45));
        planes[1].buffer.limit(planes[1].buffer.position() + 1);
        assertThrows(IllegalArgumentException.class, () -> converter.convert(planes, 0, 0, 4, 4, 0));
    }

    private static Nv12FrameConverter.Plane[] planes(int width, int height, int padding,
            int uvPixelStride, boolean direct) {
        Nv12FrameConverter.Plane[] planes = new Nv12FrameConverter.Plane[3];
        for (int i = 0; i < planes.length; i++) {
            int divisor = i == 0 ? 1 : 2;
            int w = width / divisor, h = height / divisor;
            int pixelStride = i == 0 ? 1 : uvPixelStride;
            int rowStride = w * pixelStride + padding;
            int prefix = i + 2;
            int length = prefix + (h - 1) * rowStride + (w - 1) * pixelStride + 1;
            ByteBuffer buffer = direct ? ByteBuffer.allocateDirect(length) : ByteBuffer.allocate(length);
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    buffer.put(prefix + y * rowStride + x * pixelStride, sample(i, x, y));
                }
            }
            buffer.position(prefix);
            planes[i] = new Nv12FrameConverter.Plane(buffer.asReadOnlyBuffer(), rowStride, pixelStride);
        }
        return planes;
    }

    private static byte sample(int plane, int x, int y) {
        return (byte) ((plane + 1) * 71 + y * 13 + x * 5);
    }

    private static byte[] reference(Nv12FrameConverter.Plane[] planes, int left, int top,
            int width, int height, int rotation, int outputWidth, int outputHeight) {
        byte[] result = new byte[outputWidth * outputHeight * 3 / 2];
        for (int plane = 0; plane < 3; plane++) {
            int divisor = plane == 0 ? 1 : 2;
            int w = width / divisor, h = height / divisor;
            int targetWidth = outputWidth / divisor, targetHeight = outputHeight / divisor;
            int orientedWidth = rotation == 90 || rotation == 270 ? h : w;
            int orientedHeight = rotation == 90 || rotation == 270 ? w : h;
            Nv12FrameConverter.Plane input = planes[plane];
            int base = input.buffer.position() + top / divisor * input.rowStride + left / divisor * input.pixelStride;
            for (int y = 0; y < targetHeight; y++) {
                for (int x = 0; x < targetWidth; x++) {
                    int ox = (int) ((long) x * orientedWidth / targetWidth);
                    int oy = (int) ((long) y * orientedHeight / targetHeight);
                    int sx = ox, sy = oy;
                    if (rotation == 90) { sx = oy; sy = h - 1 - ox; }
                    else if (rotation == 180) { sx = w - 1 - ox; sy = h - 1 - oy; }
                    else if (rotation == 270) { sx = w - 1 - oy; sy = ox; }
                    int index = y * targetWidth + x;
                    int destination = plane == 0 ? index : outputWidth * outputHeight + index * 2 + plane - 1;
                    result[destination] = input.buffer.get(base + sy * input.rowStride + sx * input.pixelStride);
                }
            }
        }
        return result;
    }
}
