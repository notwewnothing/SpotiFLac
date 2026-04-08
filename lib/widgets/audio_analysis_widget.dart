import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/level.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';

class AudioAnalysisData {
  final String filePath;
  final int fileSize;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final double duration;
  final int bitrate;
  final String bitDepth;
  final double dynamicRange;
  final double peakAmplitude;
  final double rmsLevel;
  final int totalSamples;
  final SpectrogramData? spectrum;

  const AudioAnalysisData({
    required this.filePath,
    required this.fileSize,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.duration,
    required this.bitrate,
    required this.bitDepth,
    required this.dynamicRange,
    required this.peakAmplitude,
    required this.rmsLevel,
    required this.totalSamples,
    this.spectrum,
  });

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'fileSize': fileSize,
    'sampleRate': sampleRate,
    'channels': channels,
    'bitsPerSample': bitsPerSample,
    'duration': duration,
    'bitrate': bitrate,
    'bitDepth': bitDepth,
    'dynamicRange': dynamicRange,
    'peakAmplitude': peakAmplitude,
    'rmsLevel': rmsLevel,
    'totalSamples': totalSamples,
  };

  factory AudioAnalysisData.fromJson(Map<String, dynamic> json) {
    return AudioAnalysisData(
      filePath: json['filePath'] as String,
      fileSize: json['fileSize'] as int,
      sampleRate: json['sampleRate'] as int,
      channels: json['channels'] as int,
      bitsPerSample: json['bitsPerSample'] as int,
      duration: (json['duration'] as num).toDouble(),
      bitrate: json['bitrate'] as int,
      bitDepth: json['bitDepth'] as String,
      dynamicRange: (json['dynamicRange'] as num).toDouble(),
      peakAmplitude: (json['peakAmplitude'] as num).toDouble(),
      rmsLevel: (json['rmsLevel'] as num).toDouble(),
      totalSamples: json['totalSamples'] as int,
    );
  }
}

class SpectrogramData {
  final List<Float64List> magnitudes;
  final int sampleRate;
  final int freqBins;
  final double duration;
  final double maxFreq;
  final int sliceCount;

  const SpectrogramData({
    required this.magnitudes,
    required this.sampleRate,
    required this.freqBins,
    required this.duration,
    required this.maxFreq,
    required this.sliceCount,
  });
}

class AudioAnalysisCard extends StatefulWidget {
  final String filePath;

  const AudioAnalysisCard({super.key, required this.filePath});

  @override
  State<AudioAnalysisCard> createState() => _AudioAnalysisCardState();
}

class _AudioAnalysisCardState extends State<AudioAnalysisCard> {
  AudioAnalysisData? _data;
  bool _analyzing = false;
  bool _checkingCache = true;
  String? _error;
  ui.Image? _spectrogramImage;

  static const _supportedExtensions = {
    '.flac',
    '.mp3',
    '.m4a',
    '.aac',
    '.opus',
    '.ogg',
    '.wav',
    '.wma',
  };

  bool get _isSupported {
    final lower = widget.filePath.toLowerCase();
    return _supportedExtensions.any((ext) => lower.endsWith(ext));
  }

  @override
  void initState() {
    super.initState();
    if (_isSupported) {
      _tryLoadFromCache();
    }
  }

  @override
  void dispose() {
    _spectrogramImage?.dispose();
    super.dispose();
  }

