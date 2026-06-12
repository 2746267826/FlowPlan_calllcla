import 'package:flowplanv2/features/ai_chat/presentation/ai_chat_page.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:visibility_detector/visibility_detector.dart';

import '../test_support/user_workflow_harness.dart';

void main() {
  setUpAll(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  tearDown(() {
    VisibilityDetectorController.instance.notifyNow();
  });

  testWidgets('AI chat page starts with fake API and renders chat composer', (
    tester,
  ) async {
    final fakeAiApi = FakeAiApi();

    await _pumpAiChatPage(tester, fakeAiApi: fakeAiApi);
    await _pumpChatReady(tester);

    expect(find.byType(AiChatPage), findsOneWidget);
    expect(find.byType(Chat), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(fakeAiApi.createConversationRequest, isNotNull);
    expect(fakeAiApi.createConversationRequest?['title'], contains('AI'));
    expect(
      fakeAiApi.createConversationRequest,
      containsPair('source', 'flowplanv2_client'),
    );
    expect(
      fakeAiApi.createConversationRequest,
      containsPair('contextScope', <String, Object?>{}),
    );
  });

  testWidgets('AI chat sends from composer button and renders the reply', (
    tester,
  ) async {
    final fakeAiApi = FakeAiApi(replyContent: 'Use a 90 minute focus block.');

    await _pumpAiChatPage(tester, fakeAiApi: fakeAiApi);
    await _pumpChatReady(tester);

    await _sendChatText(tester, '  Plan my day  ');
    await _pumpFrames(tester);

    expect(fakeAiApi.sentMessages, hasLength(1));
    expect(fakeAiApi.sentMessages.single['conversationId'], 'conversation-1');
    expect(fakeAiApi.sentMessages.single['content'], 'Plan my day');
    expect(fakeAiApi.sentMessages.single['source'], 'flowplanv2');
    expect(fakeAiApi.sentMessages.single['contextScope'], <String, Object?>{});
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text, '');
    expect(
      _chatTextMessages(tester).map((message) => message.text),
      containsAll(<String>['Plan my day', 'Use a 90 minute focus block.']),
    );
  });

  testWidgets('AI chat send button follows composer text state', (
    tester,
  ) async {
    final fakeAiApi = FakeAiApi();

    await _pumpAiChatPage(tester, fakeAiApi: fakeAiApi);
    await _pumpChatReady(tester);

    expect(find.byType(SendButton), findsNothing);

    await tester.enterText(find.byType(TextField), 'Focus plan');
    await tester.pump();
    expect(find.byType(SendButton), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.byType(SendButton), findsNothing);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(find.byType(SendButton), findsNothing);
    expect(fakeAiApi.sentMessages, isEmpty);
  });

  testWidgets('AI chat ignores blank messages', (tester) async {
    final fakeAiApi = FakeAiApi();

    await _pumpAiChatPage(tester, fakeAiApi: fakeAiApi);
    await _pumpChatReady(tester);

    await _sendChatText(tester, '   ', expectSendButton: false);
    await _pumpFrames(tester);

    expect(fakeAiApi.sentMessages, isEmpty);
    expect(_chatTextMessages(tester), isEmpty);
  });

  testWidgets('AI chat renders composer when AI provider is unavailable', (
    tester,
  ) async {
    await _pumpAiChatPage(
      tester,
      overrides: [
        aiApiProvider.overrideWith((ref) async {
          throw StateError('missing AI provider');
        }),
      ],
    );
    await _pumpFrames(tester, 8);

    expect(find.byType(Chat), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'AI chat records system error when provider is unavailable on send',
      (tester) async {
    await _pumpAiChatPage(
      tester,
      overrides: [
        aiApiProvider.overrideWith((ref) async {
          throw StateError('missing AI provider');
        }),
      ],
    );
    await _pumpChatReady(tester);

    await _sendChatText(tester, 'Can you still help?');
    await _pumpFrames(tester);

    final messages = _chatTextMessages(tester);
    expect(
      messages,
      contains(
        isA<types.TextMessage>()
            .having((message) => message.author.id, 'author.id', 'self')
            .having((message) => message.text, 'text', 'Can you still help?'),
      ),
    );
    expect(
      messages,
      contains(
        isA<types.TextMessage>()
            .having((message) => message.author.id, 'author.id', 'system')
            .having((message) => message.text, 'text',
                contains('missing AI provider')),
      ),
    );
  });

  testWidgets('AI chat can still send when conversation creation fails', (
    tester,
  ) async {
    final fakeAiApi = _CreateConversationFailsAiApi(
      replyContent: 'Temporary chat still works.',
    );

    await _pumpAiChatPage(tester, fakeAiApi: fakeAiApi);
    await _pumpChatReady(tester);

    await _sendChatText(tester, 'Use a temporary thread');
    await _pumpFrames(tester);

    expect(fakeAiApi.createConversationAttempts, 1);
    expect(fakeAiApi.sentMessages, hasLength(1));
    expect(fakeAiApi.sentMessages.single['conversationId'], isNull);
    expect(
      _chatTextMessages(tester).map((message) => message.text),
      containsAll(<String>[
        'Use a temporary thread',
        'Temporary chat still works.',
      ]),
    );
  });

  testWidgets('AI chat shows a system failure message when send fails', (
    tester,
  ) async {
    final fakeAiApi = FakeAiApi(sendMessageError: StateError('offline'));

    await _pumpAiChatPage(tester, fakeAiApi: fakeAiApi);
    await _pumpChatReady(tester);

    await _sendChatText(tester, 'Need help');
    await _pumpFrames(tester);

    expect(fakeAiApi.sentMessages.single['content'], 'Need help');
    expect(
      _chatTextMessages(tester),
      contains(
        isA<types.TextMessage>()
            .having((message) => message.author.id, 'author.id', 'system')
            .having((message) => message.text, 'text', isNotEmpty),
      ),
    );
  });

  testWidgets('AI chat keeps multi-turn history with newest messages first', (
    tester,
  ) async {
    final fakeAiApi = _EchoTurnAiApi();

    await _pumpAiChatPage(tester, fakeAiApi: fakeAiApi);
    await _pumpChatReady(tester);

    await _sendChatText(tester, 'First prompt');
    await _pumpFrames(tester);
    await _sendChatText(tester, 'Second prompt');
    await _pumpFrames(tester);

    expect(fakeAiApi.sentMessages, hasLength(2));
    expect(
      _chatTextMessages(tester).map((message) => message.text).toList(),
      <String>[
        'Reply 2 to Second prompt',
        'Second prompt',
        'Reply 1 to First prompt',
        'First prompt',
      ],
    );
  });

  testWidgets('AI chat clear action removes all visible messages', (
    tester,
  ) async {
    final fakeAiApi = FakeAiApi(replyContent: 'Draft a plan.');

    await _pumpAiChatPage(tester, fakeAiApi: fakeAiApi);
    await _pumpChatReady(tester);

    await _sendChatText(tester, 'Need a plan');
    await _pumpFrames(tester);
    expect(_chatTextMessages(tester), hasLength(2));

    await tester.tap(find.byKey(AppKeys.aiChatClearButton));
    await _pumpFrames(tester);

    expect(_chatTextMessages(tester), isEmpty);
    expect(find.byType(Chat), findsOneWidget);
    expect(fakeAiApi.sentMessages, hasLength(1));
  });
}

Future<void> _pumpAiChatPage(
  WidgetTester tester, {
  FakeAiApi? fakeAiApi,
  List<Override>? overrides,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides ??
          [
            aiApiProvider.overrideWith((ref) async => fakeAiApi ?? FakeAiApi()),
          ],
      child: const MaterialApp(home: AiChatPage()),
    ),
  );
  await tester.pump();
}

Future<void> _pumpChatReady(WidgetTester tester) async {
  await pumpUntilFound(tester, find.byType(Chat), maxPumps: 20);
  await _pumpFrames(tester);
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 4]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _sendChatText(
  WidgetTester tester,
  String text, {
  bool expectSendButton = true,
}) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();

  if (!expectSendButton) {
    expect(find.byType(SendButton), findsNothing);
    return;
  }

  expect(find.byType(SendButton), findsOneWidget);
  await tester.tap(find.byType(SendButton));
  await tester.pump();
}

List<types.TextMessage> _chatTextMessages(WidgetTester tester) {
  return tester
      .widget<Chat>(find.byType(Chat))
      .messages
      .whereType<types.TextMessage>()
      .toList();
}

class _CreateConversationFailsAiApi extends FakeAiApi {
  _CreateConversationFailsAiApi({required super.replyContent});

  int createConversationAttempts = 0;

  @override
  Future<Map<String, dynamic>> createConversation({
    String title = 'AI chat',
    String source = 'flowplanv2',
    String? providerKey,
    String? model,
    Map<String, Object?> contextScope = const <String, Object?>{},
  }) async {
    createConversationAttempts++;
    throw StateError('conversation bootstrap failed');
  }
}

class _EchoTurnAiApi extends FakeAiApi {
  @override
  Future<Map<String, dynamic>> sendMessage({
    String? conversationId,
    required String content,
    String source = 'flowplanv2',
    String? providerKey,
    String? model,
    String? title,
    Map<String, Object?> contextScope = const <String, Object?>{},
  }) async {
    sentMessages.add(<String, Object?>{
      'conversationId': conversationId,
      'content': content,
      'source': source,
      'providerKey': providerKey,
      'model': model,
      'title': title,
      'contextScope': contextScope,
    });
    return <String, dynamic>{
      'message': <String, dynamic>{
        'id': 'message-${sentMessages.length}',
        'content': 'Reply ${sentMessages.length} to $content',
      },
    };
  }
}
