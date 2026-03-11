import '../../domain/entities/foundation_entity.dart';

class FoundationModel {
  final String id;
  final String name;

  const FoundationModel({
    required this.id,
    required this.name,
  });

  factory FoundationModel.fromJson(Map<String, dynamic> json) {
    return FoundationModel(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }

  FoundationEntity toEntity() => FoundationEntity(id: id, name: name);
}
