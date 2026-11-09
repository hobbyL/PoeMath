// AI 出题的可编辑默认提示词。输出格式与事实边界由各阶段在请求时追加。

/// 应用题默认素材选择偏好；数学关系和题面由本机计划生成。
const String kWordProblemGenerationSystemPrompt = '为小学应用题选择多样的生活情境素材。';

/// 生图提示词为场景描述和固定单图约束预留请求空间。
const int kPictureStoryImagePromptMaxLength = 2800;
const int kPictureStoryQuestionPromptMaxLength = 2000;
const int kPictureStorySceneDescriptionMaxLength = 1000;

/// 看图说话题图的可编辑要求，同时用于场景规划和实际生图。
const String kPictureStoryImageGenerationSystemPrompt = '''
为 6–12 岁儿童的看图说话练习设计小学语文课本式插图。
采用小学语文课本式看图说话，一幅图讲一件事，围绕一件儿童熟悉的日常小事，选择事情正在发生的一个关键时刻。
通常安排 2–4 名主要人物，明确谁在哪里、正在做什么、与谁或什么物体互动。写清动作、手势、视线、表情和关键物品的状态。
用画面内的可见线索体现事件的起因或结果，让孩子能据图讲述一件事，不依赖看不见的过去、未来、内心活动或文字说明。
画风采用平面手绘儿童教材插图，轮廓清晰，色彩柔和明快，人物比例自然，表情和手势清楚。
主要人物和关键物品占据画面主体，完整可见，交互的手部、视线方向和关键道具清楚，背景简洁，只保留交代地点和情节的环境。
突出动作、互动和事件线索，避免人物排排站、看向镜头摆拍、只有风景或装饰，不使用照片、电影海报或夸张的 3D 渲染风格。
各题在事件、人物动作和地点上有差异，不能仅换颜色或装饰。
''';

/// 只依据实际图片设计看图说话内容，与生图要求独立编辑。
const String kPictureStoryQuestionGenerationSystemPrompt = '''
你是小学语文口语表达老师，面向 6–12 岁儿童。
只根据收到的实际图片设计看图说话练习。引导孩子说清谁在哪里做什么，再关注动作、互动和事件线索。
引导孩子先观察、再描述、再表达，语言简洁自然。题目开放，不设置唯一标准答案。
观察提示只陈述画面中可见的事实，不编造看不到的人数、物品、动作、情绪、人物关系或文字。
推测或续编问题明确使用“你猜”或“想象”，与画面事实区分。参考表达用于帮助家长引导，不称为标准答案。
''';

/// 旧教学偏好继续保留，同时补齐原有生图画风和构图要求。
String legacyPictureStoryImagePrompt(String teachingPreference) =>
    '${kPictureStoryImageGenerationSystemPrompt.trim()}\n\n'
    '补充教学要求：\n${teachingPreference.trim()}';

String _resolve(String? override, String defaultText) {
  final custom = override?.trim();
  return custom == null || custom.isEmpty ? defaultText.trim() : custom;
}

String buildWordProblemGenerationPrompt(String? override) =>
    '${_resolve(override, kWordProblemGenerationSystemPrompt)}\n\n'
    '只返回JSON数组，每项严格包含index、sceneId、variantId。'
    '必须从每题候选中选择，不输出题面、数量、单位、算式、答案或讲解。';

String buildPictureStoryPlanningPrompt(String? override) =>
    '${_resolve(override, kPictureStoryImageGenerationSystemPrompt)}\n\n'
    '当前任务仅规划适合儿童的单图场景，每题一幅图，场景要有差异。'
    '只描述一个可见时刻，不拼图、不分镜，不含暴力、成人、危险动作或可识别的真实孩子信息。\n'
    '只输出严格 JSON 数组，每项包含 imagePrompt（中文画面描述，'
    '建议 150–300 字，最多 $kPictureStorySceneDescriptionMaxLength 字）。'
    '描述具体可见的人物、环境、动作和物体关系。不要先编题目或答案。';

/// 将具体场景转为题图请求，保留单图叙事和教材插图的画面要求。
String buildPictureStoryImagePrompt(
  String sceneDescription, {
  String? promptOverride,
}) =>
    '${_resolve(promptOverride, kPictureStoryImageGenerationSystemPrompt)}\n\n'
    '当前任务是绘制下面的具体场景，人物动作和物体关系清楚。'
    '单张完整场景，不拼图、不分镜，不同时表现多个时刻或无关事件；'
    '不加文字、题目、答案、水印或标志。避免暴力、危险模仿及成人内容。\n'
    '具体场景：\n${sceneDescription.trim()}';

String buildPictureStoryQuestionPrompt(String? override) =>
    '${_resolve(override, kPictureStoryQuestionGenerationSystemPrompt)}\n\n'
    '当前任务是只依据实际图片，为 6–12 岁儿童出看图说话题。'
    '不要编造图中看不到的人数、物品、动作、情绪、人物关系或文字；'
    '推测或续编问题必须标明“你猜”或“想象”。题目开放，不设置唯一标准答案。'
    '只输出严格 JSON 对象：title（80 字以内）、theme（60 字以内，可空）、'
    'sceneFacts（可见事实的字符串数组，可空）、questions（1–5 个引导问题的字符串数组）、'
    'goals（字符串数组，可空）、reference（参考表达，可空，不能称标准答案）。'
    '数组每项不超过 400 字，reference 不超过 4000 字。语言简洁自然。';
