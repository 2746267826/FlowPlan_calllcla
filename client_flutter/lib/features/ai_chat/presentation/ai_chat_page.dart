import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../../core/server_api/ai_api.dart';
import '../../../shared/providers/app_providers.dart';

class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final List<types.Message> _messages = [];
  types.User _user = const types.User(id: 'self');
  String? _conversationId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _startConversation();
  }

  Future<void> _startConversation() async {
    final aiApi = await ref.read(aiApiProvider.future);
    try {
      final result = await aiApi.createConversation(
        title: 'AI 对话',
        source: 'flowplanv2_client',
      );
      final conv = result['conversation'] as Map<String, dynamic>?;
      if (conv != null) {
        _conversationId = conv['id'] as String?;
      }
    } catch (_) {
      // Conversation creation may fail if AI provider not configured.
    }
    setState(() => _loading = false);
  }

  Future<void> _handleSendPressed(types.PartialText message) async {
    final text = message.text.trim();
    if (text.isEmpty) return;

    final userMsg = types.TextMessage(
      author: _user,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
    );

    setState(() => _messages.insert(0, userMsg));

    try {
      final aiApi = await ref.read(aiApiProvider.future);
      final result = await aiApi.sendMessage(
        content: text,
        conversationId: _conversationId,
      );

      final reply = result['message'] as Map<String, dynamic>?;
      final content = reply?['content'] as String?;

      if (content != null && content.isNotEmpty) {
        final aiMsg = types.TextMessage(
          author: const types.User(id: 'ai', firstName: 'AI'),
          createdAt: DateTime.now().millisecondsSinceEpoch,
          id: 'ai-${DateTime.now().millisecondsSinceEpoch}',
          text: content,
        );
        setState(() => _messages.insert(0, aiMsg));
      }
    } catch (e) {
      final errorMsg = types.TextMessage(
        author: const types.User(id: 'system', firstName: 'System'),
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: 'err-${DateTime.now().millisecondsSinceEpoch}',
        text: '错误：${e.toString()}',
      );
      setState(() => _messages.insert(0, errorMsg));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Use markdown widget to render AI replies with rich formatting
    final defaultBubbleBuilder = Chat(
      messages: [],
      onSendPressed: (_) {},
      user: _user,
    ).bubbleBuilder;

    return Scaffold(
      appBar: AppBar(title: const Text('AI 对话')),
      body: Chat(
        messages: _messages,
        onSendPressed: _handleSendPressed,
        user: _user,
        showUserAvatars: true,
        showUserNames: true,
        bubbleBuilder: (
          child, {
          required types.Message message,
          required bool nextMessageInGroup,
        }) {
          if (message.author.id != _user.id &&
              message is types.TextMessage) {
            return Container(
              constraints: const BoxConstraints(maxWidth: 300),
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: MarkdownWidget(data: message.text),
            );
          }
          return child;
        },
      ),
    );
  }
}
