// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'learning_activity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LearningActivityAdapter extends TypeAdapter<LearningActivity> {
  @override
  final int typeId = 15;

  @override
  LearningActivity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LearningActivity(
      id: fields[0] as String,
      profileId: fields[1] as String,
      activityType: fields[2] as String,
      totalItems: fields[3] as int,
      successfulItems: fields[4] as int,
      starsEarned: fields[6] as int,
      durationSeconds: fields[7] as int,
      completedAt: fields[8] as DateTime,
      poemId: fields[5] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, LearningActivity obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.profileId)
      ..writeByte(2)
      ..write(obj.activityType)
      ..writeByte(3)
      ..write(obj.totalItems)
      ..writeByte(4)
      ..write(obj.successfulItems)
      ..writeByte(5)
      ..write(obj.poemId)
      ..writeByte(6)
      ..write(obj.starsEarned)
      ..writeByte(7)
      ..write(obj.durationSeconds)
      ..writeByte(8)
      ..write(obj.completedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LearningActivityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