  Future<void> _tryLoadFromCache() async {
    try {
      final cached = await _loadFromCache(widget.filePath);
      if (cached != null && mounted) {
        setState(() {
          _data = cached;
          _checkingCache = false;
        });
        final image = await _loadSpectrogramFromCache(widget.filePath);
        if (image != null && mounted) {
          setState(() {
            _spectrogramImage?.dispose();
            _spectrogramImage = image;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _checkingCache = false);
    }
  }

  Future<void> _analyze() async {
    if (_analyzing) return;
    setState(() {
      _analyzing = true;
      _error = null;
    });

    try {
      final cached = await _loadFromCache(widget.filePath);
      AudioAnalysisData data;
      bool fromCache = false;

      if (cached != null) {
        data = cached;
        fromCache = true;
      } else {
        data = await _runAnalysis(widget.filePath);
        _saveToCache(widget.filePath, data);
      }

      ui.Image? image;
      if (fromCache) {
        image = await _loadSpectrogramFromCache(widget.filePath);
      }
      if (image == null &&
          data.spectrum != null &&
          data.spectrum!.sliceCount > 0) {
        image = await _renderSpectrogramToImage(data.spectrum!);
        _saveSpectrogramToCache(widget.filePath, image);
      }

      if (mounted) {
        setState(() {
          _data = data;
          _spectrogramImage?.dispose();
          _spectrogramImage = image;
          _analyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _analyzing = false;
        });
      }
    }
  }

  static String _cacheKey(String filePath) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(filePath)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  static Future<Directory> _cacheDir() async {
    final appSupport = await getApplicationSupportDirectory();
    final dir = Directory('${appSupport.path}/audio_analysis_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<AudioAnalysisData?> _loadFromCache(String filePath) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final file = File('${dir.path}/$key.json');
      if (!await file.exists()) return null;

      final json = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
      final cachedSize = json['fileSize'] as int;

      if (!filePath.startsWith('content://')) {
        final currentSize = await File(filePath).length();
        if (currentSize != cachedSize) return null;
      }

      return AudioAnalysisData.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveToCache(
    String filePath,
    AudioAnalysisData data,
  ) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final file = File('${dir.path}/$key.json');
      await file.writeAsString(jsonEncode(data.toJson()));
    } catch (_) {}
  }

  static Future<void> _saveSpectrogramToCache(
    String filePath,
    ui.Image image,
  ) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final file = File('${dir.path}/$key.png');
        await file.writeAsBytes(byteData.buffer.asUint8List());
      }
    } catch (_) {}
  }

