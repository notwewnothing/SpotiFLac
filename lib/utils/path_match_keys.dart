import 'dart:io';

const _androidStoragePathAliases = <String>[
  '/storage/emulated/0',
  '/storage/emulated/legacy',
  '/storage/self/primary',
  '/sdcard',
  '/mnt/sdcard',
];

/// Audio file extensions that the app commonly produces or converts between.
/// Used to generate extension-stripped match keys so that a file converted from
/// one format to another (e.g. .flac → .opus) is still recognised as the same
/// track.
const _audioExtensions = <String>[
  '.flac',
  '.m4a',
  '.mp3',
  '.opus',
  '.ogg',
  '.wav',
  '.aac',
];

/// Strips a trailing audio extension from [path] if present.
/// Returns the path without extension, or `null` if no known audio extension
/// was found.
String? _stripAudioExtension(String path) {
  final lower = path.toLowerCase();
  for (final ext in _audioExtensions) {
    if (lower.endsWith(ext)) {
      return path.substring(0, path.length - ext.length);
    }
  }
  return null;
}

Set<String> buildPathMatchKeys(String? filePath) {
  final raw = filePath?.trim() ?? '';
  if (raw.isEmpty) return const {};

  final cleaned = raw.startsWith('EXISTS:') ? raw.substring(7).trim() : raw;
  if (cleaned.isEmpty) return const {};

  final keys = <String>{};
  final visited = <String>{};

  void addNormalized(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    if (!visited.add(trimmed)) return;

    keys.add(trimmed);
    keys.add(trimmed.toLowerCase());

    if (trimmed.contains('\\')) {
      final slash = trimmed.replaceAll('\\', '/');
      if (slash != trimmed) {
        addNormalized(slash);
      }
    }

    if (trimmed.contains('%')) {
      try {
        final decoded = Uri.decodeFull(trimmed);
        if (decoded != trimmed) {
          addNormalized(decoded);
        }
      } catch (_) {}
    }

    Uri? parsed;
    try {
      parsed = Uri.parse(trimmed);
    } catch (_) {}

    if (parsed != null && parsed.hasScheme) {
      final withoutQueryOrFragment = parsed.replace(
        query: null,
        fragment: null,
      );
      final uriString = withoutQueryOrFragment.toString();
      keys.add(uriString);
      keys.add(uriString.toLowerCase());

      if (parsed.scheme == 'file') {
        try {
          addNormalized(parsed.toFilePath());
        } catch (_) {}
      }
    } else if (trimmed.startsWith('/')) {
      try {
        final asFileUri = Uri.file(trimmed).toString();
        keys.add(asFileUri);
        keys.add(asFileUri.toLowerCase());
      } catch (_) {}
    }

    if (Platform.isAndroid) {
      for (final alias in _androidEquivalentPaths(trimmed)) {
        if (alias != trimmed) {
          addNormalized(alias);
        }
      }
    }
  }

  addNormalized(cleaned);

  // Add extension-stripped variants so that a file converted from one audio
  // format to another (e.g. Song.flac → Song.opus) still matches.
  final extensionStrippedKeys = <String>{};
  for (final key in keys) {
    final stripped = _stripAudioExtension(key);
    if (stripped != null && stripped.isNotEmpty) {
      extensionStrippedKeys.add(stripped);
    }
  }
  keys.addAll(extensionStrippedKeys);

  return keys;
}

Iterable<String> _androidEquivalentPaths(String path) {
  final normalized = path.replaceAll('\\', '/');
  final lower = normalized.toLowerCase();
  String? suffix;

  for (final prefix in _androidStoragePathAliases) {
    if (lower == prefix) {
      suffix = '';
      break;
    }
    final withSlash = '$prefix/';
    if (lower.startsWith(withSlash)) {
      suffix = normalized.substring(prefix.length);
      break;
    }
  }

  if (suffix == null) return const [];
  return _androidStoragePathAliases.map((prefix) => '$prefix$suffix');
}
