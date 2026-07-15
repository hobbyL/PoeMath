// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'poem.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PoemAdapter extends TypeAdapter<Poem> {
  @override
  final int typeId = 0;

  @override
  Poem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Poem(
      id: fields[0] as String,
      title: fields[1] as String,
      author: fields[2] as String,
      dynasty: fields[3] as String,
      content: fields[4] as String,
      pinyin: fields[5] as String,
      layer: fields[6] as String,
      grade: fields[7] as int?,
      semester: fields[8] as String?,
      textbookUnit: fields[9] as String?,
      isRequired: fields[10] as bool,
      annotations: (fields[11] as List).cast<PoemAnnotation>(),
      translation: fields[12] as String,
      appreciation: fields[13] as String,
      background: fields[14] as String,
      famousLines: (fields[15] as List).cast<String>(),
      tags: (fields[16] as List).cast<String>(),
      difficulty: fields[17] as int,
    );
  }

  @override
  void write(BinaryWriter writer, Poem obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.author)
      ..writeByte(3)
      ..write(obj.dynasty)
      ..writeByte(4)
      ..write(obj.content)
      ..writeByte(5)
      ..write(obj.pinyin)
      ..writeByte(6)
      ..write(obj.layer)
      ..writeByte(7)
      ..write(obj.grade)
      ..writeByte(8)
      ..write(obj.semester)
      ..writeByte(9)
      ..write(obj.textbookUnit)
      ..writeByte(10)
      ..write(obj.isRequired)
      ..writeByte(11)
      ..write(obj.annotations)
      ..writeByte(12)
      ..write(obj.translation)
      ..writeByte(13)
      ..write(obj.appreciation)
      ..writeByte(14)
      ..write(obj.background)
      ..writeByte(15)
      ..write(obj.famousLines)
      ..writeByte(16)
      ..write(obj.tags)
      ..writeByte(17)
      ..write(obj.difficulty);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PoemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
