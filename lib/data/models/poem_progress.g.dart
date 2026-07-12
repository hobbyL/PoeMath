// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'poem_progress.dart';

class LearningStatusAdapter extends TypeAdapter<LearningStatus> {
  @override
  final int typeId = 20;

  @override
  LearningStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return LearningStatus.notStarted;
      case 1:
        return LearningStatus.learning;
      case 2:
        return LearningStatus.reviewing;
      case 3:
        return LearningStatus.mastered;
      default:
        return LearningStatus.notStarted;
    }
  }

  @override
  void write(BinaryWriter writer, LearningStatus obj) {
    writer.writeByte(obj.index);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LearningStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PoemProgressAdapter extends TypeAdapter<PoemProgress> {
  @override
  final int typeId = 5;

  @override
  PoemProgress read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PoemProgress(
      poemId: fields[0] as String,
      profileId: fields[1] as String,
      status: fields[2] as LearningStatus,
      masteryLevel: fields[3] as int,
      studyCount: fields[4] as int,
      lastStudiedAt: fields[5] as DateTime?,
      firstStudiedAt: fields[6] as DateTime?,
      stars: fields[7] as int,
    );
  }

  @override
  void write(BinaryWriter writer, PoemProgress obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.poemId)
      ..writeByte(1)
      ..write(obj.profileId)
      ..writeByte(2)
      ..write(obj.status)
      ..writeByte(3)
      ..write(obj.masteryLevel)
      ..writeByte(4)
      ..write(obj.studyCount)
      ..writeByte(5)
      ..write(obj.lastStudiedAt)
      ..writeByte(6)
      ..write(obj.firstStudiedAt)
      ..writeByte(7)
      ..write(obj.stars);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PoemProgressAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
