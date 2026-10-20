import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../localization/xlab_localization.dart';

const _referenceBackgroundColor = Color(0xFF303032);

enum XLabRealtimeReferenceUploadState { ready, uploading, failed }

enum XLabRealtimePanelMode {
  character('charx', '视频中角色替换成参考图中角色'),
  clothing('clothx', '视频中人物衣服替换成参考图中衣服'),
  style('vibex', '视频风格变为参考图指定的风格'),
  summon('dimx', '指定角色在场景中互动'),
  touch('mox', '角色沿着拖拽轨迹运动，位置贴合轨迹，运动过渡自然'),
  free('free', '');

  const XLabRealtimePanelMode(this.id, this.prompt);

  final String id;
  final String prompt;

  String get label => XLabLocalization.shared.text('category.$id');

  bool get usesReferences => switch (this) {
    character || clothing || style || summon => true,
    touch || free => false,
  };
}

final class XLabRealtimeReference {
  XLabRealtimeReference({
    required this.id,
    required this.categoryID,
    required this.title,
    required this.referencePath,
    this.iconURL,
    this.iconBytes,
    this.sourceURL,
    this.uploadState = XLabRealtimeReferenceUploadState.ready,
  });

  final String id;
  final String categoryID;
  final String title;
  String? referencePath;
  final String? iconURL;
  final Uint8List? iconBytes;
  final Uri? sourceURL;
  XLabRealtimeReferenceUploadState uploadState;

  bool get isReady =>
      uploadState == XLabRealtimeReferenceUploadState.ready &&
      referencePath != null;

  factory XLabRealtimeReference.fromJson(Map<String, dynamic> json) =>
      XLabRealtimeReference(
        id: json['id'] as String,
        categoryID: json['categoryID'] as String,
        title: json['title'] as String,
        iconURL: json['iconURL'] as String,
        referencePath: json['referencePath'] as String,
      );
}

Future<List<XLabRealtimeReference>> loadXLabRealtimeReferences() async {
  final catalog =
      jsonDecode(
            await rootBundle.loadString(
              'assets/realtime_reference_catalog.json',
            ),
          )
          as Map<String, dynamic>;
  final items = catalog['items'] as List<dynamic>;
  return items
      .cast<Map<String, dynamic>>()
      .map(XLabRealtimeReference.fromJson)
      .toList(growable: false);
}

final class XLabRealtimeControlPanel extends StatelessWidget {
  const XLabRealtimeControlPanel({
    required this.mode,
    required this.generating,
    required this.busy,
    this.enabled = true,
    required this.promptController,
    required this.referencesByCategory,
    required this.selectedReference,
    required this.onModeChanged,
    required this.onStop,
    required this.onReferenceChanged,
    required this.onAddReference,
    required this.onTouchStart,
    required this.onPromptSubmit,
    required this.onPromptReference,
    this.promptReference,
    super.key,
  });

  final XLabRealtimePanelMode mode;
  final bool generating;
  final bool busy;
  final bool enabled;
  final TextEditingController promptController;
  final Map<String, List<XLabRealtimeReference>> referencesByCategory;
  final XLabRealtimeReference? selectedReference;
  final XLabRealtimeReference? promptReference;
  final ValueChanged<XLabRealtimePanelMode> onModeChanged;
  final VoidCallback onStop;
  final ValueChanged<XLabRealtimeReference> onReferenceChanged;
  final VoidCallback onAddReference;
  final VoidCallback onTouchStart;
  final VoidCallback onPromptSubmit;
  final VoidCallback onPromptReference;

  void _submitPrompt() {
    unawaited(HapticFeedback.lightImpact());
    onPromptSubmit();
  }

