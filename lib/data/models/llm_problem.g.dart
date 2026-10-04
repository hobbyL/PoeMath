// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'llm_problem.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LlmProblemAdapter extends TypeAdapter<LlmProblem> {
  @override
  final int typeId = 16;

  @override
  LlmProblem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LlmProblem(
      id: fields[0] as String,
      profileId: fields[1] as String,
      questionText: fields[2] as String,
      unit: fields[3] as String,
      operands: (fields[4] as List).cast<int>(),
      operators: (fields[5] as List).cast<String>(),
      answer: fields[6] as int,
      explanation: fields[7] as String,
      batchId: fields[8] as String,
      createdAt: fields[9] as DateTime,
      grade: fields[10] as int,
      semester: fields[11] as String,
      topic: fields[12] as String,
      difficulty: fields[13] as int,
      done: fields[14] as bool,
      attempts: fields[15] as int,
      correctCount: fields[16] as int,
      lastDoneAt: fields[17] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, LlmProblem obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.profileId)
      ..writeByte(2)
      ..write(obj.questionText)
      ..writeByte(3)
      ..write(obj.unit)
      ..writeByte(4)
      ..write(obj.operands)
      ..writeByte(5)
      ..write(obj.operators)
      ..writeByte(6)
      ..write(obj.answer)
      ..writeByte(7)
      ..write(obj.explanation)
      ..writeByte(8)
      ..write(obj.batchId)
      ..writeByte(9)
      ..write(obj.createdAt)
      ..writeByte(10)
      ..write(obj.grade)
      ..writeByte(11)
      ..write(obj.semester)
      ..writeByte(12)
      ..write(obj.topic)
      ..writeByte(13)
      ..write(obj.difficulty)
      ..writeByte(14)
      ..write(obj.done)
      ..writeByte(15)
      ..write(obj.attempts)
      ..writeByte(16)
      ..write(obj.correctCount)
      ..writeByte(17)
      ..write(obj.lastDoneAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LlmProblemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
