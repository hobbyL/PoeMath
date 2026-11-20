/// 外观预设。沿用已有 AppSubject 名称及 poem/math 存储值，避免迁移偏好。
enum AppSubject {
  poem('宣纸 · 松墨', '青白素宣 · 松绿冷墨 · 松枝山水'),
  math('宣纸 · 赭石', '暖黄旧纸 · 棕墨朱砂 · 梅枝书案'),
  candy('奶糖乐园', '学习手账 · 云上伙伴 · 贴纸入口'),
  space('星海探险', '太空舷窗 · 目标航程 · 切角舱面');

  const AppSubject(this.label, this.description);

  final String label;
  final String description;

  static AppSubject? fromId(Object? value) {
    for (final subject in values) {
      if (subject.name == value) return subject;
    }
    return null;
  }
}
