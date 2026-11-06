import 'dart:convert';

Map<String, Object?> pictureStoryFeedbackFixture({
  String answer = '孩子的表达',
  int questionCount = 2,
}) => {
  'version': 1,
  'summary': '你说清了地点。再补充一个动作。',
  'dimensions': [
    for (final id in ['picture', 'response', 'expression'])
      {'id': id, 'status': 'met', 'evidence': answer, 'reason': '这句提供了表达的依据。'},
  ],
  'questions': [
    for (var i = 1; i <= questionCount; i++)
      {
        'id': '$i',
        'status': 'developing',
        'evidence': '',
        'reason': '可以再补充相关细节。',
      },
  ],
  'suggestions': <Object>[],
};

String pictureStoryFeedbackResponse({
  String answer = '孩子的表达',
  int questionCount = 2,
}) => jsonEncode({
  'choices': [
    {
      'message': {
        'role': 'assistant',
        'content': jsonEncode(
          pictureStoryFeedbackFixture(
            answer: answer,
            questionCount: questionCount,
          ),
        ),
      },
    },
  ],
});
