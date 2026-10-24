import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

/// XLab 的界面语言；选项与 iOS XLab 保持一致。
enum XLabLanguage { system, simplifiedChinese, english }

/// XLab 的界面语言设置。中文界面连接国内环境，英文界面连接海外环境。
final class XLabLocalization extends ChangeNotifier {
  XLabLocalization._();

  static final XLabLocalization shared = XLabLocalization._();
  static const _storageKey = 'xlab.language';

  XLabLanguage _language = XLabLanguage.system;
  int _selectionVersion = 0;

  XLabLanguage get language => _language;

  String get languageCode {
    if (_language == XLabLanguage.simplifiedChinese) return 'zh-Hans';
    if (_language == XLabLanguage.english) return 'en';
    return WidgetsBinding.instance.platformDispatcher.locale.languageCode ==
            'zh'
        ? 'zh-Hans'
        : 'en';
  }

  Locale get locale =>
      languageCode == 'zh-Hans' ? const Locale('zh') : const Locale('en');

  XmaxEnvironment get environment => languageCode == 'zh-Hans'
      ? XmaxEnvironment.china
      : XmaxEnvironment.global;

  Uri get apiKeyApplicationURL => Uri.parse(
    environment == XmaxEnvironment.china
        ? 'https://platform.xmaxai.com/api-keys'
        : 'https://platform.xmax.ai/api-keys',
  );

  Future<void> load() async {
    final version = _selectionVersion;
    final saved = await SharedPreferencesAsync().getString(_storageKey);
    if (version != _selectionVersion) return;
    final next = switch (saved) {
      'zh-Hans' => XLabLanguage.simplifiedChinese,
      'en' => XLabLanguage.english,
      _ => XLabLanguage.system,
    };
    if (_language == next) return;
    _language = next;
    notifyListeners();
  }

  Future<void> setLanguage(XLabLanguage language) async {
    if (_language == language) return;
    _selectionVersion += 1;
    _language = language;
    notifyListeners();
    await SharedPreferencesAsync().setString(_storageKey, switch (language) {
      XLabLanguage.system => 'system',
      XLabLanguage.simplifiedChinese => 'zh-Hans',
      XLabLanguage.english => 'en',
    });
  }

  void systemLocaleDidChange() {
    if (_language == XLabLanguage.system) notifyListeners();
  }

  String languageTitle(XLabLanguage language) => switch (language) {
    XLabLanguage.system => text('language.system'),
    XLabLanguage.simplifiedChinese => '简体中文',
    XLabLanguage.english => 'English',
  };

  String text(String key) {
    final catalog = languageCode == 'zh-Hans' ? _chinese : _english;
    return catalog[key] ?? key;
  }

  String formatCount(String key, int count) =>
      text(key).replaceFirst('%d', count.toString()).replaceAll('%%', '%');

