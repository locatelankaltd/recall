import 'dart:convert';
import 'dart:math';

import '../domain/recall_models.dart';

/// Only canonical server snapshots enter an account workspace.
abstract class CloudProjectGateway {
  Future<List<Project>> fetchProjects();
  Future<Project> createProject({
    required String title,
    required String clientName,
    String category = 'Creative',
  });
  Future<Project?> mutateProject({
    required String projectId,
    required String action,
    Map<String, dynamic> payload = const {},
  });
}

abstract class CloudReviewGateway {
  Future<ReviewLink> createLink({
    required String projectId,
    required String revisionId,
    required String participantId,
    List<String>? itemIds,
    int ttlSeconds = 604800,
  });
  Future<List<ReviewLink>> listLinks(String projectId);
  Future<void> revokeLink(String linkId);
  Future<PublicReview> fetchReview(String token);
  Future<ReviewReceipt> respond({
    required String token,
    required String action,
    String note = '',
  });
}

/// Injectable RPC boundary keeps credentials and network effects out of tests.
abstract class CloudRpcTransport {
  Future<dynamic> rpc(String function, Map<String, dynamic> params);
}

class CloudException implements Exception {
  const CloudException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}

String newRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

Map<String, dynamic> cloudMap(dynamic value) {
  if (value is! Map) throw const FormatException('Invalid server response.');
  return Map<String, dynamic>.from(value);
}

class ReviewLink {
  const ReviewLink({
    required this.id,
    required this.expires,
    required this.revisionId,
    required this.participantId,
    required this.itemIds,
    this.token,
    this.revoked = false,
    this.responded = false,
  });
  final String id;
  final String? token;
  final DateTime expires;
  final String revisionId;
  final String participantId;
  final List<String> itemIds;
  final bool revoked;
  final bool responded;
  bool get expired => DateTime.now().isAfter(expires);
  factory ReviewLink.fromJson(Map<String, dynamic> json) => ReviewLink(
    id: json['id'] as String,
    token: json['token'] as String?,
    expires: DateTime.parse(json['expires'] as String),
    revisionId: json['revisionId'] as String,
    participantId: json['participantId'] as String,
    itemIds: List<String>.from(json['itemIds'] as List? ?? const []),
    revoked: json['revoked'] as bool? ?? false,
    responded: json['responded'] as bool? ?? false,
  );

  Uri urlFor(Uri applicationUrl) {
    if (token == null) {
      throw const CloudException('Create a new link to get a shareable URL.');
    }
    return Uri(
      scheme: applicationUrl.scheme,
      userInfo: applicationUrl.userInfo,
      host: applicationUrl.host,
      port: applicationUrl.hasPort ? applicationUrl.port : null,
      path: applicationUrl.path,
      fragment: Uri(queryParameters: {'review': token!}).query,
    );
  }
}

class ReviewChange {
  const ReviewChange({required this.itemId, this.previous, this.proposed});
  final String itemId;
  final PlanItem? previous;
  final PlanItem? proposed;
  factory ReviewChange.fromJson(Map<String, dynamic> json) => ReviewChange(
    itemId: json['itemId'] as String,
    previous: json['previous'] == null
        ? null
        : PlanItem.fromJson(cloudMap(json['previous'])),
    proposed: json['proposed'] == null
        ? null
        : PlanItem.fromJson(cloudMap(json['proposed'])),
  );
}

class PublicReview {
  const PublicReview({
    required this.projectTitle,
    required this.participantName,
    required this.revisionId,
    required this.version,
    required this.status,
    required this.changes,
    required this.evidence,
    required this.evidenceOmitted,
    required this.canRespond,
    required this.identity,
    this.response,
  });
  final String projectTitle;
  final String participantName;
  final String revisionId;
  final int version;
  final String status;
  final List<ReviewChange> changes;
  final List<Evidence> evidence;
  final bool evidenceOmitted;
  final bool canRespond;
  final String identity;
  final Map<String, dynamic>? response;
  factory PublicReview.fromJson(Map<String, dynamic> json) => PublicReview(
    projectTitle: json['projectTitle'] as String,
    participantName: json['participantName'] as String,
    revisionId: json['revisionId'] as String,
    version: json['version'] as int,
    status: json['status'] as String,
    changes: (json['changes'] as List)
        .map((item) => ReviewChange.fromJson(cloudMap(item)))
        .toList(growable: false),
    evidence: (json['evidence'] as List)
        .map((item) => Evidence.fromJson(cloudMap(item)))
        .toList(growable: false),
    evidenceOmitted: json['evidenceOmitted'] as bool? ?? false,
    canRespond: json['canRespond'] as bool,
    identity: json['identity'] as String? ?? 'link-holder',
    response: json['response'] == null ? null : cloudMap(json['response']),
  );
}

class ReviewReceipt {
  const ReviewReceipt({
    required this.receiptId,
    required this.revisionId,
    required this.version,
    required this.action,
    required this.status,
    required this.identity,
  });
  final String receiptId;
  final String revisionId;
  final int version;
  final String action;
  final String status;
  final String identity;
  factory ReviewReceipt.fromJson(Map<String, dynamic> json) => ReviewReceipt(
    receiptId: json['receiptId'] as String,
    revisionId: json['revisionId'] as String,
    version: json['version'] as int,
    action: json['action'] as String,
    status: json['status'] as String,
    identity: json['identity'] as String? ?? 'link-holder',
  );
}

