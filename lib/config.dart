import 'package:flutter/foundation.dart' show kIsWeb;

/// Your deployed backend. Override at build time with:
///   flutter run --dart-define=BACKEND_URL=https://your-project.vercel.app
const String backendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'https://YOUR-PROJECT.vercel.app',
);

/// Where the web version of the app is hosted, e.g. https://duespay.web.app.
/// Used to build pay links that phone apps can share too:
///   --dart-define=WEB_APP_URL=https://your-project.web.app
const String webAppUrl = String.fromEnvironment('WEB_APP_URL');

/// A link that opens the web app straight on a due, e.g.
/// https://duespay.web.app/?code=K7M2QX. Null when no web address is known.
String? payLink(String code) {
  var base = webAppUrl;
  if (base.isEmpty && kIsWeb) base = Uri.base.origin;
  if (base.isEmpty) return null;
  return '${base.replaceAll(RegExp(r'/+$'), '')}/?code=$code';
}

/// Reads ?code=... when the web app was opened from a pay link.
String? codeFromLaunchUrl() {
  if (!kIsWeb) return null;
  final raw = Uri.base.queryParameters['code'] ?? '';
  final code = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (code.isEmpty || code.length > 12) return null;
  return code;
}

/// Formats whole naira amounts, e.g. 2500 -> ₦2,500.
String naira(num value) {
  final digits = value.round().toString();
  final withCommas = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );
  return '₦$withCommas';
}
