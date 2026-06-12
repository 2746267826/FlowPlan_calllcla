import 'dart:convert';

import 'package:flowplanv2/core/server_api/ai_api.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  test('AI API forwards settings, conversation, message, and draft commands',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final requests = <_CapturedRequest>[];
    final api = AiApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          requests.add(_CapturedRequest.from(request));
          return http.Response('{"ok":true}', 200);
        }),
      ),
    );

    await api.settings();
    await api.upsertProvider(
      providerKey: 'openai main',
      displayName: 'OpenAI Main',
      baseUrl: 'https://api.example.test/v1',
      model: 'gpt-test',
      apiKey: 'secret',
      options: const <String, Object?>{'timeout': 30},
    );
    await api.testProvider('openai main');
    await api.context();
    await api.conversations(status: 'open', limit: 7, offset: 3);
    await api.conversations();
    await api.createConversation(
      title: 'Planning',
      source: 'web',
      providerKey: 'openai',
      model: 'gpt-test',
      contextScope: const <String, Object?>{'taskId': 42},
    );
    await api.messages('conversation 1');
    await api.sendMessage(
      conversationId: 'conversation 1',
      content: 'Hello',
      providerKey: 'openai',
      model: 'gpt-test',
      title: 'Greeting',
      contextScope: const <String, Object?>{'calendar': true},
    );
    await api.toolDrafts(status: 'pending', limit: 8, offset: 2);
    await api.toolDrafts();
    await api.reviewDraft(
      draftId: 'draft 1',
      status: 'rejected',
      reviewNote: 'No thanks',
    );
    await api.confirmDraft(draftId: 'draft 1', reviewNote: 'Run it');

    expect(
      requests.map((request) => '${request.method} ${request.path}').toList(),
      <String>[
        'GET /api/ai/settings',
        'PATCH /api/ai/settings/openai%20main',
        'POST /api/ai/settings/openai%20main/test',
        'GET /api/ai/context',
        'GET /api/ai/conversations',
        'GET /api/ai/conversations',
        'POST /api/ai/conversations',
        'GET /api/ai/conversations/conversation%201/messages',
        'POST /api/ai/messages',
        'GET /api/ai/tool-drafts',
        'GET /api/ai/tool-drafts',
        'PATCH /api/ai/tool-drafts/draft%201',
        'POST /api/ai/tool-drafts/draft%201/confirm',
      ],
    );
    expect(requests[4].query, <String, String>{
      'status': 'open',
      'limit': '7',
      'offset': '3',
    });
    expect(requests[5].query, <String, String>{
      'limit': '50',
      'offset': '0',
    });
    expect(requests[1].jsonBody,
        containsPair('providerType', 'openai_compatible'));
    expect(requests[1].jsonBody, containsPair('temperature', 0.2));
    expect(requests[1].jsonBody['options'], <String, Object?>{'timeout': 30});
    expect(requests[6].jsonBody, <String, Object?>{
      'title': 'Planning',
      'source': 'web',
      'providerKey': 'openai',
      'model': 'gpt-test',
      'contextScope': <String, Object?>{'taskId': 42},
    });
    expect(requests[8].jsonBody, <String, Object?>{
      'conversationId': 'conversation 1',
      'content': 'Hello',
      'source': 'flowplanv2',
      'providerKey': 'openai',
      'model': 'gpt-test',
      'title': 'Greeting',
      'contextScope': <String, Object?>{'calendar': true},
    });
    expect(requests[9].query, <String, String>{
      'status': 'pending',
      'limit': '8',
      'offset': '2',
    });
    expect(requests[11].jsonBody, <String, Object?>{
      'status': 'rejected',
      'reviewNote': 'No thanks',
    });
    expect(requests[12].jsonBody, <String, Object?>{
      'reviewNote': 'Run it',
    });
  });
}

class _CapturedRequest {
  _CapturedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.jsonBody,
  });

  factory _CapturedRequest.from(http.Request request) {
    return _CapturedRequest(
      method: request.method,
      path: request.url.path,
      query: request.url.queryParameters,
      jsonBody: request.body.isEmpty
          ? const <String, Object?>{}
          : Map<String, Object?>.from(
              jsonDecode(request.body) as Map<String, dynamic>,
            ),
    );
  }

  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, Object?> jsonBody;
}