  static const _chinese = <String, String>{
    'statistics.title': '统计',
    'statistics.level.hint': 'L1 最高 · L5 最低，手动调整后仍会自动调档。',
    'statistics.uplink': '上行视频',
    'statistics.downlink': '下行视频',
    'statistics.resolution': '分辨率',
    'statistics.captureFPS': '采集帧率',
    'statistics.encodeFPS': '编码帧率',
    'statistics.sendFPS': '发送帧率',
    'statistics.decodeFPS': '解码帧率',
    'statistics.renderFPS': '渲染帧率',
    'statistics.bitrate': '码率',
    'statistics.loss': '丢包率',
    'statistics.quality': '网络质量',
    'statistics.delay': '端到端（RTC）',
    'statistics.quality.excellent': '优秀',
    'statistics.quality.good': '良好',
    'statistics.quality.poor': '较差',
    'statistics.quality.bad': '很差',
    'statistics.quality.veryBad': '极差',
    'statistics.quality.down': '中断',
    'language.system': '跟随系统',
    'common.home': '返回首页',
    'category.charx': '换形象',
    'category.clothx': '换装',
    'category.vibex': '换风格',
    'category.dimx': '虚拟召唤',
    'category.mox': '触控动图',
    'category.free': '自由',
    'media.image': '图片',
    'media.video': '视频',
    'feed.api.hide': '隐藏 API Key',
    'feed.api.link': '前往 Xmax 开放平台申请',
    'feed.api.placeholder': '输入 Xmax API Key',
    'feed.api.prompt': '还没有 API Key？',
    'feed.api.required': '请先输入 API Key',
    'feed.api.show': '显示 API Key',
    'feed.api.openError': '无法打开 Xmax 开放平台',
    'feed.available': '可用',
    'feed.camera.subtitle': '实时采集摄像头画面，持续驱动视频生成。',
    'feed.camera.title': '摄像头实时流',
    'feed.examples': '更多能力与接入示例',
    'feed.features': 'SDK 功能',
    'feed.hero.subtitle': '体验 XmaxSDK 流式生成链路',
    'feed.hero.title': '实时交互视频模型',
    'feed.image.error': '读取图片失败，请重试',
    'feed.image.subtitle': '选择本地图片，让静态画面持续流动起来。',
    'feed.image.title': '图片生成管线',
    'feed.input': '选择一种内容输入方式',
    'feed.latestModel': '最新模型',
    'feed.model.count': '模型：%d',
    'feed.model.title': '选择你的模型',
    'feed.open': '进入',
    'feed.os': '最低系统',
    'feed.pipelines': '实时生成管线',
    'feed.ready': '就绪',
    'feed.render.subtitle': '使用自定义 Renderer 绘制交互轨迹。',
    'feed.render.title': '自定义轨迹渲染',
    'feed.run': '运行',
    'feed.runtime': '运行平台',
    'feed.selected': '已选择',
    'feed.storage.subtitle': '上传图片或视频，获取可复用的远程地址',
    'feed.storage.title': '存储服务',
    'realtime.flip': '翻转',
    'realtime.flipCamera': '翻转摄像头',
    'realtime.generation.drag': '在画面上拖拽，用轨迹控制角色',
    'realtime.generation.start': '点击开始生成',
    'realtime.generation.stop': '停止生成',
    'realtime.prompt.placeholder': '输入你想要的效果',
    'realtime.prompt.submit': '提交自定义模式描述',
    'realtime.reference.label': '参考图',
    'realtime.reference.prompt.add': '添加自定义模式参考图',
    'realtime.reference.prompt.delete': '删除自定义模式参考图',
    'realtime.reference.prompt.uploading': '正在上传自定义模式参考图',
    'realtime.reference.prompt.retry': '重试上传自定义模式参考图',
    'realtime.performance.limited': '网络或设备性能受限，实时画质可能下降',
    'realtime.loading': '正在加载实时画面',
    'storage.select': '选择图片或视频',
    'storage.reselect': '重新上传',
    'storage.safety.unsupported': '视频生成暂不支持安全检测',
    'storage.upload.safe': '安全检测上传',
    'storage.upload.normal': '普通上传',
    'storage.upload.getURL': '上传并获取地址',
    'storage.copy': '复制地址',
    'storage.hero.title': '把本地媒体交给 XmaxSDK',
    'storage.hero.subtitle': '选择图片或视频，上传后获取可直接使用的远程地址。',
    'storage.preview': '文件预览',
    'storage.select.hint': '点击选择图片或视频',
    'storage.result': '上传结果',
    'storage.elapsed': '上传耗时',
    'storage.file.error': '读取文件失败，请重试',
    'storage.video.error': '读取视频失败，请重试',
    'storage.upload.progress': '上传中 %d%%',
    'storage.upload.video': '正在上传视频',
    'storage.upload.safety': '包含内容安全检查',
    'storage.upload.image': '正在上传图片',
    'storage.upload.error': '上传失败，请检查 API Key 和网络后重试',
    'storage.copied': '地址已复制',
    'storage.pipeline': '存储管线',
    'storage.localFile': '本地文件',
    'storage.remoteURL': '远程地址',
    'storage.type': '类型',
    'storage.resolution': '分辨率',
    'storage.size': '文件大小',
    'storage.mediaTypes': '图片 / 视频',
    'storage.success': '成功',
  };

