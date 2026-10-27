# 汉字笔顺数据来源与修改声明

## 来源

本应用内置的汉字笔顺数据（`assets/data/writing_strokes.json.gz`）派生自
**Make Me a Hanzi** 项目的 `graphics.txt`（https://github.com/skishore/makemeahanzi）。

Make Me a Hanzi 的笔顺数据提取自 **Arphic Public License** 授权的
AR PL UKai / AR PL UMing 字体，其分发与使用遵循 Arphic Public License
（全文见同目录 `ARPHICPL.TXT`）。

## 修改声明（APL 2(c)）

原始数据经过以下修改后打包进本应用：

1. **裁剪**：只保留本应用已导入教材中出现的会写字（当前 2333 字），
   其余字形不随应用分发。
2. **坐标变换**：`strokes` 内的 SVG path 与 `medians` 内的折线坐标，
   y 轴由字体坐标翻转为屏幕坐标（`y' = 900 - y`），以匹配 Flutter 画布方向。
3. **重采样**：`medians` 按弧长重采样为最多 16 个点，用于笔画几何比对
   （方向、起止点、形状、长度）。
4. **字段裁剪**：只保留 `strokes` 与 `medians`，丢弃 `character`、
   `definition`、`pinyin`、`radical`、`matches` 等本应用不使用的字段。
5. **打包格式**：由 UTF-8 JSON 文本改为 gzip 压缩（`GZipCodec` level 9），
   运行时解压读取。

生成脚本见 `tool/extract_strokes.dart`。

## 署名

应用内「我的 → 关于 → 开源许可」列出本数据来源及 Arphic Public License 全文。