/// Versions belong to one signed-in account and never survive account changes.
class RpcCloudProjectGateway implements CloudProjectGateway {
  RpcCloudProjectGateway({
    required this.transport,
    required this.currentUserId,
  });
  final CloudRpcTransport transport;
  final String? Function() currentUserId;
  final Map<String, int> _versions = {};
  String? _owner;
  final Map<String, String> _pendingRequests = {};
  final Map<String, String> _pendingCreates = {};

  String _account() {
    final user = currentUserId();
    if (_owner != user) {
      _versions.clear();
      _pendingRequests.clear();
      _pendingCreates.clear();
      _owner = user;
    }
    if (user == null) {
      throw const CloudException('Sign in to open your account workspace.');
    }
    return user;
  }

  void _checkAccount(String owner) {
    if (currentUserId() != owner) {
      _account();
      throw const CloudException(
        'The account changed. Open the workspace again.',
      );
    }
  }

  Project _snapshot(dynamic value) {
    final map = cloudMap(value);
    final project = Project.fromJson(cloudMap(map['project']));
    final version = map['version'] as int;
    if (version < 1) throw const FormatException('Invalid project version.');
    _versions[project.id] = version;
    return project;
  }

  @override
  Future<List<Project>> fetchProjects() async {
    final owner = _account();
    final result = await transport.rpc('recall_list_projects', {});
    _checkAccount(owner);
    if (result is! List) throw const FormatException('Invalid project list.');
    // Parse all snapshots before replacing the version map.
    final oldVersions = Map<String, int>.of(_versions);
    _versions.clear();
    try {
      return result.map(_snapshot).toList(growable: false);
    } catch (_) {
      _versions
        ..clear()
        ..addAll(oldVersions);
      rethrow;
    }
  }

  @override
  Future<Project> createProject({
    required String title,
    required String clientName,
    String category = 'Creative',
  }) async {
    final owner = _account();
    final key = jsonEncode([title, clientName, category]);
    final requestId = _pendingCreates.putIfAbsent(key, newRequestId);
    final result = await transport.rpc('recall_create_project', {
      'p_title': title,
      'p_client_name': clientName,
      'p_category': category,
      'p_request_id': requestId,
    });
    _checkAccount(owner);
    final project = _snapshot(result);
    _pendingCreates.remove(key);
    return project;
  }

  @override
  Future<Project?> mutateProject({
    required String projectId,
    required String action,
    Map<String, dynamic> payload = const {},
  }) async {
    final owner = _account();
    final version = _versions[projectId];
    if (version == null) {
      throw const CloudException('Refresh this project before changing it.');
    }
    // Keep an uncertain operation's key for an identical retry. A successful
    // response or a different operation gets a fresh key.
    final key = jsonEncode([projectId, version, action, payload]);
    final requestId = _pendingRequests.putIfAbsent(key, newRequestId);
    final result = await transport.rpc('recall_mutate_project', {
      'p_project_id': projectId,
      'p_expected_version': version,
      'p_action': action,
      'p_payload': payload,
      'p_request_id': requestId,
    });
    _checkAccount(owner);
    final response = cloudMap(result);
    _pendingRequests.remove(key);
    if (response['project'] == null && action == 'delete') {
      _versions.remove(projectId);
      return null;
    }
    final project = _snapshot(response);
    if (project.id != projectId) {
      _versions.remove(project.id);
      throw const FormatException('The server returned a different project.');
    }
    return project;
  }
}

class RpcCloudReviewGateway implements CloudReviewGateway {
  RpcCloudReviewGateway({required this.transport});
  final CloudRpcTransport transport;
  final Map<String, String> _pendingResponses = {};
  @override
  Future<ReviewLink> createLink({
    required String projectId,
    required String revisionId,
    required String participantId,
    List<String>? itemIds,
    int ttlSeconds = 604800,
  }) async => ReviewLink.fromJson(
    cloudMap(
      await transport.rpc('recall_create_review_link', {
        'p_project_id': projectId,
        'p_revision_id': revisionId,
        'p_participant_id': participantId,
        'p_item_ids': ?itemIds,
        'p_ttl_seconds': ttlSeconds,
      }),
    ),
  );

  @override
  Future<List<ReviewLink>> listLinks(String projectId) async {
    final result = await transport.rpc('recall_list_review_links', {
      'p_project_id': projectId,
    });
    return (result as List)
        .map((item) => ReviewLink.fromJson(cloudMap(item)))
        .toList(growable: false);
  }

  @override
  Future<void> revokeLink(String linkId) async {
    await transport.rpc('recall_revoke_review_link', {'p_link_id': linkId});
  }

  @override
  Future<PublicReview> fetchReview(String token) async => PublicReview.fromJson(
    cloudMap(await transport.rpc('recall_review_link', {'p_token': token})),
  );
  @override
  Future<ReviewReceipt> respond({
    required String token,
    required String action,
    String note = '',
  }) async {
    if (!['confirm', 'correction', 'decline'].contains(action)) {
      throw const CloudException('Choose a valid response.');
    }
    if (note.trim().length > 2000) {
      throw const CloudException('Keep your response within 2,000 characters.');
    }
    if (action == 'correction' && note.trim().isEmpty) {
      throw const CloudException('Describe the correction you need.');
    }
    final key = '$token:$action:$note';
    final request = _pendingResponses.putIfAbsent(key, newRequestId);
    final response = ReviewReceipt.fromJson(
      cloudMap(
        await transport.rpc('recall_respond_review', {
          'p_token': token,
          'p_action': action,
          'p_note': note.trim(),
          'p_request_id': request,
        }),
      ),
    );
    _pendingResponses.remove(key);
    return response;
  }
}
