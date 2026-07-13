# 韵算 (PoeMath) 项目约定

## 技术栈

- Flutter 3.44.6 via FVM (`~/.pub-cache/bin/fvm flutter`)
- Dart 3.12.2
- Hive 本地存储 (14 boxes)
- Riverpod 状态管理
- GoRouter 路由

## UI 组件规范（必须遵守）

### 卡片 / 容器

**所有页面的信息卡片、区域容器必须使用 `ColoredCard`**，禁止手写 `BoxDecoration`：

```dart
import 'package:poemath/core/widgets/app_widgets.dart';

// ✅ 使用 ColoredCard
ColoredCard(color: theme.colorScheme.primary, child: ...)

// ❌ 禁止手写
Container(decoration: BoxDecoration(color: ..., borderRadius: ...))
```

### 列表行 / 设置项

**所有设置项、功能列表必须使用 `AppTile`**，禁止页面私有 Tile 组件：

```dart
AppTile(
  icon: Icons.palette_outlined,
  iconColor: theme.colorScheme.primary,
  title: '主题设置',
  subtitle: '诗词',
  onTap: () => ...,
)
```

### 设计令牌

- 间距：`SpacingTokens.xs/sm/md/lg/xl`，禁止魔法数字
- 圆角：`SpacingTokens.radiusSmall/radiusMedium/radiusLarge/radiusPill`
- 颜色：`theme.colorScheme.*` 或 `ColorTokens.*`，禁止硬编码

完整规范见 `.trellis/spec/frontend/component-guidelines.md`。

## 运行命令

```bash
~/.pub-cache/bin/fvm flutter analyze       # 代码分析
~/.pub-cache/bin/fvm dart fix --apply      # 自动修复 lint
~/.pub-cache/bin/fvm flutter test          # 运行测试
```

## 开发流程要求

- 修改 UI/逻辑后，**必须运行 `flutter test` 确认测试通过后再 commit**
- 修改 UI 组件时，主动检查对应测试文件是否需要同步更新
