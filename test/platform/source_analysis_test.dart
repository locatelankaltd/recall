import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:recall_next/cloud/source_analysis.dart';
import 'package:recall_next/cloud/recall_api.dart';

class FakeSourceAiTransport implements SourceAiTransport {
  @override
  String? userId = 'account-a';
  final calls =
      <({String function, Object body, List<http.MultipartFile>? files})>[];
  Object? response;
  Future<Object?> Function()? handler;
  @override
  Future<Object?> invoke(
    String function, {
    required Object body,
    List<http.MultipartFile>? files,
    Future<void>? abortSignal,
  }) async {
    calls.add((function: function, body: body, files: files));
    return handler == null ? response : await handler!();
  }
}

void main() {
  const source =
      'Please change the fee to EUR 850. நாளை is not a date agreement.';
  const items = [
    SourceAnalysisItem(id: 'fee', label: 'Total fee', value: 'EUR 600'),
  ];
  Map<String, Object?> result({
    String? quote = source,
    String? value = 'EUR 850',
    String intent = 'request',
    bool clarify = false,
    String? question,
  }) => {
    'status': 'review_required',
    'suggestions': [
      {
        'item_id': 'fee',
        'proposed_value': value,
        'source_quote': quote,
        'intent': intent,
        'needs_clarification': clarify,
        'question': question,
      },
    ],
    'warnings': <String>[],
  };
  Matcher issue(String key) => isA<SourceAiException>().having(
    (error) => error.messageKey,
    'safe message',
    key,
  );

  test(
    'both actions require explicit consent before any transport request',
    () async {
      final transport = FakeSourceAiTransport();
      final client = SourceAnalysisClient(transport: transport);
      await expectLater(
        client.analyze(sourceText: source, currentItems: items, consent: false),
        throwsA(issue('aiConsentRequired')),
      );
      await expectLater(
        client.transcribe(
          audio: Uint8List.fromList([1]),
          mimeType: 'audio/mp4',
          consent: false,
        ),
        throwsA(issue('aiConsentRequired')),
      );
      expect(transport.calls, isEmpty);
    },
  );

  test(
    'analysis preserves multilingual text and sends only selected source/current item fields',
    () async {
      final transport = FakeSourceAiTransport()..response = result();
      final response = await SourceAnalysisClient(
        transport: transport,
      ).analyze(sourceText: source, currentItems: items, consent: true);
      final call = transport.calls.single;
      expect(call.function, 'analyze-source');
      expect(call.files, isNull);
      expect(call.body, {
        'consent': true,
        'source_text': source,
        'current_items': [
          {'id': 'fee', 'label': 'Total fee', 'value': 'EUR 600'},
        ],
      });
      expect(response.suggestions.single.proposedValue, 'EUR 850');
      expect(response.suggestions.single.sourceQuote, source);
      expect(() => response.suggestions.clear(), throwsUnsupportedError);
    },
  );

  test(
    'source, byte, item and duplicate bounds fail before transport',
    () async {
      final transport = FakeSourceAiTransport();
      final client = SourceAnalysisClient(transport: transport);
      for (final invalid in ['', 'a' * 12001, '😀' * 9000]) {
        await expectLater(
          client.analyze(
            sourceText: invalid,
            currentItems: items,
            consent: true,
          ),
          throwsA(issue('aiSourceLimit')),
        );
      }
      await expectLater(
        client.analyze(
          sourceText: source,
          currentItems: [...items, ...items],
          consent: true,
        ),
        throwsA(issue('aiItemLimit')),
      );
      expect(transport.calls, isEmpty);
    },
  );

  test(
    'unsupported evidence and proposed values cannot become accepted draft text',
    () async {
      final transport = FakeSourceAiTransport();
      final client = SourceAnalysisClient(transport: transport);
      for (final invalid in [
        result(quote: 'A made-up source quote'),
        result(value: 'USD 900'),
        result(intent: 'tentative'),
        result(clarify: true),
      ]) {
        transport.response = invalid;
        await expectLater(
          client.analyze(
            sourceText: source,
            currentItems: items,
            consent: true,
          ),
          throwsA(issue('aiInvalidResult')),
        );
      }
      transport.response = result(
        value: null,
        intent: 'tentative',
        clarify: true,
        question: 'What fee is intended?',
      );
      final valid = await client.analyze(
        sourceText: source,
        currentItems: items,
        consent: true,
      );
      expect(valid.suggestions.single.proposedValue, isNull);
      expect(valid.suggestions.single.question, 'What fee is intended?');
    },
  );

  test(
    'signed-out and consent-account changes fail before sending source',
    () async {
      final transport = FakeSourceAiTransport();
      final client = SourceAnalysisClient(transport: transport);
      transport.userId = null;
      await expectLater(
        client.analyze(sourceText: source, currentItems: items, consent: true),
        throwsA(issue('aiSignIn')),
      );
      transport.userId = 'account-b';
      await expectLater(
        client.analyze(
          sourceText: source,
          currentItems: items,
          consent: true,
          expectedUserId: 'account-a',
        ),
        throwsA(issue('aiAccountChanged')),
      );
      expect(transport.calls, isEmpty);
    },
  );

  test('account changes while awaiting a result discard it', () async {
    final completion = Completer<Object?>();
    final transport = FakeSourceAiTransport()
      ..handler = () => completion.future;
    final pending = SourceAnalysisClient(
      transport: transport,
    ).analyze(sourceText: source, currentItems: items, consent: true);
    transport.userId = 'account-b';
    completion.complete(result());
    await expectLater(pending, throwsA(issue('aiAccountChanged')));
    expect(transport.calls, hasLength(1));
  });

  test(
    'transcription sends exact bytes with a safe filename and separate multipart consent',
    () async {
      final transport = FakeSourceAiTransport()
        ..response = {
          'status': 'review_required',
          'kind': 'machine_transcript',
          'text': 'A possible transcript. தமிழ்',
        };
      final bytes = Uint8List.fromList([
        0,
        0,
        0,
        12,
        102,
        116,
        121,
        112,
        77,
        52,
        65,
        32,
      ]);
      final transcript = await SourceAnalysisClient(
        transport: transport,
      ).transcribe(audio: bytes, mimeType: 'audio/mp4', consent: true);
      expect(transcript, 'A possible transcript. தமிழ்');
      final call = transport.calls.single;
      expect(call.function, 'transcribe-recording');
      expect(call.body, {'consent': 'true'});
      final file = call.files!.single;
      expect(file.field, 'audio');
      expect(file.filename, 'recording.m4a');
      expect(file.contentType.toString(), 'audio/mp4');
      expect(await file.finalize().toBytes(), bytes);
    },
  );

  test(
    'audio size/type and unreviewable transcript results are rejected',
    () async {
      final transport = FakeSourceAiTransport();
      final client = SourceAnalysisClient(transport: transport);
      for (final bytes in [
        Uint8List(0),
        Uint8List(SourceAnalysisClient.maxAudioBytes + 1),
      ]) {
        await expectLater(
          client.transcribe(audio: bytes, mimeType: 'audio/mp4', consent: true),
          throwsA(issue('aiAudioLimit')),
        );
      }
      await expectLater(
        client.transcribe(
          audio: Uint8List(1),
          mimeType: 'application/octet-stream',
          consent: true,
        ),
        throwsA(issue('aiAudioFormat')),
      );
      expect(transport.calls, isEmpty);
      transport.response = {
        'status': 'review_required',
        'kind': 'original_text',
        'text': 'Not authenticated',
      };
      await expectLater(
        client.transcribe(
          audio: Uint8List(1),
          mimeType: 'audio/webm',
          consent: true,
        ),
        throwsA(issue('aiInvalidResult')),
      );
    },
  );

  test(
    'service errors expose safe local keys, never private server/provider details',
    () async {
      final transport = FakeSourceAiTransport();
      final client = SourceAnalysisClient(transport: transport);
      for (final entry in {
        401: 'aiSignIn',
        429: 'aiAllowance',
        503: 'aiUnavailable',
        504: 'aiTimeout',
        500: 'aiFailed',
      }.entries) {
        transport.handler = () async => throw RecallApiException(
          'Private source or provider credential',
          status: entry.key,
        );
        await expectLater(
          client.analyze(
            sourceText: source,
            currentItems: items,
            consent: true,
          ),
          throwsA(issue(entry.value)),
        );
      }
      transport.handler = () async =>
          throw TimeoutException('Private endpoint detail');
      await expectLater(
        client.analyze(sourceText: source, currentItems: items, consent: true),
        throwsA(issue('aiTimeout')),
      );
      expect(
        transport.calls,
        hasLength(6),
      ); // Exactly one call per user action.
    },
  );
}
