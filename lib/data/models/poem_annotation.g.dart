// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'poem_annotation.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PoemAnnotationAdapter extends TypeAdapter<PoemAnnotation> {
  @override
  final int typeId = 3;

  @override
  PoemAnnotation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PoemAnnotation(
      word: fields[0] as String,
      meaning: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, PoemAnnotation obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.word)
      ..writeByte(1)
      ..write(obj.meaning);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PoemAnnotationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
