import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  test('reports the package version', () {
    expect(XmaxSDKInfo.version, '1.0.4');
  });
}