  static Future<ui.Image?> _loadSpectrogramFromCache(String filePath) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final file = File('${dir.path}/$key.png');
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, completer.complete);
      return completer.future;
    } catch (_) {
      return null;
    }
  }

  Future<AudioAnalysisData> _runAnalysis(String filePath) async {
    await FFmpegKitConfig.setLogLevel(Level.avLogError);

    String workingPath = filePath;
    String? tempCopy;
    if (filePath.startsWith('content://')) {
      tempCopy = await PlatformBridge.copyContentUriToTemp(filePath);
      if (tempCopy == null) {
        throw Exception('Failed to copy SAF file for analysis');
      }
      workingPath = tempCopy;
    }

    try {
      final info = await _getMediaInfo(workingPath);

      final tempDir = await getTemporaryDirectory();
      final pcmPath =
          '${tempDir.path}/analysis_pcm_${DateTime.now().millisecondsSinceEpoch}.raw';

      try {
        await _decodeToPCM(workingPath, pcmPath, info.sampleRate);

        final pcmBytes = await File(pcmPath).readAsBytes();
        final result = await compute(
          _analyzeInIsolate,
          _AnalysisParams(
            pcmBytes: pcmBytes,
            sampleRate: info.sampleRate,
            bitsPerSample: info.bitsPerSample,
          ),
        );

        final trueTotalSamples =
            (info.duration * info.sampleRate * info.channels).round();

        return AudioAnalysisData(
          filePath: filePath,
          fileSize: info.fileSize,
          sampleRate: info.sampleRate,
          channels: info.channels,
          bitsPerSample: info.bitsPerSample,
          duration: info.duration,
          bitrate: info.bitrate,
          bitDepth: info.bitsPerSample > 0
              ? '${info.bitsPerSample}-bit'
              : 'N/A',
          dynamicRange: result.dynamicRange,
          peakAmplitude: result.peakAmplitude,
          rmsLevel: result.rmsLevel,
          totalSamples: trueTotalSamples,
          spectrum: result.spectrum,
        );
      } finally {
        try {
          await File(pcmPath).delete();
        } catch (_) {}
      }
    } finally {
      if (tempCopy != null) {
        try {
          await File(tempCopy).delete();
        } catch (_) {}
      }
      await FFmpegKitConfig.setLogLevel(Level.avLogInfo);
    }
  }

  Future<_MediaInfo> _getMediaInfo(String filePath) async {
    final session = await FFprobeKit.getMediaInformation(filePath);
    final info = session.getMediaInformation();

    if (info == null) {
      throw Exception('Failed to get media information');
    }

    int fileSize = 0;
    try {
      fileSize = await File(filePath).length();
    } catch (_) {}

    final streams = info.getStreams();
    final audioStream = streams.firstWhere(
      (s) => s.getAllProperties()?['codec_type'] == 'audio',
      orElse: () => throw Exception('No audio stream found'),
    );

    final props = audioStream.getAllProperties() ?? {};
    final sampleRate =
        int.tryParse(props['sample_rate']?.toString() ?? '') ?? 0;
    final channels = int.tryParse(props['channels']?.toString() ?? '') ?? 0;
    final duration =
        double.tryParse(
          info.getDuration() ?? props['duration']?.toString() ?? '',
        ) ??
        0;
    final bitrate =
        int.tryParse(
          info.getBitrate() ?? props['bit_rate']?.toString() ?? '',
        ) ??
        0;

    int bitsPerSample =
        int.tryParse(props['bits_per_raw_sample']?.toString() ?? '') ?? 0;
    if (bitsPerSample == 0) {
      bitsPerSample =
          int.tryParse(props['bits_per_sample']?.toString() ?? '') ?? 0;
    }

    if (bitsPerSample == 0) {
      final sampleFmt = props['sample_fmt']?.toString() ?? '';
      if (sampleFmt.contains('16') ||
          sampleFmt == 's16' ||
          sampleFmt == 's16p') {
        bitsPerSample = 16;
      } else if (sampleFmt.contains('32') ||
          sampleFmt == 'flt' ||
          sampleFmt == 'fltp') {
        bitsPerSample = 32;
      } else if (sampleFmt.contains('24') || sampleFmt == 's24') {
        bitsPerSample = 24;
      }
    }

    return _MediaInfo(
      fileSize: fileSize,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
      duration: duration,
      bitrate: bitrate,
    );
  }

  Future<void> _decodeToPCM(
    String inputPath,
    String outputPath,
    int sampleRate,
  ) async {
    final maxDuration = sampleRate > 0 ? (10000000 / sampleRate) : 300;

    final session = await FFmpegKit.executeWithArguments([
      '-loglevel',
      'error',
      '-i',
      inputPath,
      '-t',
      maxDuration.toStringAsFixed(1),
      '-ac',
      '1',
      '-ar',
      sampleRate.toString(),
      '-f',
      's16le',
      '-acodec',
      'pcm_s16le',
      '-y',
      outputPath,
    ]);

    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getLogsAsString();
      throw Exception('FFmpeg decode failed: $logs');
    }
  }

  Future<ui.Image> _renderSpectrogramToImage(SpectrogramData spectrum) async {
    const imgWidth = 800;
    const imgHeight = 400;

    final pixels = await compute(
      _renderSpectrogramPixels,
      _SpectrogramRenderParams(
        spectrum: spectrum,
        width: imgWidth,
        height: imgHeight,
      ),
    );

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      imgWidth,
      imgHeight,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupported) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    if (_checkingCache) return const SizedBox.shrink();

    if (_analyzing) {
      return Card(
        color: cs.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.audioAnalysisAnalyzing,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Card(
        color: cs.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: cs.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_data == null) {
      return Card(
        color: cs.surfaceContainerLow,
        child: InkWell(
          onTap: _analyze,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.analytics_outlined, color: cs.primary, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.audioAnalysisTitle,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.audioAnalysisDescription,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      );
    }

    final data = _data!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AudioInfoCard(data: data),
        if (_spectrogramImage != null) ...[
          const SizedBox(height: 12),
          _SpectrogramView(
            image: _spectrogramImage!,
            sampleRate: data.sampleRate,
            maxFreq: data.spectrum?.maxFreq ?? data.sampleRate / 2,
          ),
        ],
      ],
    );
  }
}

