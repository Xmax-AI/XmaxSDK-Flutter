package com.xmax.xlab.flutter;

import java.nio.ByteBuffer;

/** Writes planar input using bulk rows, including codecs whose U/V planes overlap. */
final class I420FrameWriter {
    private final int width, height;
    private final byte[] chromaRow;

    I420FrameWriter(int width, int height) {
        this.width = width;
        this.height = height;
        chromaRow = new byte[width];
    }

    void write(byte[] data, ByteBuffer[] planes, int[] strides, int[] pixels) {
        writePlane(planes[0], strides[0], pixels[0], data, 0, width, height);
        int cw = width / 2, ch = height / 2, size = width * height;
        ByteBuffer u = planes[1], v = planes[2];
        int ub = u.position(), vb = v.position();
        if (pixels[1] == 2 && pixels[2] == 2 && strides[1] == strides[2] && cw > 0 && ch > 0) {
            // Confirm shared storage by changing a marker, rather than guessing NV12/NV21.
            u.put(ub, (byte) 91);
            v.put(vb, (byte) 42);
            boolean uv = u.limit() > ub + 1 && u.get(ub + 1) == 42;
            v.put(vb, (byte) 43);
            uv = uv && u.get(ub + 1) == 43;
            u.put(ub, (byte) 92);
            boolean vu = v.limit() > vb + 1 && v.get(vb + 1) == 92;
            u.put(ub, (byte) 93);
            vu = vu && v.get(vb + 1) == 93;
            if (uv || vu) {
                ByteBuffer first = uv ? u : v;
                int base = uv ? ub : vb;
                for (int row = 0; row < ch; row++) {
                    int source = row * cw;
                    for (int column = 0; column < cw; column++) {
                        byte a = data[size + source + column], b = data[size + size / 4 + source + column];
                        chromaRow[column * 2] = uv ? a : b;
                        chromaRow[column * 2 + 1] = uv ? b : a;
                    }
                    int destination = base + row * strides[1];
                    int count = Math.min(width, first.limit() - destination);
                    first.position(destination);
                    first.put(chromaRow, 0, count);
                    if (count < width) {
                        ByteBuffer last = uv ? v : u;
                        int lastBase = uv ? vb : ub;
                        last.put(lastBase + row * strides[1] + (cw - 1) * 2, chromaRow[width - 1]);
                    }
                }
                return;
            }
        }
        writePlane(u, strides[1], pixels[1], data, size, cw, ch);
        writePlane(v, strides[2], pixels[2], data, size + size / 4, cw, ch);
    }

    private static void writePlane(ByteBuffer buffer, int stride, int pixelStride, byte[] data,
                                   int offset, int columns, int rows) {
        int base = buffer.position();
        for (int row = 0; row < rows; row++) {
            int destination = base + row * stride, source = offset + row * columns;
            if (pixelStride == 1) {
                buffer.position(destination);
                buffer.put(data, source, columns);
            } else {
                for (int column = 0; column < columns; column++)
                    buffer.put(destination + column * pixelStride, data[source + column]);
            }
        }
    }
}
