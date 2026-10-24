import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/render/video/VideoTextureFrameObserver.dart';

void main() {
  testWidgets('waits for a nonempty texture, then notifies once after paint', (
    tester,
  ) async {
    final binding = Object();
    var calls = 0;
    Widget view(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: VideoTextureFrameObserver(
        binding: binding,
        onFirstFrameRendered: () => calls++,
        child: child,
      ),
    );

    await tester.pumpWidget(view(const SizedBox.expand()));
    expect(calls, 0);
    await tester.pumpWidget(
      view(const Center(child: SizedBox.shrink(child: Texture(textureId: 1)))),
    );
    expect(calls, 0);
    await tester.pumpWidget(view(const Texture(textureId: 1)));
    expect(calls, 1);
    await tester.pumpWidget(view(const Texture(textureId: 1)));
    await tester.pump();
    expect(calls, 1);
  });

  for (final hidden in ['offstage', 'transparent']) {
    testWidgets('does not report a $hidden texture as displayed', (
      tester,
    ) async {
      final binding = Object();
      var calls = 0;
      Widget view(bool visible) => Directionality(
        textDirection: TextDirection.ltr,
        child: VideoTextureFrameObserver(
          binding: binding,
          onFirstFrameRendered: () => calls++,
          child: hidden == 'offstage'
              ? Offstage(offstage: !visible, child: const Texture(textureId: 1))
              : Opacity(
                  opacity: visible ? 1 : 0,
                  child: const Texture(textureId: 1),
                ),
        ),
      );
      await tester.pumpWidget(view(false));
      expect(calls, 0);
      await tester.pumpWidget(view(true));
      expect(calls, 1);
    });
  }

  testWidgets('new binding observes a fresh frame without native callbacks', (
    tester,
  ) async {
    var calls = 0;
    Widget view(Object binding) => Directionality(
      textDirection: TextDirection.ltr,
      child: VideoTextureFrameObserver(
        binding: binding,
        onFirstFrameRendered: () => calls++,
        child: const Texture(textureId: 1),
      ),
    );
    await tester.pumpWidget(view(Object()));
    expect(calls, 1);
    await tester.pumpWidget(view(Object()));
    expect(calls, 2);
  });

  testWidgets('callback can safely update the parent loading UI', (
    tester,
  ) async {
    final binding = Object();
    var loading = true;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) => Stack(
            fit: StackFit.expand,
            children: [
              VideoTextureFrameObserver(
                binding: binding,
                onFirstFrameRendered: () => setState(() => loading = false),
                child: const Texture(textureId: 1),
              ),
              if (loading) const Text('Loading'),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Loading'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
