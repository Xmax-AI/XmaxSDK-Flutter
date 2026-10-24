//
//  RealtimeContext.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The prompt and optional reference image path for realtime generation.
final class RealtimeContext {

  /// Creates generation conditions.
  ///
  /// Parameters:
  /// - [prompt]: The prompt describing the requested generation effect.
  /// - [referencePath]: The uploaded reference image URL or path; null or whitespace clears the
  ///   reference.
  RealtimeContext({
    required String prompt,
    String? referencePath,
  }) : prompt = prompt.trim(),
       referencePath = _normalizedReferencePath(referencePath);

  /// The prompt describing the requested generation effect.
  final String prompt;

  /// The reference image URL or path, or null to omit a reference image.
  final String? referencePath;

  /// Trims a reference path and converts whitespace-only input to null.
  ///
  /// Parameters:
  /// - [value]: The reference image path to normalize.
  ///
  /// Returns the trimmed reference path, or null for empty content.
  static String? _normalizedReferencePath(
    String? value,
  ) {
    final normalized = value?.trim();

    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  /// Whether [other] has the same value.
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(
        this,
        other,
      ) ||
      other is RealtimeContext &&
          prompt == other.prompt &&
          referencePath == other.referencePath;

  /// The hash code consistent with value equality.
  @override
  int get hashCode => Object.hash(
    prompt,
    referencePath,
  );
}
