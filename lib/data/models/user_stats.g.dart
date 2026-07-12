// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_stats.dart';

class UserStatsAdapter extends TypeAdapter<UserStats> {
  @override
  final int typeId = 13;

  @override
  UserStats read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserStats(
      profileId: fields[0] as String,
      totalStars: fields[1] as int,
      currentStreak: fields[2] as int,
      longestStreak: fields[3] as int,
      poemsLearned: fields[4] as int,
      poemsMastered: fields[5] as int,
      mathTotalProblems: fields[6] as int,
      mathTotalCorrect: fields[7] as int,
      level: fields[8] as int,
      createdAt: fields[9] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, UserStats obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.profileId)
      ..writeByte(1)
      ..write(obj.totalStars)
      ..writeByte(2)
      ..write(obj.currentStreak)
      ..writeByte(3)
      ..write(obj.longestStreak)
      ..writeByte(4)
      ..write(obj.poemsLearned)
      ..writeByte(5)
      ..write(obj.poemsMastered)
      ..writeByte(6)
      ..write(obj.mathTotalProblems)
      ..writeByte(7)
      ..write(obj.mathTotalCorrect)
      ..writeByte(8)
      ..write(obj.level)
      ..writeByte(9)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserStatsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
