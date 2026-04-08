import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';

class StreamingModePage extends ConsumerWidget {
  const StreamingModePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('App Mode'), centerTitle: true),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Choose how you want to use SpotiFLAC',
              style: theme.textTheme.bodyLarge,
            ),
          ),
          // Download Mode Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              elevation: settings.appmode == 'download' ? 4 : 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: settings.appmode == 'download'
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                  width: settings.appmode == 'download' ? 2 : 1,
                ),
              ),
              child: InkWell(
                onTap: () => _setMode(context, ref, 'download'),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.download_done,
                            size: 32,
                            color: settings.appmode == 'download'
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Download Mode',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: settings.appmode == 'download'
                                        ? colorScheme.primary
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Default behavior - Download songs to your device',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Radio<String>(
                            value: 'download',
                            groupValue: settings.appmode,
                            onChanged: (value) =>
                                _setMode(context, ref, value ?? 'download'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _BulletPoint(
                              text:
                                  'Download full quality audio in FLAC format',
                              theme: theme,
                            ),
                            _BulletPoint(
                              text: 'Access downloaded tracks offline',
                              theme: theme,
                            ),
                            _BulletPoint(
                              text:
                                  'Customize download location and organization',
                              theme: theme,
                            ),
                            _BulletPoint(
                              text: 'Embed metadata and lyrics in files',
                              theme: theme,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Streaming Mode Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              elevation: settings.appmode == 'stream' ? 4 : 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: settings.appmode == 'streaming'
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                  width: settings.appmode == 'stream' ? 2 : 1,
                ),
              ),
              child: InkWell(
                onTap: () => _setMode(context, ref, 'stream'),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.stream,
                            size: 32,
                            color: settings.appmode == 'streaming'
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Streaming Mode',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: settings.appmode == 'stream'
                                        ? colorScheme.primary
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Stream music in-app without downloading',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Radio<String>(
                            value: 'stream',
                            groupValue: settings.appmode,
                            onChanged: (value) =>
                                _setMode(context, ref, value ?? 'stream'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _BulletPoint(
                              text: 'Stream music directly in the app',
                              theme: theme,
                            ),
                            _BulletPoint(
                              text: 'Save storage space on your device',
                              theme: theme,
                            ),
                            _BulletPoint(
                              text:
                                  'Access music instantly with basic playback controls',
                              theme: theme,
                            ),
                            _BulletPoint(
                              text: 'Requires active internet connection',
                              theme: theme,
                              isWarning: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              elevation: 0,
              color: colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Mode',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      settings.appmode == 'stream'
                          ? 'Streaming - Music plays !in-app without downloading'
                          : 'Download - Music is downloaded to your device',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _setMode(BuildContext context, WidgetRef ref, String mode) {
    // Normalize mode value: 'streaming' -> 'stream'
    final normalizedMode = mode == 'streaming' ? 'stream' : mode;
    ref.read(settingsProvider.notifier).setAppMode(normalizedMode);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          normalizedMode == 'stream'
              ? 'Switched to Streaming Mode'
              : 'Switched to Download Mode',
        ),
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;
  final ThemeData theme;
  final bool isWarning;

  const _BulletPoint({
    required this.text,
    required this.theme,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isWarning ? Icons.info : Icons.check_circle,
            size: 16,
            color: isWarning
                ? theme.colorScheme.tertiary
                : theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isWarning
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