  static const _english = <String, String>{
    'statistics.title': 'Stats',
    'statistics.level.hint':
        'L1 highest · L5 lowest. Automatic adaptation remains active.',
    'statistics.uplink': 'Uplink video',
    'statistics.downlink': 'Downlink video',
    'statistics.resolution': 'Resolution',
    'statistics.captureFPS': 'Capture FPS',
    'statistics.encodeFPS': 'Encode FPS',
    'statistics.sendFPS': 'Send FPS',
    'statistics.decodeFPS': 'Decode FPS',
    'statistics.renderFPS': 'Render FPS',
    'statistics.bitrate': 'Bitrate',
    'statistics.loss': 'Packet loss',
    'statistics.quality': 'Network',
    'statistics.delay': 'E2E (RTC)',
    'statistics.quality.excellent': 'Excellent',
    'statistics.quality.good': 'Good',
    'statistics.quality.poor': 'Poor',
    'statistics.quality.bad': 'Bad',
    'statistics.quality.veryBad': 'Very Bad',
    'statistics.quality.down': 'Disconnected',
    'language.system': 'Follow System',
    'common.home': 'Back to Home',
    'category.charx': 'Character',
    'category.clothx': 'Outfit',
    'category.vibex': 'Style',
    'category.dimx': 'Companion',
    'category.mox': 'Animate',
    'category.free': 'Free',
    'media.image': 'Image',
    'media.video': 'Video',
    'feed.api.hide': 'Hide API Key',
    'feed.api.link': 'Get One At Xmax Open Platform',
    'feed.api.placeholder': 'Enter your Xmax API Key',
    'feed.api.prompt': 'Need an API Key?',
    'feed.api.required': 'Please enter your API Key first',
    'feed.api.show': 'Show API Key',
    'feed.api.openError': 'Could not open the Xmax Open Platform',
    'feed.available': 'AVAILABLE',
    'feed.camera.subtitle': 'Generate video in real time from your camera.',
    'feed.camera.title': 'Live Camera',
    'feed.examples': 'More features and integration examples',
    'feed.features': 'SDK FEATURES',
    'feed.hero.subtitle': 'Experience streaming generation with XmaxSDK.',
    'feed.hero.title': 'Realtime Interactive Video',
    'feed.image.error': "Couldn't read the image. Please try again.",
    'feed.image.subtitle':
        'Bring a local image to life with continuous motion.',
    'feed.image.title': 'Image Pipeline',
    'feed.input': 'Choose an input source',
    'feed.latestModel': 'LATEST MODEL',
    'feed.model.count': 'MODELS: %d',
    'feed.model.title': 'Choose your model',
    'feed.open': 'Open',
    'feed.os': 'MIN OS',
    'feed.pipelines': 'REALTIME GENERATION PIPELINES',
    'feed.ready': 'READY',
    'feed.render.subtitle': 'Draw touch trails with a custom renderer.',
    'feed.render.title': 'Custom Rendering',
    'feed.run': 'Run',
    'feed.runtime': 'RUNTIME',
    'feed.selected': 'SELECTED',
    'feed.storage.subtitle': 'Upload images or videos and get reusable URLs.',
    'feed.storage.title': 'Storage Service',
    'realtime.flip': 'Flip',
    'realtime.flipCamera': 'Switch camera',
    'realtime.generation.drag': 'Drag on the video to guide the character',
    'realtime.generation.start': 'Tap to generate',
    'realtime.generation.stop': 'Stop generation',
    'realtime.prompt.placeholder': 'Describe the effect you want',
    'realtime.prompt.submit': 'Submit custom prompt',
    'realtime.reference.label': 'Reference',
    'realtime.reference.prompt.add': 'Add a custom-mode reference image',
    'realtime.reference.prompt.delete': 'Remove custom-mode reference image',
    'realtime.reference.prompt.uploading':
        'Uploading custom-mode reference image',
    'realtime.reference.prompt.retry': 'Retry custom-mode reference upload',
    'realtime.performance.limited':
        'Network or device performance is limited. Realtime quality may decrease.',
    'realtime.loading': 'Loading realtime video',
    'storage.select': 'Select an image or video',
    'storage.reselect': 'Reselect',
    'storage.safety.unsupported': "Safety checks aren't available for videos.",
    'storage.upload.safe': 'Upload & check',
    'storage.upload.normal': 'Upload',
    'storage.upload.getURL': 'Upload and get URL',
    'storage.copy': 'Copy URL',
    'storage.hero.title': 'Upload media with XmaxSDK',
    'storage.hero.subtitle':
        'Choose an image or video and upload it to get a ready-to-use URL.',
    'storage.preview': 'File Preview',
    'storage.select.hint': 'Tap to select an image or video',
    'storage.result': 'Upload Result',
    'storage.elapsed': 'Upload time',
    'storage.file.error': "Couldn't read the file. Please try again.",
    'storage.video.error': "Couldn't read the video. Please try again.",
    'storage.upload.progress': 'Uploading %d%%',
    'storage.upload.video': 'Uploading video',
    'storage.upload.safety': 'Includes a safety check',
    'storage.upload.image': 'Uploading image',
    'storage.upload.error':
        'Upload failed. Check your API Key and network, then try again.',
    'storage.copied': 'URL copied',
    'storage.pipeline': 'STORAGE PIPELINE',
    'storage.localFile': 'LOCAL FILE',
    'storage.remoteURL': 'REMOTE URL',
    'storage.type': 'type',
    'storage.resolution': 'resolution',
    'storage.size': 'size',
    'storage.mediaTypes': 'IMAGE / VIDEO',
    'storage.success': 'SUCCESS',
  };
}
