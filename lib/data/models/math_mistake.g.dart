// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'math_mistake.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MathMistakeAdapter extends TypeAdapter<MathMistake> {
  @override
  final int typeId = 8;

  @override
  MathMistake read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MathMistake(
      id: fields[0] as String,
      profileId: fields[1] as String,
      problemText: fields[2] as String,
      correctAnswer: fields[3] as String,
      userAnswer: fields[4] as String,
      problemType: fields[5] as String,
      grade: fields[6] as int,
      errorType: fields[7] as String?,
      solutionStepsJson: fields[8] as String?,
      createdAt: fields[9] as DateTime?,
      isResolved: fields[10] as bool,
      retryCount: fields[11] as int,
      wrongCount: fields[12] as int,
      lastWrongAt: fields[13] as DateTime?,
      consolidationRound: fields[14] as int,
      nextConsolidationDate: fields[15] as DateTime?,
      skillId: fields[16] as String?,
      semester: fields[17] as String?,
      problemJson: fields[18] as String?,
      attemptJson: fields[19] as String?,
      appliedActivityIds:
          fields[20] == null ? [] : (fields[20] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, MathMistake obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.profileId)
      ..writeByte(2)
      ..write(obj.problemText)
      ..writeByte(3)
      ..write(obj.correctAnswer)
      ..writeByte(4)
      ..write(obj.userAnswer)
      ..writeByte(5)
      ..write(obj.problemType)
      ..writeByte(6)
      ..write(obj.grade)
      ..writeByte(7)
      ..write(obj.errorType)
      ..writeByte(8)
      ..write(obj.solutionStepsJson)
      ..writeByte(9)
      ..write(obj.createdAt)
      ..writeByte(10)
      ..write(obj.isResolved)
      ..writeByte(11)
      ..write(obj.retryCount)
      ..writeByte(12)
      ..write(obj.wrongCount)
      ..writeByte(13)
      ..write(obj.lastWrongAt)
      ..writeByte(14)
      ..write(obj.consolidationRound)
      ..writeByte(15)
      ..write(obj.nextConsolidationDate)
      ..writeByte(16)
      ..write(obj.skillId)
      ..writeByte(17)
      ..write(obj.semester)
      ..writeByte(18)
      ..write(obj.problemJson)
      ..writeByte(19)
      ..write(obj.attemptJson)
      ..writeByte(20)
      ..write(obj.appliedActivityIds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MathMistakeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
