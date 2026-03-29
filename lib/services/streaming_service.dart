import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('StreamingService');

class StreamingUrlResponse {
  final String url;
  final String? decryptionKey;
  final int? bitDepth;
  final int? sampleRate;
  final String? format;
  final String? service;

  StreamingUrlResponse({
    required this.url,
    this.decryptionKey,
    this.bitDepth,
    this.sampleRate,
    this.format,
    this.service,
  });

  factory StreamingUrlResponse.fromJson(Map<String, dynamic> json) {
    return StreamingUrlResponse(
      url: json['url'] as String? ?? '',
      decryptionKey: json['decryption_key'] as String?,
      bitDepth: json['bit_depth'] as int?,
      sampleRate: json['sample_rate'] as int?,
      format: json['format'] as String?,
      service: json['service'] as String?,
    );
  }
}

class StreamingService {
  static const _channel = MethodChannel('com.zarz.spotiflac/backend');
  static const _perServiceTimeout = Duration(seconds: 15);

  /// Get a streaming URL for a track from a single service
  static Future<StreamingUrlResponse> getStreamingUrl({
    required Track track,
    required String service,
    required String quality,
  }) async {
    try {
      _log.d(
        'Requesting streaming URL for "${track.name}" by ${track.artistName} from $service',
      );

      final request = {
        'track_name': track.name,
        'artist_name': track.artistName,
        'album_name': track.albumName,
        'spotify_id': track.id,
        'isrc': track.isrc ?? '',
        'service': service,
        'quality': quality,
        'duration_ms': track.duration,
      };

      final result = await _channel.invokeMethod(
        'getStreamingUrl',
        jsonEncode(request),
      );

      if (result == null) {
        throw Exception('No streaming URL available');
      }

      final responseJson = jsonDecode(result as String) as Map<String, dynamic>;

      if (responseJson['success'] == false || responseJson.containsKey('error')) {
        throw Exception('Streaming error: ${responseJson['error']}');
      }

      if (!responseJson.containsKey('data')) {
        throw Exception('Invalid response format: missing data field');
      }

      final response = StreamingUrlResponse.fromJson(
        responseJson['data'] as Map<String, dynamic>,
      );

      if (response.url.isEmpty) {
        throw Exception('Empty streaming URL returned');
      }

      _log.i(
        'Got streaming URL for "${track.name}" from $service: ${response.url.substring(0, response.url.length.clamp(0, 50))}...',
      );

      return response;
    } on PlatformException catch (e) {
      _log.e('Platform exception: ${e.message}');
      throw Exception('Failed to get streaming URL: ${e.message}');
    } catch (e) {
      _log.e('Error getting streaming URL: $e');
      throw Exception('Failed to get streaming URL: $e');
    }
  }

  /// Try services sequentially (preferred service first) with per-service timeout.
  /// Returns the first successful response. This avoids dangling concurrent requests
  /// that overwhelm the backend and cause timeout cascades.
  static Future<StreamingUrlResponse> getStreamingUrlWithFallback({
    required Track track,
    required List<String> services,
    required String quality,
  }) async {
    if (services.isEmpty) {
      throw Exception('No services provided for streaming fallback');
    }

    final errors = <String>[];

    for (final service in services) {
      try {
        final response = await getStreamingUrl(
          track: track,
          service: service,
          quality: quality,
        ).timeout(_perServiceTimeout, onTimeout: () {
          throw TimeoutException('$service timed out after ${_perServiceTimeout.inSeconds}s');
        });
        _log.i('Fallback: $service succeeded for "${track.name}"');
        return response;
      } catch (e) {
        errors.add('$service: $e');
        _log.w('Fallback: $service failed for "${track.name}": $e');
        continue;
      }
    }

    throw Exception(
      'Failed to get streaming URL from any service:\n${errors.join('\n')}',
    );
  }
}
