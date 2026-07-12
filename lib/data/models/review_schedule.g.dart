// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_schedule.dart';

class ReviewScheduleAdapter extends TypeAdapter<ReviewSchedule> {
  @override
  final int typeId = 7;

  @override
  ReviewSchedule read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReviewSchedule(
      poemId: fields[0] as String,
      profileId: fields[1] as String,
      currentRound: fields[2] as int,
      nextReviewDate: fields[3] as DateTime,
      lastReviewedAt: fields[4] as DateTime?,
      isCompleted: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, ReviewSchedule obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.poemId)
      ..writeByte(1)
      ..write(obj.profileId)
      ..writeByte(2)
      ..write(obj.currentRound)
      ..writeByte(3)
      ..write(obj.nextReviewDate)
      ..writeByte(4)
      ..write(obj.lastReviewedAt)
      ..writeByte(5)
      ..write(obj.isCompleted);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewScheduleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
