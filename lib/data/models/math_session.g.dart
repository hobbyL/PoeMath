// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'math_session.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MathSessionAdapter extends TypeAdapter<MathSession> {
  @override
  final int typeId = 9;

  @override
  MathSession read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MathSession(
      id: fields[0] as String,
      profileId: fields[1] as String,
      grade: fields[2] as int,
      problemType: fields[3] as String,
      totalProblems: fields[4] as int,
      correctCount: fields[5] as int,
      durationSeconds: fields[6] as int,
      starsEarned: fields[7] as int,
      startedAt: fields[8] as DateTime?,
      finishedAt: fields[9] as DateTime?,
      semester: fields[10] as String?,
      difficulty: fields[11] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, MathSession obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.profileId)
      ..writeByte(2)
      ..write(obj.grade)
      ..writeByte(3)
      ..write(obj.problemType)
      ..writeByte(4)
      ..write(obj.totalProblems)
      ..writeByte(5)
      ..write(obj.correctCount)
      ..writeByte(6)
      ..write(obj.durationSeconds)
      ..writeByte(7)
      ..write(obj.starsEarned)
      ..writeByte(8)
      ..write(obj.startedAt)
      ..writeByte(9)
      ..write(obj.finishedAt)
      ..writeByte(10)
      ..write(obj.semester)
      ..writeByte(11)
      ..write(obj.difficulty);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MathSessionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
