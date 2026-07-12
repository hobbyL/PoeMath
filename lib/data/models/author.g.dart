// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'author.dart';

class AuthorAdapter extends TypeAdapter<Author> {
  @override
  final int typeId = 1;

  @override
  Author read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Author(
      id: fields[0] as String,
      name: fields[1] as String,
      dynasty: fields[2] as String,
      lifeYears: fields[3] as String,
      title: fields[4] as String,
      brief: fields[5] as String,
      representativeWorks: (fields[6] as List).cast<String>(),
      avatar: fields[7] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Author obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.dynasty)
      ..writeByte(3)
      ..write(obj.lifeYears)
      ..writeByte(4)
      ..write(obj.title)
      ..writeByte(5)
      ..write(obj.brief)
      ..writeByte(6)
      ..write(obj.representativeWorks)
      ..writeByte(7)
      ..write(obj.avatar);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthorAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