class _MediaInfo {
  final int fileSize;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final double duration;
  final int bitrate;

  const _MediaInfo({
    required this.fileSize,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.duration,
    required this.bitrate,
  });
}

class _AnalysisParams {
  final Uint8List pcmBytes;
  final int sampleRate;
  final int bitsPerSample;

  const _AnalysisParams({
    required this.pcmBytes,
    required this.sampleRate,
    required this.bitsPerSample,
  });
}

class _AnalysisResult {
  final double dynamicRange;
  final double peakAmplitude;
  final double rmsLevel;
  final int totalSamples;
  final SpectrogramData? spectrum;

  const _AnalysisResult({
    required this.dynamicRange,
    required this.peakAmplitude,
    required this.rmsLevel,
    required this.totalSamples,
    this.spectrum,
  });
}

_AnalysisResult _analyzeInIsolate(_AnalysisParams params) {
  final byteData = ByteData.sublistView(params.pcmBytes);
  final sampleCount = params.pcmBytes.length ~/ 2;
  final samples = Float64List(sampleCount);

  for (int i = 0; i < sampleCount; i++) {
    final raw = byteData.getInt16(i * 2, Endian.little);
    samples[i] = raw / 32768.0;
  }

  double peak = 0;
  double sumSquares = 0;
  for (int i = 0; i < samples.length; i++) {
    final abs = samples[i].abs();
    if (abs > peak) peak = abs;
    sumSquares += samples[i] * samples[i];
  }

  final peakDB = peak > 0 ? 20.0 * math.log(peak) / math.ln10 : -100.0;
  final rms = math.sqrt(sumSquares / samples.length);
  final rmsDB = rms > 0 ? 20.0 * math.log(rms) / math.ln10 : -100.0;

  SpectrogramData? spectrum;
  if (samples.length >= 8192) {
    spectrum = _computeSpectrum(samples, params.sampleRate);
  }

  return _AnalysisResult(
    dynamicRange: peakDB - rmsDB,
    peakAmplitude: peakDB,
    rmsLevel: rmsDB,
    totalSamples: sampleCount,
    spectrum: spectrum,
  );
}

SpectrogramData _computeSpectrum(Float64List samples, int sampleRate) {
  const fftSize = 8192;
  const numSlices = 300;
  const freqBins = fftSize ~/ 2;

  final duration = samples.length / sampleRate;
  var samplesPerSlice = samples.length ~/ numSlices;
  var actualSlices = numSlices;
  if (samplesPerSlice < fftSize) {
    samplesPerSlice = fftSize;
    actualSlices = samples.length ~/ fftSize;
  }

  final magnitudes = <Float64List>[];

  for (int i = 0; i < actualSlices; i++) {
    final start = i * samplesPerSlice;
    if (start + fftSize > samples.length) break;

    final windowed = Float64List(fftSize);
    for (int j = 0; j < fftSize; j++) {
      final w = 0.5 * (1.0 - math.cos(2.0 * math.pi * j / (fftSize - 1)));
      windowed[j] = samples[start + j] * w;
    }

    final spectrum = _fft(windowed);

    final mags = Float64List(freqBins);
    for (int j = 0; j < freqBins; j++) {
      final re = spectrum[j * 2];
      final im = spectrum[j * 2 + 1];
      var mag = math.sqrt(re * re + im * im);
      if (mag < 1e-10) mag = 1e-10;
      mags[j] = 20.0 * math.log(mag) / math.ln10;
    }
    magnitudes.add(mags);
  }

  return SpectrogramData(
    magnitudes: magnitudes,
    sampleRate: sampleRate,
    freqBins: freqBins,
    duration: duration,
    maxFreq: sampleRate / 2.0,
    sliceCount: magnitudes.length,
  );
}

