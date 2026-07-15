// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'formula.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FormulaAdapter extends TypeAdapter<Formula> {
  @override
  final int typeId = 2;

  @override
  Formula read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Formula(
      id: fields[0] as String,
      category: fields[1] as String,
      name: fields[2] as String,
      formulaText: fields[3] as String,
      formulaLatex: fields[4] as String,
      grade: fields[5] as int,
      params: (fields[6] as List).cast<FormulaParam>(),
      memoryTip: fields[7] as String,
      example: fields[8] as String,
      relatedFormulas: (fields[9] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, Formula obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.category)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.formulaText)
      ..writeByte(4)
      ..write(obj.formulaLatex)
      ..writeByte(5)
      ..write(obj.grade)
      ..writeByte(6)
      ..write(obj.params)
      ..writeByte(7)
      ..write(obj.memoryTip)
      ..writeByte(8)
      ..write(obj.example)
      ..writeByte(9)
      ..write(obj.relatedFormulas);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FormulaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
