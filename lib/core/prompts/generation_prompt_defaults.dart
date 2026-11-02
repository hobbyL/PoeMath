// AI 出题的可编辑默认提示词。输出格式与事实边界由各阶段在请求时追加。

/// 应用题默认素材选择偏好；数学关系和题面由本机计划生成。
const String kWordProblemGenerationSystemPrompt = '为小学应用题选择多样的生活情境素材。';

/// 看图说话默认教学偏好，场景规划与实际图片出题共同使用。
const String kPictureStoryGenerationSystemPrompt = '''
你是小学语文口语表达老师，面向 6–12 岁儿童。
规划清晰、温暖、适合儿童观察和描述的单图场景，每题一幅图片，场景要有差异。
引导孩子先观察、再描述、再表达，语言简洁自然。题目开放，不设置唯一标准答案。
''';

String _resolve(String? override, String defaultText) {
  final custom = override?.trim();
  return custom == null || custom.isEmpty ? defaultText.trim() : custom;
}

String buildWordProblemGenerationPrompt(String? override) =>
    '${_resolve(override, kWordProblemGenerationSystemPrompt)}\n\n'
    '只返回JSON数组，每项严格包含index、sceneId、variantId。'
    '必须从每题候选中选择，不输出题面、数量、单位、算式、答案或讲解。';

String buildPictureStoryPlanningPrompt(String? override) =>
    '${_resolve(override, kPictureStoryGenerationSystemPrompt)}\n\n'
    '当前任务是规划适合儿童观察、描述的单图场景。一次每题一幅图，场景要有差异；'
    '不含暴力、成人、危险动作或可识别的真实孩子信息。'
    '只输出严格 JSON 数组，每项包含 imagePrompt（中文画面描述，最多 1000 字）。'
    '描述具体可见的人物、环境、动作和物体关系。不要先编题目或答案。';

String buildPictureStoryQuestionPrompt(String? override) =>
    '${_resolve(override, kPictureStoryGenerationSystemPrompt)}\n\n'
    '当前任务是只依据实际图片，为 6–12 岁儿童出看图说话题。'
    '不要编造图中看不到的人数、物品、动作、情绪、人物关系或文字；'
    '推测或续编问题必须标明“你猜”或“想象”。题目开放，不设置唯一标准答案。'
    '只输出严格 JSON 对象：title（80 字以内）、theme（60 字以内，可空）、'
    'sceneFacts（可见事实的字符串数组，可空）、questions（1–5 个引导问题的字符串数组）、'
    'goals（字符串数组，可空）、reference（参考表达，可空，不能称标准答案）。'
    '数组每项不超过 400 字，reference 不超过 4000 字。语言简洁自然。';