/// Cooley-Tukey radix-2 FFT. Returns interleaved [re, im, re, im, ...].
Float64List _fft(Float64List realInput) {
  final n = realInput.length;
  final data = Float64List(n * 2);
  for (int i = 0; i < n; i++) {
    data[i * 2] = realInput[i];
  }

  int j = 0;
  for (int i = 0; i < n; i++) {
    if (i < j) {
      final tr = data[i * 2];
      final ti = data[i * 2 + 1];
      data[i * 2] = data[j * 2];
      data[i * 2 + 1] = data[j * 2 + 1];
      data[j * 2] = tr;
      data[j * 2 + 1] = ti;
    }
    int m = n >> 1;
    while (m >= 1 && j >= m) {
      j -= m;
      m >>= 1;
    }
    j += m;
  }

  for (int size = 2; size <= n; size <<= 1) {
    final halfSize = size >> 1;
    final angle = -2.0 * math.pi / size;
    final wRe = math.cos(angle);
    final wIm = math.sin(angle);

    for (int i = 0; i < n; i += size) {
      double curRe = 1.0;
      double curIm = 0.0;

      for (int k = 0; k < halfSize; k++) {
        final evenIdx = (i + k) * 2;
        final oddIdx = (i + k + halfSize) * 2;

        final tRe = curRe * data[oddIdx] - curIm * data[oddIdx + 1];
        final tIm = curRe * data[oddIdx + 1] + curIm * data[oddIdx];

        data[oddIdx] = data[evenIdx] - tRe;
        data[oddIdx + 1] = data[evenIdx + 1] - tIm;
        data[evenIdx] += tRe;
        data[evenIdx + 1] += tIm;

        final newRe = curRe * wRe - curIm * wIm;
        curIm = curRe * wIm + curIm * wRe;
        curRe = newRe;
      }
    }
  }

  return data;
}

class _AudioInfoCard extends StatelessWidget {
  final AudioAnalysisData data;

  const _AudioInfoCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nyquist = data.sampleRate / 2;

