// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'formula_param.dart';

class FormulaParamAdapter extends TypeAdapter<FormulaParam> {
  @override
  final int typeId = 4;

  @override
  FormulaParam read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FormulaParam(
      symbol: fields[0] as String,
      meaning: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, FormulaParam obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.symbol)
      ..writeByte(1)
      ..write(obj.meaning);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FormulaParamAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
