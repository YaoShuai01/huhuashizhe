import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/cloud_models.dart';
import '../services/cloud_farm_controller.dart';
import '../widgets/cloud_widgets.dart';

class CloudAssistantTab extends ConsumerStatefulWidget {
  const CloudAssistantTab({super.key});

  @override
  ConsumerState<CloudAssistantTab> createState() => _CloudAssistantTabState();
}

class _CloudAssistantTabState extends ConsumerState<CloudAssistantTab> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;

  static const _quick = [
    '今天要浇水吗？',
    '什么时候施肥？',
    '作物长到哪个阶段？',
    '本地适合种什么？',
    '怎么异地查看田块？',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cloudFarmProvider).ensureAssistantGreeting();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send([String? preset]) {
    final text = preset ?? _input.text;
    if (text.trim().isEmpty) return;
    ref.read(cloudFarmProvider).sendChat(text);
    _input.clear();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(cloudFarmProvider);
    final messages = c.chat;
    if (messages.length != _lastCount) {
      _lastCount = messages.length;
      _scrollToBottom();
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: '返回 App 首页',
          onPressed: () => context.go('/home'),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text('AI 农事助手'),
            SizedBox(height: 2),
            Text('已接入天气 · 墒情 · 田块数据',
                style: TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.auto_awesome, size: 18),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final m = messages[index];
                return _Bubble(message: m);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: cloudCardColor(context),
              border: Border(
                top: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
              ),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 30,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _quick.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) => ActionChip(
                      label: Text(_quick[index],
                          style: const TextStyle(fontSize: 10.5)),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _send(_quick[index]),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: '问一个农事问题…',
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 42,
                      height: 42,
                      child: FilledButton(
                        onPressed: _send,
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(42, 42),
                          shape: const CircleBorder(),
                        ),
                        child: const Icon(Icons.arrow_upward, size: 19),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final CloudChatMessage message;

  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final mine = message.isMe;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: cloudSoft(primary, context),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.auto_awesome, size: 15, color: primary),
            ),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: mine ? primary : cloudCardColor(context),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(13),
                  topRight: const Radius.circular(13),
                  bottomLeft: Radius.circular(mine ? 13 : 3),
                  bottomRight: Radius.circular(mine ? 3 : 13),
                ),
                border: mine
                    ? null
                    : Border.all(
                        color: Theme.of(context).dividerColor.withValues(alpha: 0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.55,
                      color: mine ? Colors.white : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${message.t.hour.toString().padLeft(2, '0')}:'
                    '${message.t.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 9,
                      color: mine
                          ? Colors.white70
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (mine) ...[
            const SizedBox(width: 7),
            CircleAvatar(
              radius: 14,
              backgroundColor: cloudSoft(primary, context),
              child: Icon(Icons.person, size: 15, color: primary),
            ),
          ],
        ],
      ),
    );
  }
}
