import 'dart:ui';

import 'package:json_annotation/json_annotation.dart';
import 'package:paperless_api/src/converters/hex_color_json_converter.dart';
import 'package:paperless_api/src/helper/helpers.dart';

part 'paperless_settings_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class PaperlessSettingsModel {
  @JsonKey(readValue: readArtificiallyNestedValue)
  @HexColorJsonConverter()
  final Color? color;
  @JsonKey(name: 'language')
  final String languageCode;

  PaperlessSettingsModel({
    this.color,
  });
}

@JsonSerializable(fieldRename: FieldRename.snake)
class DarkModeSettings {
  @JsonKey(fromJson: stringToBool)
  final bool enabled;
  final bool useSystem;
  @JsonKey(fromJson: stringToBool)
  final bool thumbInverted;

  DarkModeSettings({
    required this.enabled,
    required this.useSystem,
    required this.thumbInverted,
  });

  factory DarkModeSettings.fromJson(Map<String, dynamic> json) =>
      _$DarkModeSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$DarkModeSettingsToJson(this);
}

bool stringToBool(String boolean) {
  return boolean == 'true';
}
