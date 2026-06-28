import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/ai_chat_provider.dart';
import '../../../providers/weather_provider.dart';
import '../../../services/ai_chat_service.dart';
import '../../../services/weather_service.dart';

class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _hasAutoScrolled = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (immediate) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        } else {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiChatProvider);

    // 历史记录加载完成后自动滚动到底部
    if (!_hasAutoScrolled && state.messages.isNotEmpty) {
      _hasAutoScrolled = true;
      _scrollToBottom(immediate: true);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI助手'),
        actions: [
          if (state.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空对话',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('清空对话'),
                    content: const Text('确定要清空所有对话记录吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () {
                          ref.read(aiChatProvider.notifier).clearHistory();
                          Navigator.pop(ctx);
                        },
                        child: const Text('确定', style: TextStyle(color: AppColors.error)),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: state.messages.isEmpty
                ? _buildWelcome()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: state.messages.length + (state.isLoading ? 0 : 0),
                    itemBuilder: (context, index) {
                      final msg = state.messages[index];
                      return _buildMessageBubble(msg, index);
                    },
                  ),
          ),
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('AI思考中...', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
                ],
              ),
            ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.auto_awesome, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text(
              'AI助手',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              '我是护花使者的智能助手，可以帮你：\n诊断病虫害、推荐农药方案、规划飞行参数',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.6),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildQuickQuestion('水稻叶片发黄怎么办？'),
                _buildQuickQuestion('小麦赤霉病用什么药？'),
                _buildQuickQuestion('飞行高度多少合适？'),
                _buildQuickQuestion('农药混用注意事项'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickQuestion(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 13)),
      backgroundColor: AppColors.surfaceVariant,
      onPressed: () {
        _controller.text = text;
        _submit();
      },
    );
  }

  Widget _buildMessageBubble(AiChatMessage msg, int index) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: msg.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制到剪贴板'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                    width: 160,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
                    bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
                  ),
                  border: isUser ? null : Border.all(color: AppColors.surfaceVariant),
                ),
                child: Column(
                  crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (!isUser)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome, size: 14, color: AppColors.accent),
                            SizedBox(width: 4),
                            Text('AI助手', style: TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    SelectableText(
                      msg.content,
                      style: TextStyle(
                        fontSize: 15,
                        color: isUser ? Colors.white : AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 操作按钮行
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4, right: 4, bottom: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _actionButton(Icons.copy, '复制', () {
                    Clipboard.setData(ClipboardData(text: msg.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制到剪贴板'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                        width: 160,
                      ),
                    );
                  }),
                  if (!isUser) ...[
                    const SizedBox(width: 4),
                    _actionButton(Icons.refresh, '重新回答', () {
                      final state = ref.read(aiChatProvider);
                      if (state.messages.length >= 2 && index > 0) {
                        final prevMsg = state.messages[index - 1];
                        if (prevMsg.role == 'user') {
                          final weather = ref.read(weatherProvider).valueOrNull;
                          ref.read(aiChatProvider.notifier).removeLastAndRetry(weather: weather);
                        }
                      }
                    }),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String tooltip, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Icon(icon, size: 14, color: AppColors.textHint),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: '输入你的问题...',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final weather = ref.read(weatherProvider).valueOrNull;
    ref.read(aiChatProvider.notifier).sendMessage(text, weather: weather);
    _scrollToBottom();
  }
}