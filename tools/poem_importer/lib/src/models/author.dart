/// Poet metadata for the authors JSON asset.
class Author {
  const Author({
    required this.id,
    required this.name,
    required this.dynasty,
    required this.lifeYears,
    required this.title,
    required this.brief,
    required this.representativeWorks,
    required this.avatar,
  });

  final String id;
  final String name;
  final String dynasty;
  final String? lifeYears;
  final String? title;
  final String brief;
  final List<String> representativeWorks;
  final String avatar;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'dynasty': dynasty,
      'life_years': lifeYears,
      'title': title,
      'brief': brief,
      'representative_works': representativeWorks,
      'avatar': avatar,
    };
  }
}