    return Card(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics_outlined, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  context.l10n.audioAnalysisTitle,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _MetricChip(
                  icon: Icons.graphic_eq,
                  label: context.l10n.audioAnalysisSampleRate,
                  value: '${(data.sampleRate / 1000).toStringAsFixed(1)} kHz',
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.audio_file,
                  label: context.l10n.audioAnalysisBitDepth,
                  value: data.bitDepth,
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.surround_sound,
                  label: context.l10n.audioAnalysisChannels,
                  value: data.channels == 2
                      ? 'Stereo'
                      : data.channels == 1
                      ? 'Mono'
                      : '${data.channels}',
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.timer_outlined,
                  label: context.l10n.audioAnalysisDuration,
                  value: _formatDuration(data.duration),
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.speed,
                  label: context.l10n.audioAnalysisNyquist,
                  value: '${(nyquist / 1000).toStringAsFixed(1)} kHz',
                  cs: cs,
                ),
                if (data.fileSize > 0)
                  _MetricChip(
                    icon: Icons.storage,
                    label: context.l10n.audioAnalysisFileSize,
                    value: _formatFileSize(data.fileSize),
                    cs: cs,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _MetricChip(
                  icon: Icons.trending_up,
                  label: context.l10n.audioAnalysisDynamicRange,
                  value: '${data.dynamicRange.toStringAsFixed(2)} dB',
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.show_chart,
                  label: context.l10n.audioAnalysisPeak,
                  value: '${data.peakAmplitude.toStringAsFixed(2)} dB',
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.equalizer,
                  label: context.l10n.audioAnalysisRms,
                  value: '${data.rmsLevel.toStringAsFixed(2)} dB',
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.numbers,
                  label: context.l10n.audioAnalysisSamples,
                  value: _formatNumber(data.totalSamples),
                  cs: cs,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(double seconds) {
    final mins = seconds ~/ 60;
    final secs = (seconds % 60).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int bytes) {
    if (bytes == 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    final i = (math.log(bytes) / math.log(1024)).floor();
    final size = bytes / math.pow(1024, i);
    return '${size.toStringAsFixed(1)} ${units[i]}';
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme cs;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
        Text(
          value,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SpectrogramView extends StatelessWidget {
  final ui.Image image;
  final int sampleRate;
  final double maxFreq;

  const _SpectrogramView({
    required this.image,
    required this.sampleRate,
    required this.maxFreq,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      color: Colors.black,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2.0,
            child: CustomPaint(
              painter: _ImagePainter(image),
              size: Size.infinite,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${context.l10n.audioAnalysisSampleRate}: $sampleRate Hz',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                ),
                const Spacer(),
                Text(
                  '${context.l10n.audioAnalysisNyquist}: ${(maxFreq / 1000).toStringAsFixed(1)} kHz',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image image;
  _ImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: Offset.zero & size,
      image: image,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _ImagePainter old) => old.image != image;
}

class _SpectrogramRenderParams {
  final SpectrogramData spectrum;
  final int width;
  final int height;

  const _SpectrogramRenderParams({
    required this.spectrum,
    required this.width,
    required this.height,
  });
}

Uint8List _renderSpectrogramPixels(_SpectrogramRenderParams params) {
  final w = params.width;
  final h = params.height;
  final spectrum = params.spectrum;
  final pixels = Uint8List(w * h * 4);

  for (int i = 3; i < pixels.length; i += 4) {
    pixels[i] = 255;
  }

  final slices = spectrum.magnitudes;
  if (slices.isEmpty) return pixels;

  final freqBins = spectrum.freqBins;

  double minDB = 0;
  double maxDB = -200;
  for (final slice in slices) {
    for (int i = 0; i < slice.length; i++) {
      final db = slice[i];
      if (db > maxDB) maxDB = db;
      if (db < minDB && db > -200) minDB = db;
    }
  }
  minDB = math.max(minDB, maxDB - 90);
  final dbRange = maxDB - minDB;
  if (dbRange <= 0) return pixels;

  for (int px = 0; px < w; px++) {
    final t = (px / w * slices.length).floor().clamp(0, slices.length - 1);
    final slice = slices[t];

    for (int py = 0; py < h; py++) {
      final freqRatio = 1.0 - (py / h);
      final f = (freqRatio * freqBins).floor().clamp(0, freqBins - 1);
      if (f >= slice.length) continue;

      final db = slice[f];
      final intensity = ((db - minDB) / dbRange).clamp(0.0, 1.0);
      final color = _spekColorRGB(intensity);

      final offset = (py * w + px) * 4;
      pixels[offset] = color[0];
      pixels[offset + 1] = color[1];
      pixels[offset + 2] = color[2];
      pixels[offset + 3] = 255;
    }
  }

  return pixels;
}

List<int> _spekColorRGB(double intensity) {
  int r, g, b;
  if (intensity < 0.08) {
    final t = intensity / 0.08;
    r = 0;
    g = 0;
    b = (t * 80).floor();
  } else if (intensity < 0.18) {
    final t = (intensity - 0.08) / 0.10;
    r = (t * 50).floor();
    g = (t * 30).floor();
    b = (80 + t * 175).floor();
  } else if (intensity < 0.28) {
    final t = (intensity - 0.18) / 0.10;
    r = (50 + t * 150).floor();
    g = (30 - t * 30).floor();
    b = (255 - t * 55).floor();
  } else if (intensity < 0.40) {
    final t = (intensity - 0.28) / 0.12;
    r = (200 + t * 55).floor();
    g = 0;
    b = (200 - t * 200).floor();
  } else if (intensity < 0.52) {
    final t = (intensity - 0.40) / 0.12;
    r = 255;
    g = (t * 100).floor();
    b = 0;
  } else if (intensity < 0.65) {
    final t = (intensity - 0.52) / 0.13;
    r = 255;
    g = (100 + t * 80).floor();
    b = 0;
  } else if (intensity < 0.78) {
    final t = (intensity - 0.65) / 0.13;
    r = 255;
    g = (180 + t * 55).floor();
    b = (t * 30).floor();
  } else if (intensity < 0.90) {
    final t = (intensity - 0.78) / 0.12;
    r = 255;
    g = (235 + t * 20).floor();
    b = (30 + t * 100).floor();
  } else {
    final t = (intensity - 0.90) / 0.10;
    r = 255;
    g = 255;
    b = (130 + t * 125).floor();
  }
  return [r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255)];
}
