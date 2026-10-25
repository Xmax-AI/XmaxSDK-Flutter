package com.xmax.xlab.flutter;
import java.nio.ByteBuffer;
import org.junit.Test;
import static org.junit.Assert.*;

public class I420FrameWriterTest {
    @Test public void writesSharedChromaInBothOrdersWithPaddingAndTruncatedFinalRow() {
        for (boolean uv : new boolean[]{true, false}) {
            for (boolean truncated : new boolean[]{true, false}) {
                byte[] source = new byte[24];
                for (int i = 0; i < source.length; i++) source[i] = (byte) (i + 1);
                ByteBuffer y = ByteBuffer.allocate(24), chroma = ByteBuffer.allocate(12);
                ByteBuffer first = chroma.duplicate(), second = chroma.duplicate();
                first.limit(truncated ? 9 : 10);
                second.position(1);
                second = second.slice();
                ByteBuffer u = uv ? first : second, v = uv ? second : first;
                new I420FrameWriter(4, 4).write(source,
                        new ByteBuffer[]{y, u, v}, new int[]{6, 6, 6}, new int[]{1, 2, 2});
                for (int row = 0; row < 4; row++)
                    for (int col = 0; col < 4; col++) assertEquals(source[row * 4 + col], y.get(row * 6 + col));
                for (int row = 0; row < 2; row++) for (int col = 0; col < 2; col++) {
                    assertEquals(source[16 + row * 2 + col], chroma.get(row * 6 + col * 2 + (uv ? 0 : 1)));
                    assertEquals(source[20 + row * 2 + col], chroma.get(row * 6 + col * 2 + (uv ? 1 : 0)));
                }
            }
        }
    }

    @Test public void writesIndependentPlanarAndStridedChromaWithoutGuessingSharedStorage() {
        for (int stride : new int[]{1, 2}) {
            byte[] source = new byte[24];
            for (int i = 0; i < source.length; i++) source[i] = (byte) (i + 1);
            ByteBuffer y = ByteBuffer.allocate(24), u = ByteBuffer.allocate(12), v = ByteBuffer.allocate(12);
            new I420FrameWriter(4, 4).write(source,
                    new ByteBuffer[]{y, u, v}, new int[]{6, 6, 6}, new int[]{1, stride, stride});
            for (int row = 0; row < 2; row++) for (int col = 0; col < 2; col++) {
                assertEquals(source[16 + row * 2 + col], u.get(row * 6 + col * stride));
                assertEquals(source[20 + row * 2 + col], v.get(row * 6 + col * stride));
            }
        }
    }
}
