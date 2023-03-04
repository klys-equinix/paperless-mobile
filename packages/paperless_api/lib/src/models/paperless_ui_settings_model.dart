import 'package:json_annotation/json_annotation.dart';
import 'package:paperless_api/src/helper/helpers.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class PaperlessUISettings {
  final int userId;
  final String username;
  final String displayName;
  @JsonKey(readValue: readArtificiallyNestedValue)
  final String settings;
}
