/// A single word/phrase annotation attached to a poem.
class Annotation {
  const Annotation({required this.word, required this.meaning});

  factory Annotation.fromMap(Map<String, dynamic> map) {
    return Annotation(
      word: map['word'] as String,
      meaning: map['meaning'] as String,
    );
  }

  final String word;
  final String meaning;

  Map<String, dynamic> toJson() => {
        'word': word,
        'meaning': meaning,
      };
}
