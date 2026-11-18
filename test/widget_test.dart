// Kept as widget_test.dart so `flutter create .` doesn't add its default
// counter-app test, which would not compile against this app.
import 'package:duespay/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('naira formats with thousands separators', () {
    expect(naira(100), '₦100');
    expect(naira(2500), '₦2,500');
    expect(naira(1234567), '₦1,234,567');
  });

  test('no web launch code off the web', () {
    expect(codeFromLaunchUrl(), isNull);
  });
}