  @override
  Widget build(BuildContext context) => Opacity(
    key: const ValueKey<String>('realtime-control-panel-enabled-state'),
    opacity: enabled ? 1 : 0.55,
    child: IgnorePointer(
      ignoring: !enabled,
      child: ColoredBox(
        color: const Color(0xFF101010),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 6),
              SizedBox(
                height: 36,
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 28,
                      height: 36,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: XLabLocalization.shared.text(
                          'realtime.generation.stop',
                        ),
                        onPressed: generating && !busy ? onStop : null,
                        icon: Icon(
                          Icons.block,
                          size: 16,
                          color: Colors.white.withValues(
                            alpha: generating ? 1 : 0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(right: 14),
                        itemCount: XLabRealtimePanelMode.values.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 16),
                        itemBuilder: (context, index) {
                          final item = XLabRealtimePanelMode.values[index];
                          final selected = item == mode;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onModeChanged(item),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Center(
                                child: Text(
                                  item.label,
                                  style: TextStyle(
                                    color: Colors.white.withValues(
                                      alpha: selected ? 1 : 0.48,
                                    ),
                                    fontSize: 12,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(height: 50, child: _categoryContents()),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _categoryContents() => Stack(
    fit: StackFit.expand,
    children: <Widget>[
      for (final item in XLabRealtimePanelMode.values)
        Offstage(
          key: ValueKey<String>('category-content-${item.id}'),
          offstage: item != mode,
          child: TickerMode(
            enabled: item == mode,
            child: _content(item, isVisible: item == mode),
          ),
        ),
    ],
  );

  Widget _content(XLabRealtimePanelMode item, {required bool isVisible}) {
    if (item.usesReferences) {
      return _ReferenceStrip(
        key: ValueKey<String>('reference-strip-${item.id}'),
        references:
            referencesByCategory[item.id] ?? const <XLabRealtimeReference>[],
        selectedReference: selectedReference,
        isVisible: isVisible,
        onReferenceChanged: onReferenceChanged,
        onAddReference: onAddReference,
      );
    }
    if (item == XLabRealtimePanelMode.touch) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: SizedBox.expand(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white.withValues(
                alpha: generating ? 0.09 : 0.14,
              ),
              foregroundColor: Colors.white.withValues(
                alpha: generating ? 0.40 : 0.85,
              ),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.19)),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            onPressed: generating || busy ? null : onTouchStart,
            child: Text(
              XLabLocalization.shared.text(
                generating
                    ? 'realtime.generation.drag'
                    : 'realtime.generation.start',
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF272728),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 11),
            Expanded(
              child: TextField(
                controller: promptController,
                maxLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submitPrompt(),
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration.collapsed(
                  hintText: XLabLocalization.shared.text(
                    'realtime.prompt.placeholder',
                  ),
                  hintStyle: const TextStyle(
                    color: Color(0x80FFFFFF),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _CircleAction(
              tooltip: switch (promptReference?.uploadState) {
                null => XLabLocalization.shared.text(
                  'realtime.reference.prompt.add',
                ),
                XLabRealtimeReferenceUploadState.uploading =>
                  XLabLocalization.shared.text(
                    'realtime.reference.prompt.uploading',
                  ),
                XLabRealtimeReferenceUploadState.failed =>
                  XLabLocalization.shared.text(
                    'realtime.reference.prompt.retry',
                  ),
                XLabRealtimeReferenceUploadState.ready =>
                  XLabLocalization.shared.text(
                    'realtime.reference.prompt.delete',
                  ),
              },
              backgroundColor: const Color(0x1FFFFFFF),
              disabledOpacity: 1,
              onPressed:
                  busy ||
                      promptReference?.uploadState ==
                          XLabRealtimeReferenceUploadState.uploading
                  ? null
                  : onPromptReference,
              child: promptReference == null
                  ? const Icon(Icons.add, color: Colors.white, size: 18)
                  : _PromptReferencePreview(reference: promptReference!),
            ),
            const SizedBox(width: 8),
            _CircleAction(
              tooltip: XLabLocalization.shared.text('realtime.prompt.submit'),
              backgroundColor: const Color(0xFFFF2E88),
              onPressed:
                  busy ||
                      promptController.text.trim().isEmpty ||
                      (promptReference != null && !promptReference!.isReady)
                  ? null
                  : _submitPrompt,
              child: const Icon(
                Icons.arrow_upward_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

final class _ReferenceStrip extends StatefulWidget {
  const _ReferenceStrip({
    required this.references,
    required this.selectedReference,
    required this.isVisible,
    required this.onReferenceChanged,
    required this.onAddReference,
    super.key,
  });

  final List<XLabRealtimeReference> references;
  final XLabRealtimeReference? selectedReference;
  final bool isVisible;
  final ValueChanged<XLabRealtimeReference> onReferenceChanged;
  final VoidCallback onAddReference;

  @override
  State<_ReferenceStrip> createState() => _ReferenceStripState();
}

final class _ReferenceStripState extends State<_ReferenceStrip> {
  final Map<String, GlobalKey> _referenceKeys = <String, GlobalKey>{};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.isVisible) _scheduleCenterSelectedReference();
  }

  @override
  void didUpdateWidget(covariant _ReferenceStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIndex = _selectedIndex(oldWidget);
    final newIndex = _selectedIndex(widget);
    if (widget.isVisible &&
        (!oldWidget.isVisible ||
            oldWidget.selectedReference?.id != widget.selectedReference?.id ||
            oldIndex != newIndex)) {
      _scheduleCenterSelectedReference();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int _selectedIndex(_ReferenceStrip target) {
    final selectedID = target.selectedReference?.id;
    if (selectedID == null) return -1;
    return target.references.indexWhere((item) => item.id == selectedID);
  }

  void _selectReference(XLabRealtimeReference reference) {
    unawaited(HapticFeedback.selectionClick());
    widget.onReferenceChanged(reference);
  }

  void _scheduleCenterSelectedReference() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selectedID = widget.selectedReference?.id;
      if (selectedID == null) return;
      final itemContext = _referenceKeys[selectedID]?.currentContext;
      if (itemContext == null) return;
      Scrollable.ensureVisible(
        itemContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  @override
  Widget build(BuildContext context) => ListView.separated(
    controller: _scrollController,
    scrollDirection: Axis.horizontal,
    clipBehavior: Clip.none,
    padding: const EdgeInsets.only(left: 14, right: 14, bottom: 6),
    itemCount: widget.references.length + 1,
    separatorBuilder: (_, _) => const SizedBox(width: 10),
    itemBuilder: (context, index) {
      if (index == 0) {
        return _AddReferenceButton(onPressed: widget.onAddReference);
      }
      final reference = widget.references[index - 1];
      final selected = widget.selectedReference?.id == reference.id;
      return GestureDetector(
        key: _referenceKeys.putIfAbsent(reference.id, GlobalKey.new),
        onTap: () => _selectReference(reference),
        child: Container(
          key: ValueKey<String>('reference-${reference.id}'),
          width: 44,
          height: 44,
          color: Colors.transparent,
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: ColoredBox(
                  color: _referenceBackgroundColor,
                  child: _ReferenceImage(reference: reference),
                ),
              ),
              _ReferenceUploadOverlay(
                key: ValueKey<String>('reference-upload-state-${reference.id}'),
                state: reference.uploadState,
                borderRadius: BorderRadius.circular(9),
              ),
              if (selected)
                Positioned(
                  top: -2,
                  right: -2,
                  bottom: -2,
                  left: -2,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: const Color(0xFFFF2E88),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

final class _AddReferenceButton extends StatelessWidget {
  const _AddReferenceButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey<String>('add-reference'),
    onTap: onPressed,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _referenceBackgroundColor,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.add, color: Colors.white, size: 19),
          SizedBox(
            width: 40,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                XLabLocalization.shared.text('realtime.reference.label'),
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(color: Colors.white, fontSize: 9),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _PromptReferencePreview extends StatelessWidget {
  const _PromptReferencePreview({required this.reference});

  final XLabRealtimeReference reference;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    key: const ValueKey<String>('prompt-reference-preview'),
    dimension: 28,
    child: Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _ReferenceImage(reference: reference, radius: 14),
        _ReferenceUploadOverlay(
          state: reference.uploadState,
          borderRadius: BorderRadius.circular(14),
          indicatorDimension: 13,
          retryIconSize: 14,
        ),
      ],
    ),
  );
}

final class _ReferenceUploadOverlay extends StatelessWidget {
  const _ReferenceUploadOverlay({
    required this.state,
    required this.borderRadius,
    this.indicatorDimension = 16,
    this.retryIconSize = 20,
    super.key,
  });

  final XLabRealtimeReferenceUploadState state;
  final BorderRadius borderRadius;
  final double indicatorDimension;
  final double retryIconSize;

  @override
  Widget build(BuildContext context) {
    if (state == XLabRealtimeReferenceUploadState.ready) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.42),
        child: Center(
          child: state == XLabRealtimeReferenceUploadState.uploading
              ? SizedBox.square(
                  dimension: indicatorDimension,
                  child: const CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  Icons.refresh_rounded,
                  color: Colors.white,
                  size: retryIconSize,
                ),
        ),
      ),
    );
  }
}

final class _ReferenceImage extends StatelessWidget {
  const _ReferenceImage({required this.reference, this.radius});

  final XLabRealtimeReference reference;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final bytes = reference.iconBytes;
    final url = reference.iconURL;
    final dimension = radius == null ? 44.0 : radius! * 2;
    final image = bytes != null
        ? Image.memory(
            bytes,
            width: dimension,
            height: dimension,
            fit: BoxFit.cover,
          )
        : url == null
        ? const ColoredBox(
            color: _referenceBackgroundColor,
            child: Icon(Icons.image_outlined, color: Colors.white54),
          )
        : CachedNetworkImage(
            imageUrl: url,
            width: dimension,
            height: dimension,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 200),
            placeholder: (_, _) =>
                const ColoredBox(color: _referenceBackgroundColor),
            errorWidget: (_, _, _) => const ColoredBox(
              color: _referenceBackgroundColor,
              child: Icon(Icons.image_outlined, color: Colors.white54),
            ),
          );
    final content = SizedBox.square(
      dimension: dimension,
      child: ColoredBox(color: _referenceBackgroundColor, child: image),
    );
    if (radius == null) return content;
    return ClipOval(child: content);
  }
}

final class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.backgroundColor = const Color(0xFF3A3A3C),
    this.disabledOpacity = 0.5,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;
  final Color backgroundColor;
  final double disabledOpacity;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? disabledOpacity : 1,
    child: SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor,
          disabledBackgroundColor: backgroundColor,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          shape: const CircleBorder(),
        ),
        onPressed: onPressed,
        icon: child,
      ),
    ),
  );
}
