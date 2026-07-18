import 'package:flutter/material.dart';

import 'package:cat_ship/data/game_data.dart';
import 'package:cat_ship/data/settings_data.dart';
import 'package:cat_ship/lib/udp_services.dart';
import 'package:logger/logger.dart';

class Data {
  static final Data _instance = Data._internal(); //this is for singleton

  Settings settings = Settings.init();
  Logger logger = getLogger();

  AppLifecycleState myAppLifecycleState = AppLifecycleState.resumed; //this is the default state after start
  Game game = Game.init();

  factory Data() {
    return _instance;
  }

  Data._internal();

  init() async {
    settings = await Settings.load();
  }

  void logMe(UdpServices udpServices) {
    globalData.logger.i('status ${game.status}');
    globalData.logger.i('conter ${game.conter}');
    if (game.opponent != null) {
      globalData.logger.i('${game.opponent}');
    }
    for (var bro in udpServices.broGroup.bros) {
      globalData.logger.i('Bro name ${bro.name} status ${bro.myStatus}');
    }
  }
}

Logger getLogger() => Logger(
      filter: null, // Use the default LogFilter (-> only log in debug mode)
      printer: PrettyPrinter(
        methodCount: 2, // Number of method calls to be displayed
        errorMethodCount: 8, // Number of method calls if stacktrace is provided
        lineLength: 120, // Width of the output
        colors: false, // Colorful log messages
        printEmojis: false, // Print an emoji for each log message
        // Should each log print contain a timestamp
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ), // Use the PrettyPrinter to format and print log
      output: null, // Use the default LogOutput (-> send everything to console)
    );
