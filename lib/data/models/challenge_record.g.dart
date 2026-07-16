// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'challenge_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ChallengeRecordAdapter extends TypeAdapter<ChallengeRecord> {
  @override
  final int typeId = 14;

  @override
  ChallengeRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChallengeRecord(
      id: fields[0] as String,
      profileId: fields[1] as String,
      mode: fields[2] as String,
      score: fields[3] as int,
      totalAnswered: fields[4] as int,
      correctCount: fields[5] as int,
      bestCombo: fields[6] as int,
      grade: fields[7] as int,
      semester: fields[8] as String,
      difficulty: fields[9] as String,
      durationSeconds: fields[10] as int,
      createdAt: fields[11] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, ChallengeRecord obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.profileId)
      ..writeByte(2)
      ..write(obj.mode)
      ..writeByte(3)
      ..write(obj.score)
      ..writeByte(4)
      ..write(obj.totalAnswered)
      ..writeByte(5)
      ..write(obj.correctCount)
      ..writeByte(6)
      ..write(obj.bestCombo)
      ..writeByte(7)
      ..write(obj.grade)
      ..writeByte(8)
      ..write(obj.semester)
      ..writeByte(9)
      ..write(obj.difficulty)
      ..writeByte(10)
      ..write(obj.durationSeconds)
      ..writeByte(11)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChallengeRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
