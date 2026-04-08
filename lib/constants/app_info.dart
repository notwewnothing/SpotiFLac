import 'package:flutter/foundation.dart';

/// App version and info constants
/// Update version here only - all other files will reference this
class AppInfo {
  static const String version = '3.8.6';
  static const String buildNumber = '112';
  static const String fullVersion = '$version+$buildNumber';

  /// Shows "Internal" in debug builds, actual version in release.
  static String get displayVersion => kDebugMode ? 'Internal' : version;

  static const String appName = 'AudioPhile';
  static const String copyright = '© 2026 AudioPhile. All rights reserved.';

  static const String mobileAuthor = 'Poldak._';
  static const String originalAuthor = 'Poldak._';

  static const String githubRepo = 'zarzet/SpotiFLAC-Mobile';
  static const String githubUrl = 'https://github.com/$githubRepo';
  static const String originalGithubUrl =
      'https://github.com/afkarxyz/SpotiFLAC';

  static const String kofiUrl = 'https://ko-fi.com/zarzet';
  static const String githubSponsorsUrl = 'https://github.com/sponsors/zarzet/';
}
