import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class SourceAiException implements Exception {
  const SourceAiException(this.messageKey);
  final String messageKey;
  @override
  String toString() => messageKey;
}

abstract interface class SourceAiTransport {
  String? get userId;
  Future<Object?> invoke(
    String function, {
    required Object body,
    List<http.MultipartFile>? files,
    Future<void>? abortSignal,
  });
}

class SupabaseSourceAiTransport implements SourceAiTransport {
  const SupabaseSourceAiTransport(this.client);
  final SupabaseClient client;
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Future<Object?> invoke(
    String function, {
    required Object body,
    List<http.MultipartFile>? files,
    Future<void>? abortSignal,
  }) async {
    final owner = userId;
    final token = client.auth.currentSession?.accessToken;
    if (owner == null || token == null || token.isEmpty) {
      throw const SourceAiException('aiSignIn');
    }
    final result = await client.functions.invoke(
      function,
      // Bind the clicked account before the SDK's asynchronous auth lookup.
      headers: {'Authorization': 'Bearer $token'},
      body: body,
      files: files,
      abortSignal: abortSignal,
    );
    if (userId != owner) throw const SourceAiException('aiAccountChanged');
    return result.data;
  }
}

class SourceAnalysisItem {
  const SourceAnalysisItem({
    required this.id,
    required this.label,
    required this.value,
  });
  final String id;
  final String label;
  final String value;
  Map<String, String> toJson() => {'id': id, 'label': label, 'value': value};
}

class SourceSuggestion {
  const SourceSuggestion({
    required this.itemId,
    required this.intent,
    required this.needsClarification,
    this.proposedValue,
    this.sourceQuote,
    this.question,
  });
  final String itemId;
  final String intent;
  final bool needsClarification;
  final String? proposedValue;
  final String? sourceQuote;
  final String? question;
}

class SourceAnalysisResult {
  SourceAnalysisResult({
    required List<SourceSuggestion> suggestions,
    required List<String> warnings,
  }) : suggestions = List.unmodifiable(suggestions),
       warnings = List.unmodifiable(warnings);
  final List<SourceSuggestion> suggestions;
  final List<String> warnings;
}

/// Calls only the configured authenticated application service. No OpenAI key,
/// audio path, or direct provider destination is accepted from the client.
class SourceAnalysisClient {
  const SourceAnalysisClient({required this.transport});
  factory SourceAnalysisClient.forSupabase(SupabaseClient client) =>
      SourceAnalysisClient(transport: SupabaseSourceAiTransport(client));
  final SourceAiTransport transport;
  static const maxAudioBytes = 20 * 1024 * 1024;
  String? get userId => transport.userId;
  bool get signedIn => transport.userId != null;

