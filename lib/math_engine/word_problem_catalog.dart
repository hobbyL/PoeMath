import 'models/word_problem_plan.dart';

/// 整套素材包含对象和量词，避免AI单独选择后错配。
class WordProblemScene {
  const WordProblemScene(
    this.id,
    this.object,
    this.unit,
    this.place, {
    this.group = '盒',
    this.purchase = false,
  });

  final String id;
  final String object;
  final String unit;
  final String place;
  final String group;
  final bool purchase;
}

class WordProblemCatalog {
  const WordProblemCatalog._();

  static const scenes = [
    WordProblemScene('pencils', '铅笔', '支', '文具室'),
    WordProblemScene('books', '图书', '本', '图书室'),
    WordProblemScene('cards', '卡片', '张', '活动室'),
    WordProblemScene('beads', '珠子', '颗', '手工教室'),
    WordProblemScene('apples', '苹果', '个', '水果店'),
    WordProblemScene('flowers', '鲜花', '朵', '花店'),
    WordProblemScene('water', '水', '瓶', '仓库'),
    WordProblemScene('ribbon', '彩带', '米', '手工材料店', group: '卷'),
    WordProblemScene('rice', '大米', '千克', '粮店', group: '袋'),
    WordProblemScene('money', '活动经费', '元', '活动小组', group: '份'),
    WordProblemScene('bookPrice', '图书', '元', '书店', group: '本', purchase: true),
    WordProblemScene('petals', '花瓣', '片', '花艺教室', group: '朵'),
  ];

  static const variantIds = ['standard', 'alternate'];

  static WordProblemScene? find(String id) {
    for (final scene in scenes) {
      if (scene.id == id) return scene;
    }
    return null;
  }

  static List<WordProblemScene> forRelation(WordProblemRelation relation) =>
      scenes.where((scene) {
        if (scene.purchase) return relation == WordProblemRelation.equalGroups;
        if (scene.id == 'petals') {
          return relation == WordProblemRelation.equalGroups;
        }
        return true;
      }).toList(growable: false);
}
