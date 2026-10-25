import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import '../app_services.dart';
import '../cloud/source_analysis.dart';
import '../data/recall_controller.dart';
import '../data/recording_files.dart';
import '../design/recall_icon.dart';
import '../design/recall_theme.dart';
import '../l10n/strings.dart';

class UpdateEditor extends StatefulWidget {
  const UpdateEditor({
    super.key,
    required this.controller,
    required this.projectId,
    this.initialItemId,
    this.initialSourceText,
    this.sourceAnalysisClient,
  });
  final RecallController controller;
  final String projectId;
  final String? initialItemId;
  final String? initialSourceText;
  final SourceAnalysisClient? sourceAnalysisClient;
  @override
  State<UpdateEditor> createState() => _UpdateEditorState();
}

class _UpdateEditorState extends State<UpdateEditor>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _source = TextEditingController();
  final _title = TextEditingController();
  final _details = TextEditingController();
  final _amount = TextEditingController();
  final _language = TextEditingController(text: 'en');
  AudioRecorder? _audioRecorder;
  AudioRecorder get _recorder => _audioRecorder ??= AudioRecorder();
  final _stopwatch = Stopwatch();
  static const _currencies = ['USD', 'EUR', 'GBP', 'CAD', 'AUD'];
  String? _itemId;
  String? _baseRevisionId;
  DateTime? _dueDate;
  String _currency = 'USD';
  String _kind = 'personalRecollection';
  bool _reviewed = false;
  bool _busy = false;
  bool _recording = false;
  bool _startingRecording = false;
  bool _audioRetained = false;
  String? _audioPath;
  String? _pendingAudioPath;
  String? _lastImportedFile;
  SourceAnalysisResult? _analysis;
  String? _aiErrorKey;
  bool _aiWorking = false;
  bool _hasReviewedTranscript = false;
  Timer? _timer;

  Project? get _project => widget.controller.projectById(widget.projectId);
  PlanItem? get _item =>
      _project?.items.where((item) => item.id == _itemId).firstOrNull;
  SourceAnalysisClient? get _sourceAi {
    if (!widget.controller.isCloud) return null;
    final injected = widget.sourceAnalysisClient;
    if (injected != null) return injected.signedIn ? injected : null;
    final services = RecallServices.maybeOf(context);
    final client = services?.cloud.client;
    if (client == null ||
        services?.cloud.session.isSignedIn != true ||
        services?.cloud.session.emailVerified != true) {
      return null;
    }
    return SourceAnalysisClient.forCloud(client);
  }

  String _t(String key, String fallback) {
    if (!mounted) return fallback;
    final value = tr(context, key);
    return value == key ? fallback : value;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final project = _project;
    final selected =
        project?.items
            .where((item) => item.id == widget.initialItemId)
            .firstOrNull ??
        project?.items.firstOrNull;
    if (selected != null) _selectItem(selected);
    _language.text = widget.controller.locale;
    final incoming = widget.initialSourceText;
    if (incoming != null && incoming.length <= 30000) {
      _source.text = incoming;
      _kind = 'originalText';
    }
  }

  void _selectItem(PlanItem item) {
    _itemId = item.id;
    _baseRevisionId = _project?.currentRevision.id;
    _title.text = item.title;
    _details.text = item.details;
    _dueDate = item.dueDate;
    _currency = item.currency;
    _amount.text = item.amountMinor == null
        ? ''
        : _currencies.contains(item.currency)
        ? (item.amountMinor! / 100).toStringAsFixed(2)
        : '';
    _reviewed = false;
    _analysis = null;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _appendSource(String text) {
    final current = _source.text;
    final separator = current.trim().isEmpty ? '' : '\n\n';
    if (current.length + separator.length + text.length > 30000) {
      _toast(
        _t(
          'sourceTooLong',
          'Keep this source within 30,000 characters. Your existing text has not been replaced.',
        ),
      );
      return false;
    }
    _source.text = '$current$separator$text';
    _source.selection = TextSelection.collapsed(offset: _source.text.length);
    setState(() {
      _reviewed = false;
      _analysis = null;
    });
    return true;
  }

  String _currentAiValue(PlanItem item) => [
    item.title,
    if (item.details.isNotEmpty) item.details,
    '${tr(context, 'date')}: ${item.dueDate?.toIso8601String().split('T').first ?? tr(context, 'noDate')}',
    '${tr(context, 'totalFee')}: ${item.amountMinor == null ? tr(context, 'noAmount') : '${item.currency} ${(item.amountMinor! / 100).toStringAsFixed(2)}'}',
  ].join('\n');

  Future<bool> _aiConsent({
    required bool audio,
    String? source,
    String? current,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            tr(
              ctx,
              audio ? 'aiTranscribeConsentTitle' : 'aiAnalyzeConsentTitle',
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    ctx,
                    audio ? 'aiTranscribeConsentBody' : 'aiAnalyzeConsentBody',
                  ),
                ),
                if (!audio) ...[
                  const SizedBox(height: 16),
                  Text(
                    tr(ctx, 'aiSelectedCurrentItem'),
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                  Text(current ?? ''),
                  const SizedBox(height: 16),
                  Text(
                    tr(ctx, 'source'),
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                  SelectableText(source ?? ''),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(ctx, 'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(ctx, audio ? 'aiSendAudio' : 'aiSendText')),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _analyzeSource() async {
    final client = _sourceAi;
    final item = _item;
    if (client == null || item == null || _busy) return;
    final owner = client.userId;
    final source = _source.text;
    final current = _currentAiValue(item);
    if (source.trim().isEmpty ||
        source.runes.length > 12000 ||
        utf8.encode(source).length > 32000) {
      _toast(tr(context, 'aiSourceLimit'));
      return;
    }
    if (item.title.runes.length > 200 || current.runes.length > 2000) {
      _toast(tr(context, 'aiItemLimit'));
      return;
    }
    if (!await _aiConsent(audio: false, source: source, current: current) ||
        !mounted) {
      return;
    }
    if (client.userId != owner || _sourceAi?.userId != owner) {
      _toast(tr(context, 'aiAccountChanged'));
      return;
    }
    setState(() {
      _busy = true;
      _aiWorking = true;
      _aiErrorKey = null;
      _analysis = null;
    });
    try {
      final result = await client.analyze(
        sourceText: source,
        currentItems: [
          SourceAnalysisItem(id: item.id, label: item.title, value: current),
        ],
        consent: true,
        expectedUserId: owner,
      );
      if (!mounted) return;
      setState(() {
        _analysis = result;
        _reviewed = false;
      });
    } on SourceAiException catch (problem) {
      if (mounted) setState(() => _aiErrorKey = problem.messageKey);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _aiWorking = false;
        });
      }
    }
  }

  Future<void> _transcribeRecording() async {
    final client = _sourceAi;
    final path = _audioPath;
    if (client == null || path == null || _busy || _recording) return;
    final owner = client.userId;
    if (!await _aiConsent(audio: true) || !mounted) return;
    if (client.userId != owner || _sourceAi?.userId != owner) {
      _toast(tr(context, 'aiAccountChanged'));
      return;
    }
    setState(() {
      _busy = true;
      _aiWorking = true;
      _aiErrorKey = null;
    });
    try {
      final bytes = await readRecordingBytes(path);
      if (client.userId != owner) {
        throw const SourceAiException('aiAccountChanged');
      }
      final transcript = await client.transcribe(
        audio: bytes,
        mimeType: kIsWeb ? 'audio/webm' : 'audio/mp4',
        consent: true,
        expectedUserId: owner,
      );
      if (!mounted) return;
      final review = TextEditingController(text: transcript);
      final approved = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(ctx, 'aiTranscriptReviewTitle')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(ctx, 'aiTranscriptReviewNote')),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('transcript-review'),
                  controller: review,
                  minLines: 5,
                  maxLines: 12,
                  maxLength: 30000,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr(ctx, 'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, review.text),
              child: Text(tr(ctx, 'aiAppendTranscript')),
            ),
          ],
        ),
      );
      review.dispose();
      if (!mounted || approved == null || approved.trim().isEmpty) return;
      if (client.userId != owner || _sourceAi?.userId != owner) {
        _toast(tr(context, 'aiAccountChanged'));
        return;
      }
      if (_appendSource(approved)) {
        setState(() {
          _kind = 'personalRecollection';
          _hasReviewedTranscript = true;
        });
      }
    } on SourceAiException catch (problem) {
      if (mounted) setState(() => _aiErrorKey = problem.messageKey);
    } catch (_) {
      if (mounted) setState(() => _aiErrorKey = 'recordingUnavailable');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _aiWorking = false;
        });
      }
    }
  }

  Widget _analysisCard(SourceAnalysisResult result) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'aiDraftTitle'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(tr(context, 'aiDraftNote')),
          if (result.suggestions.isEmpty) Text(tr(context, 'aiNoSuggestions')),
          for (final suggestion in result.suggestions) ...[
            const SizedBox(height: 16),
            Text(
              tr(context, switch (suggestion.intent) {
                'request' => 'aiIntentRequest',
                'tentative' => 'aiIntentTentative',
                'withdrawal' => 'aiIntentWithdrawal',
                'no_change' => 'aiIntentNoChange',
                _ => 'aiIntentUnclear',
              }),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (suggestion.proposedValue != null) ...[
              Text(tr(context, 'aiSuggestedText')),
              SelectableText(suggestion.proposedValue!),
            ],
            if (suggestion.sourceQuote != null) ...[
              const SizedBox(height: 8),
              Text(tr(context, 'aiSourceQuote')),
              SelectableText(suggestion.sourceQuote!),
            ],
            if (suggestion.question != null) ...[
              const SizedBox(height: 8),
              Text(tr(context, 'aiQuestion')),
              Text(suggestion.question!),
            ],
          ],
          for (final warning in result.warnings) ...[
            const SizedBox(height: 8),
            Text(
              tr(context, warning),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    ),
  );

  Future<void> _paste() async {
    try {
      final value = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      if (value?.text?.trim().isNotEmpty != true) {
        _toast(_t('emptyClipboard', 'There is no text on the clipboard.'));
        return;
      }
      _appendSource(value!.text!);
    } catch (_) {
      _toast(
        _t(
          'clipboardError',
          'Clipboard access was not available. You can type the source below.',
        ),
      );
    }
  }

  Future<void> _importText() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'md', 'csv', 'vtt', 'srt'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      if (file.size > 1024 * 1024 || (file.bytes?.length ?? 0) > 1024 * 1024) {
        _toast(_t('fileTooLarge', 'Choose a text file smaller than 1 MB.'));
        return;
      }
      final bytes = file.bytes;
      if (bytes == null) {
        _toast(
          _t(
            'fileUnreadable',
            'This file could not be read. Your existing source is unchanged.',
          ),
        );
        return;
      }
      final text = utf8.decode(bytes).replaceFirst('\uFEFF', '');
      if (text.trim().isEmpty) {
        _toast(_t('fileEmpty', 'This file does not contain text.'));
        return;
      }
      if (!_appendSource(text)) return;
      setState(() {
        _lastImportedFile = file.name;
        _kind = 'originalText';
      });
    } on FormatException {
      _toast(
        _t(
          'fileEncoding',
          'Choose a UTF-8 text file. Nothing in your source has been replaced.',
        ),
      );
    } catch (_) {
      _toast(
        _t(
          'fileImportFailed',
          'The file could not be imported. Your source is still here.',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _record() async {
    if (_recording) {
      await _stopRecording();
      return;
    }
    final consent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(dialogContext, 'record')),
        content: Text(tr(dialogContext, 'recordNotice')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr(dialogContext, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('beginRecording', 'Start recording')),
          ),
        ],
      ),
    );
    if (consent != true || !mounted) return;
    setState(() => _startingRecording = true);
    try {
      if (!await _recorder.hasPermission()) {
        _toast(
          _t(
            'micDenied',
            'Microphone access was not granted. You can write your recollection instead.',
          ),
        );
        return;
      }
      if (!mounted) return;
      // Do not replace an existing recording without the user's explicit removal.
      if (_audioPath != null) {
        _toast(
          _t(
            'oneRecording',
            'Remove or download the current recording before making another.',
          ),
        );
        return;
      }
      if (!await _discardPendingRecording()) {
        _toast(
          _t(
            'audioRemoveFailed',
            'The unfinished recording could not be removed. Try again.',
          ),
        );
        return;
      }
      final encoder = kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc;
      if (!await _recorder.isEncoderSupported(encoder)) {
        _toast(
          _t(
            'recordUnsupported',
            'Recording is not supported by this browser or device. You can still add text.',
          ),
        );
        return;
      }
      final path = await createRecordingPath();
      _pendingAudioPath = path;
      if (!mounted) {
        await _discardPendingRecording();
        return;
      }
      await _recorder.start(RecordConfig(encoder: encoder), path: path);
      if (!mounted) {
        await _releaseRecorder(cancel: true);
        await _discardPendingRecording();
        return;
      }
      _stopwatch.reset();
      _stopwatch.start();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
        if (_stopwatch.elapsed.inMinutes >= 10) unawaited(_stopRecording());
      });
      setState(() {
        _recording = true;
        _kind = 'personalRecollection';
      });
    } catch (_) {
      await _releaseRecorder(cancel: true);
      await _discardPendingRecording();
      _toast(
        _t(
          'recordFailed',
          'Recording could not start. Your written source has been kept.',
        ),
      );
    } finally {
      if (mounted) setState(() => _startingRecording = false);
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _timer?.cancel();
    _stopwatch.stop();
    setState(() {
      _recording = false;
      _startingRecording = true;
    });
    try {
      final path = await _recorder.stop();
      if (!mounted) {
        await discardRecording(path);
        return;
      }
      if (path == null) {
        await _releaseRecorder(cancel: true);
        await _discardPendingRecording();
        _toast(
          _t(
            'audioUnavailable',
            'No recording was returned. Your written source is unchanged.',
          ),
        );
        return;
      }
      setState(() => _audioPath = path);
      _pendingAudioPath = null;
      _toast(
        kIsWeb
            ? _t(
                'webAudioSession',
                'Recording ready in this browser session. Download it before leaving.',
              )
            : tr(context, 'recorded'),
      );
    } catch (_) {
      // A failed stop must still attempt cancellation and disposal so the
      // microphone is not deliberately left running behind the error message.
      await _releaseRecorder(cancel: true);
      await _discardPendingRecording();
      _toast(
        _t(
          'stopFailed',
          'The recording could not be saved. Your written source is unchanged.',
        ),
      );
    } finally {
      if (mounted) setState(() => _startingRecording = false);
    }
  }

  Future<void> _downloadAudio() async {
    final path = _audioPath;
    if (path == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await readRecordingBytes(path);
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: _t('downloadAudio', 'Save a copy of the recording'),
        fileName: kIsWeb ? 'recall-debrief.webm' : 'recall-debrief.m4a',
        bytes: bytes,
      );
      if (savedPath != null) {
        _toast(_t('audioCopySaved', 'Recording copy saved.'));
      }
    } catch (_) {
      _toast(
        _t(
          'audioSaveFailed',
          'The recording copy could not be saved. The current recording is unchanged.',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeAudio() async {
    final path = _audioPath;
    try {
      await discardRecording(path);
      if (mounted) setState(() => _audioPath = null);
    } catch (_) {
      _toast(
        _t(
          'audioRemoveFailed',
          'The recording could not be removed. Try again.',
        ),
      );
    }
  }

  String _normalizeAmount(String text) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var normalized = text.trim();
    for (var i = 0; i < 10; i++) {
      normalized = normalized
          .replaceAll(arabic[i], '$i')
          .replaceAll(persian[i], '$i');
    }
    return normalized.replaceAll('٫', '.');
  }

  int? _minorAmount(String text) {
    final clean = _normalizeAmount(text);
    if (clean.isEmpty) return null;
    if (!RegExp(r'^\d{1,9}([.,]\d{1,2})?$').hasMatch(clean)) {
      throw const FormatException();
    }
    final parts = clean.split(RegExp('[.,]'));
    return int.parse(parts[0]) * 100 +
        (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  }

  Future<void> _chooseDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final firstDate = DateTime(1900);
    final lastDate = DateTime(2200);
    final selected = _dueDate ?? today;
    final initialDate = selected.isBefore(firstDate)
        ? firstDate
        : selected.isAfter(lastDate)
        ? lastDate
        : selected;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (date != null && mounted) {
      setState(() {
        _dueDate = date;
        _reviewed = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_currencies.contains(_item?.currency)) {
      _toast(
        _t(
          'unsupportedCurrency',
          'This item uses a currency this editor does not yet support. Its amount and currency have been kept unchanged.',
        ),
      );
      return;
    }
    if (!_form.currentState!.validate()) return;
    if (!_reviewed) {
      _toast(
        _t(
          'reviewValuesFirst',
          'Review the values and select the confirmation below.',
        ),
      );
      return;
    }
    final item = _item;
    if (item == null) return;
    // ListView may dispose a field outside its viewport. Validate controller
    // values here as well, so an off-screen field cannot bypass validation.
    if (_source.text.trim().isEmpty ||
        _title.text.trim().isEmpty ||
        _language.text.trim().isEmpty) {
      _toast(tr(context, 'sourceRequired'));
      return;
    }
    int? amount;
    try {
      amount = _minorAmount(_amount.text);
    } on FormatException {
      _toast(tr(context, 'invalidAmount'));
      return;
    }
    if (_title.text.trim() == item.title &&
        _details.text.trim() == item.details &&
        DateUtils.isSameDay(_dueDate, item.dueDate) &&
        amount == item.amountMinor &&
        _currency == item.currency) {
      _toast(
        _t(
          'noChangedValues',
          'Change at least one plan value before saving a proposal.',
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.proposeChange(
        projectId: widget.projectId,
        itemId: item.id,
        title: _title.text.trim(),
        details: _details.text.trim(),
        dueDate: _dueDate,
        clearDueDate: _dueDate == null,
        amountMinor: amount,
        clearAmount: amount == null,
        currency: _currency,
        sourceText: _source.text.trim(),
        sourceLanguage: _language.text.trim(),
        sourceKind: _kind,
        attachmentPath: kIsWeb ? null : _audioPath,
        expectedBaseRevisionId: _baseRevisionId,
      );
      _audioRetained = !kIsWeb;
      if (!mounted) return;
      _toast(
        _t(
          'proposalSaved',
          'Proposal saved. The current plan has not changed.',
        ),
      );
      Navigator.pop(context, true);
    } catch (_) {
      _toast(
        widget.controller.error ??
            _t(
              'saveFailed',
              'Could not save. Your source and edits are still here.',
            ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _releaseRecorder({bool cancel = false}) async {
    final recorder = _audioRecorder;
    _audioRecorder = null;
    if (recorder == null) return;
    if (cancel) {
      try {
        await recorder.cancel();
      } catch (_) {
        /* Disposal is still attempted if cancellation fails. */
      }
    }
    try {
      await recorder.dispose();
    } catch (_) {
      /* No sensitive paths or source content in logs. */
    }
  }

  Future<bool> _discardPendingRecording() async {
    try {
      await discardRecording(_pendingAudioPath);
      _pendingAudioPath = null;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _cleanup() async {
    await _releaseRecorder(cancel: _recording || _startingRecording);
    if (!_audioRetained) {
      try {
        await discardRecording(_audioPath);
      } catch (_) {
        /* Pending-file cleanup must still run if another file cannot be removed. */
      }
    }
    await _discardPendingRecording();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive) &&
        _recording) {
      unawaited(_stopRecording());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _stopwatch.stop();
    unawaited(_cleanup());
    for (final controller in [_source, _title, _details, _amount, _language]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;
    final item = _item;
    final p = RecallPalette.of(context);
    final text = Theme.of(context).textTheme;
    if (project == null || project.items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(tr(context, 'addUpdate'))),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'noItems'), style: text.titleLarge),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(_t('back', 'Back')),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final enabled = !_busy && !_recording && !_startingRecording;
    final aiClient = _sourceAi;
    return PopScope(
      canPop: !_busy && !_recording && !_startingRecording,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr(context, 'addUpdate')),
          leading: IconButton(
            onPressed: enabled ? () => Navigator.pop(context) : null,
            tooltip: _t('back', 'Back'),
            icon: const RecallIcon(RecallGlyph.back),
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              key: const ValueKey('update-scroll'),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                Text(project.title, style: text.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  _t(
                    'manualReview',
                    'Add the source, then review the new plan values. No AI extraction or upload is running.',
                  ),
                  style: text.bodyMedium?.copyWith(color: p.muted),
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  key: const ValueKey('update-item'),
                  initialValue: _itemId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr(context, 'chooseItem'),
                  ),
                  items: project.items
                      .map(
                        (i) => DropdownMenuItem(
                          value: i.id,
                          child: Text(
                            i.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: enabled
                      ? (id) {
                          final chosen = project.items.firstWhere(
                            (i) => i.id == id,
                          );
                          setState(() => _selectItem(chosen));
                        }
                      : null,
                ),
                const SizedBox(height: 28),
                Text(tr(context, 'source'), style: text.titleLarge),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: enabled ? _paste : null,
                      icon: const RecallIcon(RecallGlyph.paste, size: 20),
                      label: Text(tr(context, 'paste')),
                    ),
                    OutlinedButton.icon(
                      onPressed: enabled ? _importText : null,
                      icon: const RecallIcon(RecallGlyph.file, size: 20),
                      label: Text(tr(context, 'file')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || _startingRecording ? null : _record,
                      icon: RecallIcon(
                        RecallGlyph.mic,
                        size: 20,
                        color: _recording ? p.change : null,
                      ),
                      label: Text(
                        _recording
                            ? tr(context, 'stop')
                            : tr(context, 'record'),
                      ),
                    ),
                  ],
                ),
                if (_recording)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        '${_t('recordingNow', 'Recording')} · ${_stopwatch.elapsed.inMinutes}:${(_stopwatch.elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: text.titleMedium?.copyWith(color: p.change),
                      ),
                    ),
                  ),
                if (_startingRecording)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_audioPath != null)
                  Container(
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: p.confirmedSurface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hasReviewedTranscript
                              ? tr(context, 'aiTranscriptAdded')
                              : kIsWeb
                              ? _t(
                                  'webAudioSession',
                                  'Recording available in this browser session only. Download it before leaving.',
                                )
                              : tr(context, 'recorded'),
                          style: text.bodyMedium,
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: enabled ? _downloadAudio : null,
                              child: Text(
                                _t(
                                  'downloadAudio',
                                  'Save a copy of the recording',
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: enabled ? _removeAudio : null,
                              child: Text(
                                _t('removeAudio', 'Remove recording'),
                              ),
                            ),
                            if (aiClient != null)
                              TextButton(
                                key: const ValueKey('transcribe-recording'),
                                onPressed: enabled
                                    ? _transcribeRecording
                                    : null,
                                child: Text(tr(context, 'aiTranscribeAction')),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (_lastImportedFile != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      '${_t('importedFile', 'Imported')}: $_lastImportedFile',
                      style: text.bodySmall,
                    ),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('update-source'),
                  controller: _source,
                  enabled: enabled,
                  minLines: 5,
                  maxLines: 10,
                  maxLength: 30000,
                  decoration: InputDecoration(
                    labelText: tr(context, 'source'),
                    hintText: tr(context, 'sourceHint'),
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => v?.trim().isEmpty != false
                      ? tr(context, 'sourceRequired')
                      : null,
                  onChanged: (_) => setState(() {
                    _reviewed = false;
                    _analysis = null;
                  }),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    key: const ValueKey('analyze-source'),
                    onPressed: enabled && aiClient != null
                        ? _analyzeSource
                        : null,
                    child: Text(tr(context, 'aiAnalyzeAction')),
                  ),
                ),
                if (aiClient == null)
                  Text(tr(context, 'aiAccountOnly'), style: text.bodySmall),
                if (_aiWorking) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  Text(tr(context, 'aiWorking')),
                ],
                if (_aiErrorKey != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      tr(context, _aiErrorKey!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                if (_analysis != null) ...[
                  const SizedBox(height: 12),
                  _analysisCard(_analysis!),
                ],
                if (_hasReviewedTranscript) ...[
                  const SizedBox(height: 12),
                  Text(
                    tr(context, 'aiTranscriptReviewNote'),
                    style: text.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'personalRecollection',
                      label: Text(tr(context, 'recollection')),
                    ),
                    ButtonSegment(
                      value: 'originalText',
                      label: Text(tr(context, 'original')),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: enabled
                      ? (values) => setState(() {
                          _kind = values.single;
                          _reviewed = false;
                        })
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('update-language'),
                  controller: _language,
                  enabled: enabled,
                  decoration: InputDecoration(
                    labelText: tr(context, 'sourceLanguage'),
                    hintText: 'English / Español / العربية',
                  ),
                  validator: (v) => v?.trim().isEmpty != false
                      ? tr(context, 'required')
                      : null,
                  onChanged: (_) => setState(() => _reviewed = false),
                ),
                const SizedBox(height: 28),
                Text(tr(context, 'currentPlan'), style: text.titleLarge),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: p.panel,
                    border: Border.all(color: p.line),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item?.title ?? '', style: text.titleMedium),
                      if (item?.details.isNotEmpty == true)
                        Text(item!.details, style: text.bodyMedium),
                      const SizedBox(height: 10),
                      Text(
                        item?.dueDate == null
                            ? tr(context, 'noDate')
                            : MaterialLocalizations.of(
                                context,
                              ).formatMediumDate(item!.dueDate!),
                        style: text.bodyMedium,
                      ),
                      if (item?.amountMinor != null &&
                          _currencies.contains(item?.currency))
                        Text(
                          '${item!.currency} ${(item.amountMinor! / 100).toStringAsFixed(2)} · ${tr(context, 'totalFee')}',
                          style: text.bodyMedium,
                        ),
                      if (!_currencies.contains(item?.currency))
                        Text(
                          _t(
                            'unsupportedCurrency',
                            'This item uses a currency this editor does not yet support. Its amount and currency have been kept unchanged.',
                          ),
                          style: text.bodyMedium,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Text(tr(context, 'newValues'), style: text.titleLarge),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('update-title'),
                  controller: _title,
                  enabled: enabled,
                  maxLength: 160,
                  decoration: InputDecoration(
                    labelText: tr(context, 'itemTitle'),
                  ),
                  validator: (v) => v?.trim().isEmpty != false
                      ? tr(context, 'required')
                      : null,
                  onChanged: (_) => setState(() => _reviewed = false),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('update-details'),
                  controller: _details,
                  enabled: enabled,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: tr(context, 'details'),
                  ),
                  onChanged: (_) => setState(() => _reviewed = false),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: enabled ? _chooseDate : null,
                  icon: const RecallIcon(RecallGlyph.calendar, size: 20),
                  label: Text(
                    _dueDate == null
                        ? tr(context, 'noDate')
                        : MaterialLocalizations.of(
                            context,
                          ).formatMediumDate(_dueDate!),
                  ),
                ),
                if (_dueDate != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: enabled
                          ? () => setState(() {
                              _dueDate = null;
                              _reviewed = false;
                            })
                          : null,
                      child: Text(_t('clearDate', 'Remove the proposed date')),
                    ),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('update-amount'),
                  controller: _amount,
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: tr(context, 'totalFee'),
                    helperText: _t(
                      'totalAmountNote',
                      'Total for this item, not an additional fee. No thousands separators.',
                    ),
                  ),
                  validator: (value) {
                    try {
                      _minorAmount(value ?? '');
                      return null;
                    } catch (_) {
                      return tr(context, 'invalidAmount');
                    }
                  },
                  onChanged: (_) => setState(() => _reviewed = false),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey('update-currency-$_itemId'),
                  initialValue: _currency,
                  decoration: InputDecoration(
                    labelText: tr(context, 'currency'),
                  ),
                  items: [
                    if (!_currencies.contains(_currency))
                      DropdownMenuItem(
                        value: _currency,
                        enabled: false,
                        child: Text(_currency),
                      ),
                    ..._currencies.map(
                      (c) => DropdownMenuItem(value: c, child: Text(c)),
                    ),
                  ],
                  onChanged: enabled && _currencies.contains(item?.currency)
                      ? (value) => setState(() {
                          _currency = value!;
                          _reviewed = false;
                        })
                      : null,
                ),
                const SizedBox(height: 18),
                CheckboxListTile(
                  key: const ValueKey('update-reviewed'),
                  value: _reviewed,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: enabled
                      ? (value) => setState(() => _reviewed = value ?? false)
                      : null,
                  title: Text(
                    _t(
                      'reviewedValues',
                      'I reviewed the source, values and conditions.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(tr(context, 'reviewNote'), style: text.bodySmall),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey('update-save'),
                  onPressed:
                      enabled &&
                          _reviewed &&
                          _currencies.contains(item?.currency)
                      ? _save
                      : null,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const RecallIcon(RecallGlyph.compare, size: 20),
                  label: Text(tr(context, 'keepChange')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
