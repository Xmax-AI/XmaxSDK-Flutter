import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

import '../../localization/xlab_localization.dart';
import '../../ui/xlab_theme.dart';
import '../realtime/realtime_local_input.dart';
import '../realtime/realtime_page.dart';
import '../storage/storage_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({this.pickImage, super.key});

  final Future<XFile?> Function()? pickImage;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _apiKeyStorageKey = 'xlab.realtime.apiKey';
  static const _modelStorageKey = 'xlab.realtime.model';
  static const _isImagePipelineEnabled = false;
  final _apiKeyController = TextEditingController();
  final _preferences = SharedPreferencesAsync();
  bool _obscureApiKey = true;
  bool _isPickingImage = false;
  RealtimeModel _selectedModel = RealtimeModel.x2_1_1_preview_cn;
  int _modelSelectionVersion = 0;

  List<RealtimeModel> get _availableModels =>
      XLabLocalization.shared.environment == XmaxEnvironment.china
      ? const [RealtimeModel.x2_1_1_preview_cn]
      : const [RealtimeModel.x2_1_1_preview_us];

  RealtimeModel get _activeModel => _availableModels.contains(_selectedModel)
      ? _selectedModel
      : _availableModels.first;

  String get _minimumOS => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android 8.0+',
    TargetPlatform.iOS => 'iOS 15+',
    _ => 'Android / iOS',
  };

  @override
  void initState() {
    super.initState();
    unawaited(_loadAPIKey());
    unawaited(_loadSelectedModel());
  }

  Future<void> _loadSelectedModel() async {
    final version = _modelSelectionVersion;
    final saved = await _preferences.getString(_modelStorageKey);
    if (!mounted || version != _modelSelectionVersion) return;

    final selected = RealtimeModel.values.firstWhere(
      (model) => model.value == saved,
      orElse: () => RealtimeModel.x2_1_1_preview_cn,
    );
    setState(() => _selectedModel = selected);
  }

  void _selectModel(RealtimeModel model) {
    if (model == _selectedModel) return;
    _modelSelectionVersion += 1;
    setState(() => _selectedModel = model);
    unawaited(_preferences.setString(_modelStorageKey, model.value));
  }

  Future<void> _loadAPIKey() async {
    final apiKey = await _preferences.getString(_apiKeyStorageKey) ?? '';
    if (!mounted) {
      return;
    }
    _apiKeyController.text = apiKey;
  }

  Future<void> _openAPIKeyApplicationPage() async {
    try {
      final opened = await launchUrl(
        XLabLocalization.shared.apiKeyApplicationURL,
        mode: LaunchMode.externalApplication,
      );
      if (opened || !mounted) {
        return;
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(XLabLocalization.shared.text('feed.api.openError')),
      ),
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  String? _apiKeyForNavigation() {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(XLabLocalization.shared.text('feed.api.required')),
        ),
      );
      return null;
    }
    unawaited(_preferences.setString(_apiKeyStorageKey, apiKey));
    return apiKey;
  }

  void _open(
    Widget Function(
      String apiKey,
      XmaxEnvironment environment,
      RealtimeModel model,
    )
    builder,
  ) {
    final apiKey = _apiKeyForNavigation();
    if (apiKey == null) return;
    final environment = XLabLocalization.shared.environment;
    final model = _activeModel;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => builder(apiKey, environment, model),
      ),
    );
  }

  Future<void> _openImagePipeline() async {
    if (_isPickingImage) return;

    final apiKey = _apiKeyForNavigation();
    if (apiKey == null) return;

    _isPickingImage = true;
    try {
      final image =
          await (widget.pickImage?.call() ??
              ImagePicker().pickImage(
                source: ImageSource.gallery,
                requestFullMetadata: false,
              ));
      if (image == null || !mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RealtimePage(
            apiKey: apiKey,
            environment: XLabLocalization.shared.environment,
            model: _activeModel,
            localInput: XLabRealtimeImageInput(
              path: image.path,
              name: image.name,
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(XLabLocalization.shared.text('feed.image.error')),
        ),
      );
    } finally {
      _isPickingImage = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Depend on MaterialApp's locale so changing language refreshes this page.
    Localizations.localeOf(context);
    final localization = XLabLocalization.shared;
    String t(String key) => localization.text(key);

    return Scaffold(
      body: XLabBackground(
        child: SafeArea(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
            children: <Widget>[
              XLabTopBar(
                title: 'XLAB',
                accent: XLabPalette.mint,
                version: XmaxSDKInfo.version,
                trailing: PopupMenuButton<XLabLanguage>(
                  key: const ValueKey<String>('language-menu'),
                  tooltip: '语言 / Language',
                  icon: const Icon(Icons.language, color: XLabPalette.mint),
                  onSelected: (language) =>
                      unawaited(localization.setLanguage(language)),
                  itemBuilder: (_) => XLabLanguage.values
                      .map(
                        (language) => CheckedPopupMenuItem<XLabLanguage>(
                          value: language,
                          checked: localization.language == language,
                          child: Text(localization.languageTitle(language)),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 34),
              _hero(),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Metric(label: t('feed.runtime'), value: 'Flutter'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Metric(label: t('feed.os'), value: _minimumOS),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Metric(
                      label: t('feed.latestModel'),
                      value: 'X2.1.1',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _modelRegistry(),
              const SizedBox(height: 30),
              _SectionHeader(
                title: t('feed.pipelines'),
                subtitle: t('feed.input'),
              ),
              const SizedBox(height: 14),
              _PipelineCard(
                sequence: '01',
                mode: 'MODE_01 / CAMERA',
                title: t('feed.camera.title'),
                subtitle: t('feed.camera.subtitle'),
                capability: 'createLocalCameraStream()',
                color: XLabPalette.mint,
                onTap: () => _open(
                  (apiKey, environment, model) => RealtimePage(
                    apiKey: apiKey,
                    environment: environment,
                    model: model,
                  ),
                ),
              ),
              if (_isImagePipelineEnabled) ...<Widget>[
                const SizedBox(height: 14),
                _PipelineCard(
                  sequence: '03',
                  mode: 'MODE_03 / IMAGE.FILE',
                  title: t('feed.image.title'),
                  subtitle: t('feed.image.subtitle'),
                  capability: 'createLocalImageStream()',
                  color: XLabPalette.purple,
                  onTap: () => unawaited(_openImagePipeline()),
                ),
              ],
              const SizedBox(height: 30),
              _SectionHeader(
                title: t('feed.features'),
                subtitle: t('feed.examples'),
              ),
              const SizedBox(height: 14),
              _FeatureCard(
                category: 'SDK SERVICE / STORAGE',
                watermark: 'URL',
                title: t('feed.storage.title'),
                subtitle: t('feed.storage.subtitle'),
                tags: const <String>['IMAGE', 'VIDEO', 'REMOTE URL'],
                color: XLabPalette.orange,
                icon: Icons.cloud_upload_outlined,
                iconLabel: 'UPLOAD',
                onTap: () => _open(
                  (apiKey, environment, _) =>
                      StoragePage(apiKey: apiKey, environment: environment),
                ),
              ),
              const SizedBox(height: 38),
              const Center(
                child: Column(
                  children: <Widget>[
                    SizedBox(
                      width: 36,
                      child: Divider(color: Color(0x18FFFFFF)),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Copyright © 2026 XMAX.AI PTE. LTD. All rights reserved.',
                      style: TextStyle(color: Color(0x50FFFFFF), fontSize: 9),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'sdk@xmax.ai',
                      style: TextStyle(color: Color(0x688EF0C8), fontSize: 9),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero() => XLabCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const SizedBox(
              width: 22,
              child: Divider(color: XLabPalette.mint, thickness: 2),
            ),
            const SizedBox(width: 8),
            const Text(
              'XMAX PLAYGROUND',
              style: TextStyle(
                color: XLabPalette.mint,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          XLabLocalization.shared.text('feed.hero.title'),
          style: TextStyle(
            color: XLabPalette.primaryText,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          XLabLocalization.shared.text('feed.hero.subtitle'),
          style: TextStyle(color: Color(0xFF91A0B2), fontSize: 12),
        ),
      ],
    ),
  );

  Widget _modelRegistry() => XLabCard(
    accent: XLabPalette.mint,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                XLabLocalization.shared.text('feed.model.title'),
                style: TextStyle(
                  color: Color(0xFFE9EDF3),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              XLabLocalization.shared.formatCount(
                'feed.model.count',
                _availableModels.length,
              ),
              style: TextStyle(
                color: Color(0x70FFFFFF),
                fontSize: 8,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0x42080C12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x12FFFFFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'API KEY',
                style: TextStyle(
                  color: Color(0xFF7E8A9A),
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: TextField(
                  key: const ValueKey<String>('api-key-field'),
                  controller: _apiKeyController,
                  obscureText: _obscureApiKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (value) => unawaited(
                    _preferences.setString(_apiKeyStorageKey, value),
                  ),
                  cursorColor: XLabPalette.mint,
                  style: const TextStyle(
                    color: Color(0xFFD6DEE9),
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    hintText: XLabLocalization.shared.text(
                      'feed.api.placeholder',
                    ),
                    hintStyle: const TextStyle(
                      color: Color(0x80607080),
                      fontSize: 12,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0x66080C12),
                    contentPadding: const EdgeInsets.only(left: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0x1CFFFFFF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0x1CFFFFFF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0x1CFFFFFF)),
                    ),
                    suffixIconConstraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                    suffixIcon: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: XLabLocalization.shared.text(
                        _obscureApiKey ? 'feed.api.show' : 'feed.api.hide',
                      ),
                      onPressed: () =>
                          setState(() => _obscureApiKey = !_obscureApiKey),
                      icon: Icon(
                        _obscureApiKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: const Color(0xC7D6DEE9),
                        size: 19,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: <Widget>[
                  Text(
                    XLabLocalization.shared.text('feed.api.prompt'),
                    style: TextStyle(color: Color(0x99708090), fontSize: 9),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: TextButton(
                      key: const ValueKey<String>('api-key-platform-link'),
                      onPressed: _openAPIKeyApplicationPage,
                      style: TextButton.styleFrom(
                        foregroundColor: XLabPalette.mint.withValues(
                          alpha: 0.63,
                        ),
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 9),
                      ),
                      child: Text(
                        XLabLocalization.shared.text('feed.api.link'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final model in _availableModels) ...<Widget>[
          if (model != _availableModels.first) const SizedBox(height: 4),
          _ModelOptionRow(
            model: model,
            selected: model == _activeModel,
            onTap: () => _selectModel(model),
          ),
        ],
      ],
    ),
  );
}

final class _ModelOptionRow extends StatelessWidget {
  const _ModelOptionRow({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final RealtimeModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      key: ValueKey<String>('model-${model.value}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? XLabPalette.mint.withValues(alpha: 0.063)
              : Colors.white.withValues(alpha: 0.025),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? XLabPalette.mint.withValues(alpha: 0.16)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: <Widget>[
            const Text(
              '◆',
              style: TextStyle(color: XLabPalette.mint, fontSize: 8),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    model.displayName,
                    style: const TextStyle(
                      color: Color(0xFFF0F2F5),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'RealtimeModel.${model.value.replaceAll(RegExp(r'[.-]'), '_')}',
                    style: const TextStyle(
                      color: Color(0x70FFFFFF),
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              XLabPill(
                XLabLocalization.shared.text('feed.selected'),
                color: XLabPalette.mint,
              ),
          ],
        ),
      ),
    ),
  );
}

final class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    height: 66,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: const Color(0xB30E141C),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: const Color(0x17FFFFFF)),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: Color(0x62FFFFFF),
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 7),
        FittedBox(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFFE8EDF5),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

final class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        title,
        style: const TextStyle(
          color: Color(0xFFC6D0DD),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF667384), fontSize: 11),
      ),
    ],
  );
}

final class _PipelineCard extends StatelessWidget {
  const _PipelineCard({
    required this.sequence,
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.capability,
    required this.color,
    required this.onTap,
  });
  final String sequence;
  final String mode;
  final String title;
  final String subtitle;
  final String capability;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => XLabCard(
    accent: color,
    onTap: onTap,
    child: Stack(
      children: <Widget>[
        Positioned(
          right: 0,
          top: 18,
          child: Text(
            sequence,
            style: const TextStyle(
              color: Color(0x0AFFFFFF),
              fontSize: 58,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.circle, color: color, size: 7),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mode,
                    style: const TextStyle(
                      color: Color(0xFF9AA7B7),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                XLabPill(
                  XLabLocalization.shared.text('feed.ready'),
                  color: color,
                ),
              ],
            ),
            const SizedBox(height: 17),
            Text(
              title,
              style: const TextStyle(
                color: XLabPalette.primaryText,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              style: const TextStyle(
                color: XLabPalette.secondaryText,
                height: 1.5,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: Container(
                    height: 36,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    decoration: BoxDecoration(
                      color: const Color(0x66080C12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x16FFFFFF)),
                    ),
                    child: FittedBox(
                      child: Text(
                        capability,
                        style: const TextStyle(
                          color: Color(0xFFB8C3D1),
                          fontSize: 9,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 82,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    XLabLocalization.shared.text('feed.run'),
                    style: TextStyle(
                      color: Color(0xFF08110E),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

final class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.category,
    required this.watermark,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.color,
    required this.icon,
    required this.iconLabel,
    required this.onTap,
  });
  final String category;
  final String watermark;
  final String title;
  final String subtitle;
  final List<String> tags;
  final Color color;
  final IconData icon;
  final String iconLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => XLabCard(
    accent: color,
    padding: EdgeInsets.zero,
    gradient: const LinearGradient(
      colors: <Color>[Color(0xF01C1813), Color(0xF00D1117), Color(0xF0151210)],
    ),
    borderColor: const Color(0x21FFFFFF),
    clipBehavior: Clip.antiAlias,
    onTap: onTap,
    child: Stack(
      children: <Widget>[
        Positioned(
          right: -40,
          top: -52,
          child: Container(
            width: 126,
            height: 126,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: -9,
          child: Text(
            watermark,
            style: const TextStyle(
              color: Color(0x08FFFFFF),
              fontSize: 45,
              fontWeight: FontWeight.bold,
              letterSpacing: -2,
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 47,
          child: Container(
            width: 3,
            height: 54,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(color: color, blurRadius: 7),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      category,
                      style: const TextStyle(
                        color: Color(0xFFA99A8A),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  _FeatureAvailablePill(color: color),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          color.withValues(alpha: 0.28),
                          const Color(0x471B1712),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: color.withValues(alpha: 0.28)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(icon, color: color, size: 24),
                        const SizedBox(height: 1),
                        Text(
                          iconLabel,
                          style: TextStyle(
                            color: color,
                            fontSize: 6,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: const TextStyle(
                            color: XLabPalette.primaryText,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitle,
                          maxLines: 2,
                          style: const TextStyle(
                            color: Color(0xFF81786F),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 58,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      XLabLocalization.shared.text('feed.open'),
                      style: TextStyle(
                        color: Color(0xFF08110E),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: tags
                    .map(
                      (tag) => _FeatureTag(
                        tag,
                        color: color,
                        highlighted: tag == tags.last,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

final class _FeatureAvailablePill extends StatelessWidget {
  const _FeatureAvailablePill({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    height: 25,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: const Color(0x0CFFFFFF),
      borderRadius: BorderRadius.circular(12.5),
      border: Border.all(color: const Color(0x2EFFFFFF)),
    ),
    child: Text(
      XLabLocalization.shared.text('feed.available'),
      style: TextStyle(
        color: color,
        fontSize: 8,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.7,
      ),
    ),
  );
}

final class _FeatureTag extends StatelessWidget {
  const _FeatureTag(
    this.text, {
    required this.color,
    required this.highlighted,
  });

  final String text;
  final Color color;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
    height: 24,
    padding: const EdgeInsets.symmetric(horizontal: 9),
    decoration: BoxDecoration(
      color: highlighted ? const Color(0x12FFFFFF) : const Color(0x66080C12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0x17FFFFFF)),
    ),
    child: Center(
      widthFactor: 1,
      child: Text(
        text,
        style: TextStyle(
          color: highlighted ? color : const Color(0xFFA89A8B),
          fontSize: 7,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}
