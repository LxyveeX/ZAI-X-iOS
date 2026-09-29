import 'package:flutter/material.dart';
import 'package:zai_x/app/i18n.dart';

/// 关于页的作者名：连续点击十次后要求输入指令，指令正确才调用 [onUnlock]。
///
/// 指令错误、留空或取消时什么都不做，也不显示任何提示；
/// 想再试一次得重新点满十次。
class AuthorUnlock extends StatefulWidget {
  const AuthorUnlock({super.key, required this.onUnlock});
  final Future<void> Function() onUnlock;

  /// 忽略大小写与前后空白：手机键盘可能自动大写开头或补上空格
  static bool accepts(String? input) =>
      input != null && input.trim().toLowerCase() == 'hitomi';

  @override
  State<AuthorUnlock> createState() => _AuthorUnlockState();
}

class _AuthorUnlockState extends State<AuthorUnlock> {
  int taps = 0;
  DateTime? lastTap;
  bool busy = false;

  Future<void> onTap() async {
    if (busy) return;
    final now = DateTime.now();
    if (lastTap == null || now.difference(lastTap!).inSeconds >= 3) {
      taps = 0;
    }
    lastTap = now;
    if (++taps != 10) return;
    taps = 0;
    busy = true;
    try {
      final input = await showDialog<String>(
        context: context,
        builder: (_) => const _CommandPrompt(),
      );
      if (!mounted || !AuthorUnlock.accepts(input)) return;
      await widget.onUnlock();
    } finally {
      busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('funkeyyou')),
      );
}

/// 只有一个输入框，不写用途也不给提示；
/// 键盘不自动更正、不显示建议，也不记住输入过的内容。
class _CommandPrompt extends StatefulWidget {
  const _CommandPrompt();

  @override
  State<_CommandPrompt> createState() => _CommandPromptState();
}

class _CommandPromptState extends State<_CommandPrompt> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() => Navigator.of(context).pop(controller.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: '指令'.i18n),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消'.i18n),
          ),
          TextButton(onPressed: submit, child: Text('确定'.i18n)),
        ],
      );
}
