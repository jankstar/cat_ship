import 'dart:convert';
import 'package:cat_ship/main.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rsa_encrypt/rsa_encrypt.dart';
import 'package:pointycastle/export.dart';


///the settings class for myself data
class Settings {
  String publicKey;
  String name;
  String pic;
  String color;
  String privateKey;
  String? locale;

  Settings(
      {required this.publicKey,
      required this.name,
      required this.pic,
      required this.color,
      required this.privateKey, //
      this.locale});

  factory Settings.fromJson(Map<String, dynamic> json) {
    return Settings(
        publicKey: json['public_key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        pic: json['pic'] as String? ?? '',
        color: json['color'] as String? ?? '',
        privateKey: json['private_key'] as String? ?? '',
        locale: json['locale'] as String? ?? 'en');
  }

  factory Settings.init() {
    return Settings(publicKey: '', name: '', pic: '', color: '', privateKey: '');
  }

  static Future<Settings> load() async {
    globalData.logger.i('loadSettings');

    var me = Settings.init();

    await SharedPreferences.getInstance().then((prefs) {
      if (prefs.containsKey('me')) {
        try {
          me = Settings.fromJson(jsonDecode(prefs.getString('me') ?? "{}") as Map<String, dynamic>);
        } catch (e) {
          globalData.logger.e('Error loadSettings ${e.toString()}\n');
          me.clearMe();
        }
      }
    }, onError: (e) {
      globalData.logger.e('Error loadSettings SharedPreferences \n${e.toString()}\n');
    });

    if (me.publicKey.isEmpty) {
      globalData.logger.i('loadSettings publicKey empty\n');

      ///no me-data found so we generate a new one
      var helper = RsaKeyHelper();

      final keyPair = await helper.computeRSAKeyPair(helper.getSecureRandom());

      final myPublic = keyPair.publicKey as RSAPublicKey;
      final myPrivate = keyPair.privateKey as RSAPrivateKey;

      var keyPairRSA = AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(myPublic, myPrivate);

      me.publicKey = helper.encodePublicKeyToPemPKCS1(keyPairRSA.publicKey);
      me.privateKey = helper.encodePrivateKeyToPemPKCS1(keyPairRSA.privateKey);
      //await me.save();
      me.save();
    }

    return me;
  }

  setName(iName) {
    name = iName;
  }

  setPic(iPic) {
    pic = iPic;
  }

  setColor(iColor) {
    color = iColor;
  }

  clearMe() {
    publicKey = "";
    name = "";
    pic = "";
    color = "";
    privateKey = "";
    save();
  }

  save() async {
    globalData.logger.i('saveSettings\n');
    await SharedPreferences.getInstance().then((prefs) {
      try {
        if (publicKey.isEmpty) {
          ///remove me-data
          prefs.remove('me');
          globalData.logger.i('removed me-data while key is empty\n');
        } else {
          ///save me-data
          prefs.setString('me', jsonEncode(toJson()));
        }
      } catch (e) {
        globalData.logger.e('Error saveSettings ${e.toString()}\n');
      }
    }, onError: (e) {
      globalData.logger.e('Error saveSettings ${e.toString()}\n');
    });
  }

  Map toJson() {
    return {
      'public_key': publicKey,
      'name': name,
      'pic': pic,
      'color': color,
      'private_key': privateKey,
      'locale': locale,
    };
  }

  Map toJsonPub(AppLifecycleState? iState) {
    return {
      'public_key': publicKey,
      'name': name,
      'pic': pic,
      'color': color,
      'lifecycle_state': iState.toString(),
    };
  }
}
