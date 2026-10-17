import 'package:flutter/material.dart';
import 'package:poemath/core/services/cloud_usage_service.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';

class ParentProtectionPage extends StatefulWidget {
  const ParentProtectionPage({super.key});
  @override
  State<ParentProtectionPage> createState() => _ParentProtectionPageState();
}

class _ParentProtectionPageState extends State<ParentProtectionPage> {
  final _pin = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;
  ParentAccessService get _access => ParentAccessService.instance;
  Future<void> _configure() async {
    if (_busy) return;
    setState(() => _busy = true);
    if (!await ensureParentAccess(context) || !mounted) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (_pin.text != _confirmation.text ||
        !ParentAccessService.validPin(_pin.text)) {
      setState(() {
        _error = '请输入两次相同的 6 位数字 PIN';
        _busy = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final recovery = await _access.configure(_pin.text);
      if (!mounted) return;
      _pin.clear();
      _confirmation.clear();
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => AlertDialog(
          title: const Text('保存一次性恢复码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('请抄写并放在孩子无法取得的地方。只显示这一次，忘记 PIN 时可用它关闭保护。'),
              const SizedBox(height: SpacingTokens.md),
              SelectableText(recovery),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('我已保存'),
            ),
          ],
        ),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeLimit(CloudUsageKind kind) async {
    if (!await ensureParentAccess(context) || !mounted) return;
    final usage = CloudUsageService.instance;
    final input =
        TextEditingController(text: usage.limit(kind)?.toString() ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('${kind.label}每日请求额度'),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '0–100000，留空表示不限',
            helperText: '0 表示暂停此类云请求',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, input.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // 路由退出动画结束后再释放输入控制器。
    WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
    if (value != null && mounted) {
      try {
        _access.assertAllowed();
        final parsed = value.isEmpty ? null : int.tryParse(value);
        if (value.isNotEmpty && parsed == null) {
          throw const FormatException('请输入有效整数');
        }
        await usage.setLimit(kind, parsed);
      } on Object catch (error) {
        if (mounted) setState(() => _error = '$error');
      }
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usage = CloudUsageService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('家长保护与云额度')),
      body: ListView(
        padding: const EdgeInsets.all(SpacingTokens.md),
        children: [
          ColoredCard(
            color: theme.colorScheme.primary,
            child: Text(
              _access.enabled
                  ? '保护已开启。解锁有效 2 分钟，离开应用立即失效。PIN 与恢复码不会随备份迁移。'
                  : '保护默认关闭。开启后，设置、服务配置、覆盖恢复和应用题最终入库需要家长解锁。',
            ),
          ),
          if (_access.needsResetNotice)
            const Padding(
              padding: EdgeInsets.all(SpacingTokens.sm),
              child: Text('原设备的家长验证未迁移，此设备的保护已重设，请重新设置 PIN。'),
            ),
          const SizedBox(height: SpacingTokens.md),
          TextField(
            controller: _pin,
            enabled: !_busy,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '新的 6 位数字 PIN'),
          ),
          TextField(
            controller: _confirmation,
            enabled: !_busy,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '再次输入 PIN'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: SpacingTokens.md),
          FilledButton(
            onPressed: _busy ? null : _configure,
            child: Text(_access.enabled ? '更新 PIN 与恢复码' : '开启保护'),
          ),
          if (_access.enabled)
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (!await ensureParentAccess(context)) return;
                      try {
                        await _access.disable();
                      } on Object catch (error) {
                        if (mounted) setState(() => _error = '$error');
                      }
                      if (mounted) setState(() {});
                    },
              child: const Text('关闭保护'),
            ),
          const SizedBox(height: SpacingTokens.lg),
          Text(
            '今日云请求用量（${usage.dayKey}）',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: SpacingTokens.sm),
          for (final kind in CloudUsageKind.values) ...[
            if (kind != CloudUsageKind.values.first)
              const SizedBox(height: SpacingTokens.sm),
            AppTile(
              icon: _usageIcon(kind),
              iconColor: theme.colorScheme.primary,
              title: kind.label,
              subtitle:
                  '已用 ${usage.used(kind)} 次 · ${usage.limit(kind) == null ? '不限' : '每日上限 ${usage.limit(kind)} 次'}',
              onTap: () => _changeLimit(kind),
            ),
          ],
          const SizedBox(height: SpacingTokens.md),
          const Text('默认每天 AI 30 次、语音识别 60 次、云朗读 120 次。可按需调整、暂停或设为不限。'),
          const SizedBox(height: SpacingTokens.sm),
          const Text(
            '额度按本设备当天实际发送的请求计数，跨重启保留，不随备份重置。失败、验证与重试也计数；AI 一次操作可能有多次请求，云朗读按新合成的段落计数，缓存和本地朗读不计。模型/音色目录读取不计。额度不是精确费用账单，请同时设置供应商账户预算。',
          ),
        ],
      ),
    );
  }

  /// 三类云用量各自的图标。
  ///
  /// 原实现三张卡都用 `Icons.cloud_outlined`，一行看下来毫无辨识度，
  /// 用户得读文字才知道哪张是哪类。按「做什么」区分：
  /// - AI：机器人（与全 app 助手/出题的图标一致）
  /// - 语音识别：麦克风（听用户说）—— 注意不要与 TTS 共用
  ///   `record_voice_over`，否则两张卡又长得一样
  /// - 云朗读：人物说话（读给用户听，沿用 TTS 设置页的既有图标）
  static IconData _usageIcon(CloudUsageKind kind) => switch (kind) {
        CloudUsageKind.llm => Icons.smart_toy_outlined,
        CloudUsageKind.asr => Icons.mic_none_rounded,
        CloudUsageKind.tts => Icons.record_voice_over_outlined,
      };
}
