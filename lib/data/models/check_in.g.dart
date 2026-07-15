// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'check_in.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CheckInAdapter extends TypeAdapter<CheckIn> {
  @override
  final int typeId = 12;

  @override
  CheckIn read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CheckIn(
      profileId: fields[0] as String,
      date: fields[1] as String,
      poemCount: fields[2] as int,
      mathCorrectCount: fields[3] as int,
      starsEarned: fields[4] as int,
      durationSeconds: fields[5] as int,
    );
  }

  @override
  void write(BinaryWriter writer, CheckIn obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.profileId)
      ..writeByte(1)
      ..write(obj.date)
      ..writeByte(2)
      ..write(obj.poemCount)
      ..writeByte(3)
      ..write(obj.mathCorrectCount)
      ..writeByte(4)
      ..write(obj.starsEarned)
      ..writeByte(5)
      ..write(obj.durationSeconds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CheckInAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