  Future<Object?> _invoke(
    String function,
    Object body, {
    List<http.MultipartFile>? files,
    String? expectedUserId,
  }) async {
    if (!signedIn) throw const SourceAiException('aiSignIn');
    if (expectedUserId != null && userId != expectedUserId) {
      throw const SourceAiException('aiAccountChanged');
    }
    final owner = transport.userId;
    final abort = Completer<void>();
    final timer = Timer(const Duration(seconds: 55), () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final result = await transport
          .invoke(function, body: body, files: files, abortSignal: abort.future)
          .timeout(const Duration(seconds: 55));
      if (transport.userId != owner) {
        throw const SourceAiException('aiAccountChanged');
      }
      if (result is! Map || result['status'] != 'review_required') {
        throw const SourceAiException('aiInvalidResult');
      }
      return result;
    } on SourceAiException {
      rethrow;
    } on FunctionException catch (problem) {
      // Provider/server response details may contain private data. Expose only
      // safe, local message keys based on the HTTP status, never raw messages.
      throw SourceAiException(switch (problem.status) {
        401 || 403 => 'aiSignIn',
        429 => 'aiAllowance',
        503 => 'aiUnavailable',
        504 => 'aiTimeout',
        _ => 'aiFailed',
      });
    } on TimeoutException {
      throw const SourceAiException('aiTimeout');
    } catch (_) {
      throw const SourceAiException('aiFailed');
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<SourceAnalysisResult> analyze({
    required String sourceText,
    required List<SourceAnalysisItem> currentItems,
    required bool consent,
    String? expectedUserId,
  }) async {
    if (!consent) throw const SourceAiException('aiConsentRequired');
    if (sourceText.trim().isEmpty ||
        sourceText.runes.length > 12000 ||
        utf8.encode(sourceText).length > 32000) {
      throw const SourceAiException('aiSourceLimit');
    }
    if (currentItems.isEmpty || currentItems.length > 20) {
      throw const SourceAiException('aiItemLimit');
    }
    final ids = <String>{};
    for (final item in currentItems) {
      if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(item.id) ||
          !ids.add(item.id) ||
          item.label.trim().isEmpty ||
          item.label.runes.length > 200 ||
          item.value.trim().isEmpty ||
          item.value.runes.length > 2000) {
        throw const SourceAiException('aiItemLimit');
      }
    }
    final body = {
      'consent': true,
      'source_text': sourceText,
      'current_items': currentItems.map((item) => item.toJson()).toList(),
    };
    if (utf8.encode(jsonEncode(body)).length > 49152) {
      throw const SourceAiException('aiSourceLimit');
    }
    final raw =
        await _invoke('analyze-source', body, expectedUserId: expectedUserId)
            as Map;
    final rows = raw['suggestions'];
    final warnings = raw['warnings'];
    if (rows is! List ||
        rows.length > currentItems.length ||
        warnings is! List ||
        warnings.length > 20 ||
        warnings.any(
          (warning) => warning is! String || warning.length > 1000,
        )) {
      throw const SourceAiException('aiInvalidResult');
    }
    final suggestions = <SourceSuggestion>[];
    final seen = <String>{};
    for (final row in rows) {
      if (row is! Map ||
          row['item_id'] is! String ||
          !ids.contains(row['item_id']) ||
          !seen.add(row['item_id'] as String) ||
          row['intent'] is! String ||
          !{
            'request',
            'tentative',
            'withdrawal',
            'unclear',
            'no_change',
          }.contains(row['intent']) ||
          row['needs_clarification'] is! bool) {
        throw const SourceAiException('aiInvalidResult');
      }
      String? nullableText(String key, int limit) {
        final value = row[key];
        if (value != null &&
            (value is! String || value.isEmpty || value.length > limit)) {
          throw const SourceAiException('aiInvalidResult');
        }
        return value as String?;
      }

      final quote = nullableText('source_quote', 3000);
      final proposed = nullableText('proposed_value', 4000);
      final question = nullableText('question', 600);
      final clarification = row['needs_clarification'] as bool;
      if ((quote != null && !sourceText.contains(quote)) ||
          (proposed != null &&
              (quote == null ||
                  !quote.contains(proposed) ||
                  clarification ||
                  row['intent'] != 'request'))) {
        throw const SourceAiException('aiInvalidResult');
      }
      suggestions.add(
        SourceSuggestion(
          itemId: row['item_id'] as String,
          intent: row['intent'] as String,
          needsClarification: clarification,
          sourceQuote: quote,
          proposedValue: proposed,
          question: question,
        ),
      );
    }
    return SourceAnalysisResult(
      suggestions: suggestions,
      warnings: warnings.cast<String>(),
    );
  }

  Future<String> transcribe({
    required Uint8List audio,
    required String mimeType,
    required bool consent,
    String? expectedUserId,
  }) async {
    if (!consent) throw const SourceAiException('aiConsentRequired');
    if (audio.isEmpty || audio.length > maxAudioBytes) {
      throw const SourceAiException('aiAudioLimit');
    }
    final extension = switch (mimeType) {
      'audio/mp4' => 'm4a',
      'audio/webm' => 'webm',
      _ => null,
    };
    if (extension == null) throw const SourceAiException('aiAudioFormat');
    final file = http.MultipartFile.fromBytes(
      'audio',
      audio,
      filename: 'recording.$extension',
      contentType: http.MediaType.parse(mimeType),
    );
    final raw =
        await _invoke(
              'transcribe-recording',
              <String, String>{'consent': 'true'},
              files: [file],
              expectedUserId: expectedUserId,
            )
            as Map;
    final text = raw['text'];
    if (raw['kind'] != 'machine_transcript' ||
        text is! String ||
        text.trim().isEmpty ||
        text.length > 30000) {
      throw const SourceAiException('aiInvalidResult');
    }
    return text;
  }
}
