// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'formula_favorite.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FormulaFavoriteAdapter extends TypeAdapter<FormulaFavorite> {
  @override
  final int typeId = 10;

  @override
  FormulaFavorite read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FormulaFavorite(
      formulaId: fields[0] as String,
      profileId: fields[1] as String,
      createdAt: fields[2] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, FormulaFavorite obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.formulaId)
      ..writeByte(1)
      ..write(obj.profileId)
      ..writeByte(2)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FormulaFavoriteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
