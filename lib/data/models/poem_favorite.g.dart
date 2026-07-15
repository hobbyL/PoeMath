// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'poem_favorite.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PoemFavoriteAdapter extends TypeAdapter<PoemFavorite> {
  @override
  final int typeId = 6;

  @override
  PoemFavorite read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PoemFavorite(
      poemId: fields[0] as String,
      profileId: fields[1] as String,
      createdAt: fields[2] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, PoemFavorite obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.poemId)
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
      other is PoemFavoriteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
