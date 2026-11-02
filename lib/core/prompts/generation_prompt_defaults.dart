// AI 出题的可编辑默认提示词。输出格式与事实边界由各阶段在请求时追加。

/// 应用题默认素材选择偏好；数学关系和题面由本机计划生成。
const String kWordProblemGenerationSystemPrompt = '为小学应用题选择多样的生活情境素材。';

/// 看图说话默认教学偏好，场景规划与实际图片出题共同使用。
const String kPictureStoryGenerationSystemPrompt = '''
你是小学语文口语表达老师，面向 6–12 岁儿童。
采用小学语文课本式看图说话，每题一幅图，围绕一件儿童熟悉、可以讲述的小事。
突出人物正在做的事情、动作和互动，用可见的画面线索帮助孩子讲清事情经过。每题的事件和场景要有差异。
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
    '当前任务是规划小学语文课本式的单图故事场景。每题围绕一件儿童熟悉的日常小事，'
    '选择事情正在发生的一个关键时刻，只用一幅图表现。\n'
    '通常安排 2–4 名主要人物，明确谁在哪里、正在做什么、与谁或什么物体互动；'
    '写清动作、手势、视线、表情以及关键物品的状态，避免人物只是站着或摆拍。\n'
    '用画面内的可见线索体现事件的起因或结果，让孩子能据图讲述一件事；'
    '不要依赖看不见的过去、未来、内心活动或文字说明，也不要把多个时刻拼在一张图里。\n'
    '主要人物与关键物品完整、清楚地呈现，背景只保留交代地点和情节所需的内容。'
    '各题在事件、人物动作和地点上有差异，不能仅换颜色或装饰。'
    '不含暴力、成人、危险动作或可识别的真实孩子信息。\n'
    '只输出严格 JSON 数组，每项包含 imagePrompt（中文画面描述，最多 1000 字）。'
    '描述具体可见的人物、环境、动作和物体关系。不要先编题目或答案。';

/// 将具体场景转为题图请求，保留单图叙事和教材插图的画面要求。
String buildPictureStoryImagePrompt(String sceneDescription) =>
    '为 6–12 岁儿童的看图说话练习绘制小学语文课本式插图。\n'
    '一幅图讲一件事，只画事情正在发生的一个关键时刻。'
    '人物正在做什么、彼此怎样互动、与哪些物品有关，必须能从画面直接看出来。\n'
    '画风：平面手绘儿童教材插图，轮廓清晰，色彩柔和明快，人物比例自然，表情和手势清楚。\n'
    '构图：主要人物和与事件相关的物品占据画面主体，完整可见；'
    '交互的手部、视线方向和关键道具不能被遮挡，背景简洁，只保留交代地点和情节的环境。\n'
    '突出动作、互动和事件线索，避免人物排排站、看向镜头摆拍、只有风景或装饰。'
    '不使用照片、电影海报或夸张的 3D 渲染风格。\n'
    '单张完整场景，不拼图、不分镜，不同时表现多个时刻或无关事件；'
    '不加文字、题目、答案、水印或标志。避免暴力、危险模仿及成人内容。\n'
    '具体场景：\n${sceneDescription.trim()}';

String buildPictureStoryQuestionPrompt(String? override) =>
    '${_resolve(override, kPictureStoryGenerationSystemPrompt)}\n\n'
    '当前任务是只依据实际图片，为 6–12 岁儿童出看图说话题。'
    '不要编造图中看不到的人数、物品、动作、情绪、人物关系或文字；'
    '推测或续编问题必须标明“你猜”或“想象”。题目开放，不设置唯一标准答案。'
    '只输出严格 JSON 对象：title（80 字以内）、theme（60 字以内，可空）、'
    'sceneFacts（可见事实的字符串数组，可空）、questions（1–5 个引导问题的字符串数组）、'
    'goals（字符串数组，可空）、reference（参考表达，可空，不能称标准答案）。'
    '数组每项不超过 400 字，reference 不超过 4000 字。语言简洁自然。';
