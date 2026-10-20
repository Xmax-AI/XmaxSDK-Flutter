//
//  RealtimeContext.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 一次实时生成使用的提示词和可选参考图路径。
final class RealtimeContext {

  /// 创建生成条件，并去除提示词及参考图路径的首尾空白。
  ///
  /// - [prompt]：描述目标生成效果的提示词。
  /// - [referencePath]：已上传参考图地址或路径；null 或空白统一保存为 null。
  RealtimeContext({
    required String prompt,
    String? referencePath,
  }) : prompt = prompt.trim(),
       referencePath = _normalizedReferencePath(referencePath);

  /// 描述目标生成效果的提示词。
  final String prompt;

  /// 参考图地址或路径；为空时不使用参考图。
  final String? referencePath;

  /// 清理参考图路径两端空白；空白路径转为 null。
  ///
  /// - [value]：待清理首尾空白的参考图路径。
  ///
  /// 返回去除两端空白的参考图路径；空内容为 null。
  static String? _normalizedReferencePath(
    String? value,
  ) {
    final normalized = value?.trim();

    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  /// 与 [other] 比较类型及 [prompt]、[referencePath] 的值。
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(this, other) ||
      other is RealtimeContext &&
          prompt == other.prompt &&
          referencePath == other.referencePath;

  /// 与相等判断一致的哈希值。
  @override
  int get hashCode => Object.hash(prompt, referencePath);
}
