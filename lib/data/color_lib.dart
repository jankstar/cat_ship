
import 'package:flutter/material.dart';

class ColorString {
  String name;
  Color color;
  ColorString(this.name, this.color);
}

class ColorLib {
  static final colorStringList = [
    ColorString('', Colors.black),
    ColorString('white', Colors.white),
    ColorString('ambler', Colors.amber),
    ColorString('pink', Colors.pink),
    ColorString('green', Colors.green),
    ColorString('blue', Colors.blue),
    ColorString('purple', Colors.purple),
  ];
  static ColorString getColorByName(String name) {
    return colorStringList.firstWhere((element) => element.name == name,
        orElse: () => colorStringList[0]);
  }
  static ColorString getBackgroundColorByName(String name) {
    if (name == '') {
      return ColorString('grey', Colors.grey.shade300);
    }
    return colorStringList.firstWhere((element) => element.name == name,
        orElse: () => colorStringList[1]);
  }
}