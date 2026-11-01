import 'package:flutter/material.dart';
import 'package:poemath/features/profile/llm_provider_settings_page.dart';

/// 生图供应商与普通供应商共用列表及编辑弹窗，配置和凭据分别保存。
class ImageGenerationSettingsPage extends StatelessWidget {
  const ImageGenerationSettingsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const LlmProviderSettingsPage(imageGeneration: true);
}
