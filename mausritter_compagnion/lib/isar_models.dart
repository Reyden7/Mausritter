import 'package:isar/isar.dart';

part 'isar_models.g.dart';

@collection
class IsarItem {
  Id id = Isar.autoIncrement;
  late int remoteId;              // items.id (bigint)
  late String name;
  String? imageUrl;
  int durabilityMax = 3;
  List<String> compatibleSlots = [];
  String category = 'OTHER';
  DateTime updatedAt = DateTime.now();
}

@collection
class IsarCharacter {
  Id id = Isar.autoIncrement;
  late String remoteId;           // characters.id (uuid)
  late String ownerId;
  String name = '';
  String background = '';
  int level = 1;
  int xp = 0;
  int strMax = 10, strCur = 10;
  int dexMax = 10, dexCur = 10;
  int wilMax = 10, wilCur = 10;
  int hpMax  = 4,  hpCur  = 4;
  DateTime updatedAt = DateTime.now();
}

@collection
class IsarEquip {
  Id id = Isar.autoIncrement;
  late String characterId;        // uuid
  late String slot;               // PAW_MAIN...
  late int itemId;                // items.id
  int durabilityUsed = 0;
  DateTime updatedAt = DateTime.now();
  // PK logique: (characterId, slot)
}
