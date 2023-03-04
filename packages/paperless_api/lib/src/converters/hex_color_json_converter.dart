import 'dart:ui';

import 'package:json_annotation/json_annotation.dart';

class HexColorJsonConverter implements JsonConverter<Color?, dynamic> {
  const HexColorJsonConverter();
  @override
  Color? fromJson(dynamic json) {
    if (json is Color) {
      return json;
    }
    if (json is String) {
      if (json.isEmpty) return null;
      final decoded = int.tryParse(json.replaceAll("#", "ff"), radix: 16);
      if (decoded == null) {
        return null;
      }
      return Color(decoded);
    }
    return null;
  }

  @override
  String? toJson(Color? color) {
    if (color == null) {
      return null;
    }
    String val =
        '#${(color.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toLowerCase()}';
    return val;
  }
}
