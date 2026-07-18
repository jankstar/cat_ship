import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cat_ship/data/global_data.dart';
import 'package:flutter/material.dart';
import 'package:cat_ship/data/bro_data.dart';
import 'package:cat_ship/data/game_data.dart';
import 'package:uuid/uuid.dart';

Data globalData = Data();

class UdpSliceBuffer {
  UdpSlice item;
  String ip;
  DateTime timestamp;
  UdpSliceBuffer({required this.item, required this.ip, required this.timestamp});
}

class UdpSlice {
  String id;
  int nr;
  int count;
  String data;
  UdpSlice({required this.id, required this.nr, required this.count, required this.data});
  Map toJson() {
    return {'id': id, 'nr': nr, 'count': count, 'data': data};
  }

  factory UdpSlice.fromJson(Map<String, dynamic> json) {
    return UdpSlice(
        id: json['id'] as String, nr: json['nr'] as int, count: json['count'] as int, data: json['data'] as String);
  }
}

class Command {
  String command;
  String data;
  Command({required this.command, required this.data});
  Map toJson() {
    return {'command': command, 'data': data};
  }

  factory Command.fromJson(Map<String, dynamic> json) {
    return Command(command: json['command'] as String, data: json['data'] as String);
  }

  List<UdpSlice> getUdpSlices() {
    const lLen = 500;
    List<UdpSlice> slices = [];
    try {
      final iId = const Uuid().v4();
      var iNr = 0;
      List<int> data = utf8.encode(json.encode(toJson()));
      if (data.isEmpty) throw Exception('data.length == 0');
      do {
        if (data.length > lLen) {
          var slice = UdpSlice(id: iId, nr: iNr, count: iNr, data: utf8.decode(data.sublist(0, lLen)));
          data = data.sublist(lLen).toList();
          slices.add(slice);
        } else {
          var slice = UdpSlice(id: iId, nr: iNr, count: iNr, data: utf8.decode(data));
          slices.add(slice);
          data.clear();
          exit;
        }
        iNr += 1;
      } while (data.isNotEmpty);
      for (var i = 0; i < slices.length; i++) {
        slices[i].count = slices.length - 1;
        //globalData.logger.i('getUdpClices slice ${i + 1}/${slices[i].id}/${slices[i].nr}/${slices[i].count}\n');
      }
    } catch (e) {
      globalData.logger.e('Error getUdpClices ${e.toString()}\n');
    }
    return slices;
  }
}

class UdpServices with ChangeNotifier {
  final int timerInterval = 5;
  final int myPort = 54321;
  RawDatagramSocket? udpListenSocket;
  Timer? loopTimer;
  Timer? acceptTimer;
  Timer? shotRetryTimer;
  Timer? starterPickRetryTimer;
  Timer? _stuckWatchdog;
  bool _starterPickAckPending = false;
  VoidCallback? _resumeStuckRetry;
  BroGroup broGroup = BroGroup();
  List<UdpSliceBuffer> udpSlicesBuffer = [];

  static const _retryInterval = Duration(seconds: 1);
  static const _stuckAfter = Duration(seconds: 20);

  ///gameInterrupted : true once a shot/starterPick has gone unacknowledged for
  ///[_stuckAfter] despite retrying every [_retryInterval] - the UI must offer the
  ///player a choice to keep retrying or abort
  bool gameInterrupted = false;

//-//////////////////////////////////////////////////////////////////////////////
  ///startAcceptTimer : ~20s for the other side to accept a startRequest, otherwise cancel locally
  void startAcceptTimer() {
    acceptTimer?.cancel();
    acceptTimer = Timer(const Duration(seconds: 20), () {
      if (globalData.game.status == GameStatus.startRequestAndWait) {
        globalData.logger.i('accept request timed out\n');
        sendMessage('Hello !', globalData.game.opponent?.publicKey, 'exit');
        globalData.game.clearGame();
        notifyListeners();
      }
    });
  }

  void cancelAcceptTimer() {
    acceptTimer?.cancel();
    acceptTimer = null;
  }

//-//////////////////////////////////////////////////////////////////////////////
  ///cancelGameTimers : stop all in-flight game timers (accept/shot-retry/starterPick-retry/watchdog) <br>
  ///must be called whenever the game is aborted/cleared, otherwise a stale retry could
  ///fire into a fresh/cleared game state
  void cancelGameTimers() {
    cancelAcceptTimer();
    shotRetryTimer?.cancel();
    shotRetryTimer = null;
    starterPickRetryTimer?.cancel();
    starterPickRetryTimer = null;
    _starterPickAckPending = false;
    _stuckWatchdog?.cancel();
    _stuckWatchdog = null;
    gameInterrupted = false;
    _resumeStuckRetry = null;
  }

//-//////////////////////////////////////////////////////////////////////////////
  ///_armStuckWatchdog : if [stillPending] is still true after [_stuckAfter] of retrying,
  ///stop retrying and surface the interruption to the UI via [gameInterrupted] instead of
  ///retrying silently forever - [onResume] is what "weiter" (continue) re-arms
  void _armStuckWatchdog(bool Function() stillPending, VoidCallback onResume) {
    _stuckWatchdog?.cancel();
    _stuckWatchdog = Timer(_stuckAfter, () {
      if (!stillPending()) return;
      shotRetryTimer?.cancel();
      starterPickRetryTimer?.cancel();
      gameInterrupted = true;
      _resumeStuckRetry = onResume;
      notifyListeners();
    });
  }

//-//////////////////////////////////////////////////////////////////////////////
  ///continueAfterInterruption : user chose "weiter" on the interruption dialog -
  ///resume retrying (for another [_stuckAfter]) instead of aborting the game
  void continueAfterInterruption() {
    gameInterrupted = false;
    final resume = _resumeStuckRetry;
    _resumeStuckRetry = null;
    resume?.call();
    notifyListeners();
  }

//-//////////////////////////////////////////////////////////////////////////////
  ///resolveStarterIfNeeded : once both sides are ready (status == inGame), exactly one
  ///side (the deterministic "picker") flips a coin and tells the other who starts. <br>
  ///the pick is resent every second until the other side confirms via 'starterPickAck',
  ///so a single lost UDP packet can't leave the non-picker stuck without a decision
  Future<void> resolveStarterIfNeeded() async {
    if (globalData.game.status != GameStatus.inGame || globalData.game.opponent == null) return;
    if (!globalData.game.amIStarterPicker()) return;

    final iStart = Random().nextBool();
    final youStart = !iStart;
    final opponentKey = globalData.game.opponent!.publicKey;
    globalData.game.status = iStart ? GameStatus.inGameMyStep : GameStatus.inGameRemoteStep;
    _starterPickAckPending = true;
    await _starterPickAttempt(opponentKey, youStart);
    notifyListeners();
  }

  Future<void> _starterPickAttempt(String opponentKey, bool youStart) async {
    await sendGameCommand(opponentKey, 'starterPick', {'youStart': youStart});
    starterPickRetryTimer?.cancel();
    starterPickRetryTimer = Timer.periodic(_retryInterval, (timer) {
      if (!_starterPickAckPending) {
        timer.cancel();
        return;
      }
      globalData.logger.i('no starterPickAck received yet, resending starterPick\n');
      sendGameCommand(opponentKey, 'starterPick', {'youStart': youStart});
    });
    _armStuckWatchdog(() => _starterPickAckPending, () => _starterPickAttempt(opponentKey, youStart));
  }

//-//////////////////////////////////////////////////////////////////////////////
  ///fireShot : send a shot and keep resending it every second until the matching
  ///'shotResult' arrives, so a lost 'shot'/'shotResult' packet can't leave both
  ///sides waiting on each other forever
  Future<void> fireShot(int row, int col) async {
    if (globalData.game.status != GameStatus.inGameMyStep || globalData.game.opponent == null) return;
    if (globalData.game.pendingShotRow != null) return; //already waiting for a result

    final opponentKey = globalData.game.opponent!.publicKey;
    globalData.game.pendingShotRow = row;
    globalData.game.pendingShotCol = col;
    await _shotAttempt(opponentKey, row, col);
  }

  Future<void> _shotAttempt(String opponentKey, int row, int col) async {
    await sendGameCommand(opponentKey, 'shot', {'row': row, 'col': col});
    shotRetryTimer?.cancel();
    shotRetryTimer = Timer.periodic(_retryInterval, (timer) {
      if (globalData.game.pendingShotRow != row || globalData.game.pendingShotCol != col) {
        timer.cancel();
        return;
      }
      globalData.logger.i('no shotResult received yet, resending shot $row,$col\n');
      sendGameCommand(opponentKey, 'shot', {'row': row, 'col': col});
    });
    _armStuckWatchdog(
        () => globalData.game.pendingShotRow == row && globalData.game.pendingShotCol == col,
        () => _shotAttempt(opponentKey, row, col));
  }

//-//////////////////////////////////////////////////////////////////////////////
  ///sendGameCommand : send a JSON payload (shot coordinates, results, ...) to a known online bro
  Future<void> sendGameCommand(String publicKey, String command, Map<String, dynamic> payload) async {
    try {
      final bro = broGroup.getBroByKey(publicKey);
      if (bro == null || !bro.isOnline()) return;
      await sendCommand(json.encode(payload), bro.ipAdress, command);
    } catch (e) {
      globalData.logger.e('Error sendGameCommand ${e.toString()}\n');
    }
  }

//-//////////////////////////////////////////////////////////////////////////////
  Future<void> startMyServices() async {
    globalData.logger.i('startMyServices()\n');
    try {
      loopTimer?.cancel();
      udpListenSocket?.close();
      loopTimer = null;
      udpListenSocket = null;

      udpListenSocket = await startUDPListener();
      if (udpListenSocket == null) {
        globalData.logger.i('udpListenSocket == null fatal error \n');
        exit(0);

        //throw Exception('udpListenSocket == null');
      }

      //send ping to all, i am online
      pingMe();

      loopTimer = Timer.periodic(Duration(seconds: timerInterval), loopCallback);
    } catch (e) {
      globalData.logger.e('Error startMyServices ${e.toString()}\n');
    }
  }

//-//////////////////////////////////////////////////////////////////////////////
  /// loopCallback : runs every timerInterval seconds <br>
  /// - sends our own heartbeat broadcast, so bros know we are still online <br>
  /// - three-stage presence check on known bros: <br>
  ///   - fresh (pinged within timerInterval): still online, nothing to do <br>
  ///   - grace (pinged within timerInterval * 2): missed one heartbeat, probe directly once (onHold) <br>
  ///   - stale (older than timerInterval * 2): missed the direct probe too, drop the bro
  void loopCallback(dynamic timer) async {
    try {
      //send heartbeat broadcast, i am (still) online
      pingMe();

      List<Bro> brosToRemove = [];
      for (var bro in broGroup.bros) {
        if (bro.ipAdress.isEmpty) continue;

        if (bro.isLastPing(timerInterval)) {
          //fresh heartbeat received, still online
          continue;
        }

        if (bro.isLastPing(timerInterval * 2)) {
          //missed one heartbeat - give it one direct chance before giving up
          if (!bro.isOnHold()) {
            bro.setOnHold();
            globalData.logger.i('bro ${bro.name} missed a heartbeat, probing directly\n');
            pingMe(ipAdress: bro.ipAdress);
            notifyListeners();
          }
        } else {
          //missed the direct probe too - consider it gone
          if (bro.isOnline() || bro.isOnHold()) {
            globalData.logger.i('bro ${bro.name} has not pinged me in ${timerInterval * 2} seconds\n');
            brosToRemove.add(bro);
          }
        }
      }
      if (brosToRemove.isNotEmpty) {
        broGroup.bros.removeWhere((bro) => brosToRemove.contains(bro));
        notifyListeners();
      }
    } catch (e) {
      globalData.logger.e('Error loopCallback ${e.toString()}\n');
    }
  }

//-//////////////////////////////////////////////////////////////////////////////
  // Command? getCommandByID(String iID)
  /// select and sort elementes from id <br>
  /// concatinate sclices to command data <br>
  /// convert concatinated data to command by json string
  Command? getCommandByID(String iID, String iIp) {
    ///select and sort elementes from id
    List<UdpSliceBuffer> mySclices =
        udpSlicesBuffer.where((a) => a.item.id == iID).toList().where((b) => b.ip == iIp).toList();
    mySclices.sort((a, b) => a.item.nr.compareTo(b.item.nr));

    var lData = '';
    var lComplete = false;

    ///concatinate sclices to command data
    for (var i = 0; i < mySclices.length; i++) {
      lData = lData + mySclices[i].item.data;
      if (mySclices[i].item.nr != i) return null; // continue number missing
      if (mySclices[i].item.count == mySclices[i].item.nr) //last element  found
      {
        lComplete = true;
      } else {
        lComplete = false;
      }
    }
    if (lComplete) {
      ///convert concatinated data to command by json string
      return Command.fromJson(json.decode(lData));
    }
    return null;
  }

//-//////////////////////////////////////////////////////////////////////////////
  /// start UDP listener <br>
  /// listen for broadcast response <br>
  /// added to udpSlices and execute command if found
  Future<RawDatagramSocket?> startUDPListener() async {
    //start listener

    try {
      var mySocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, myPort);

      mySocket.broadcastEnabled = true;

      //listen for broadcast response
      mySocket.listen((e) async {
        try {
          if (e == RawSocketEvent.read) {
            Datagram? dg = mySocket.receive();
            if (dg != null) {
              var lSclice = UdpSlice.fromJson(json.decode(utf8.decode(dg.data)));
              //globalData.logger.i("received sclice id:${lSclice.id}/nr:${lSclice.nr}/count:${lSclice.count}\n");
              udpSlicesBuffer.add(UdpSliceBuffer(item: lSclice, ip: dg.address.address, timestamp: DateTime.now()));
              //delete older sclices
              udpSlicesBuffer.removeWhere(
                  (element) => element.timestamp.isBefore(DateTime.now().subtract(const Duration(minutes: 2))));

              var lCommand = getCommandByID(lSclice.id, dg.address.address);

              if (lCommand != null) {
                executeCommand(lCommand, dg.address.address); //execute command
                udpSlicesBuffer
                    .removeWhere((itemBuffer) => itemBuffer.item.id == lSclice.id); //remove sclice of valide command
              }
            }
          } else {
            globalData.logger.i("listen() event $e \n");
          }
        } catch (e) {
          globalData.logger.e("listen() Socket.receive() error ${e.toString()}\n");
        }
      }, onDone: () {
        globalData.logger.i("listen() onDone \n");
      }, onError: (e) {
        globalData.logger.e("listen() onError ${e.toString()}\n");
      }, cancelOnError: false);

      return mySocket;
    } catch (e) {
      globalData.logger.e('startUDPListener() Error udp socket ${e.toString()}\n');
    }
    return null;
  }

//-//////////////////////////////////////////////////////////////////////////////
  Future<void> sendCommand(String iData, String ipAdress, String iCommand) async {
    try {
      udpListenSocket == null ? await startUDPListener() : null;

      if (iData.isEmpty || globalData.settings.publicKey.isEmpty || udpListenSocket == null) {
        throw Exception('iData is empty or me.publicKey or udpListenSocket is null');
      }

      var myBroMessage = BroMessage(
        publicKey: globalData.settings.publicKey,
        timestamp: DateTime.now(),
        message: iData,
      );
      var myCommand = Command(command: iCommand, data: json.encode(myBroMessage));

      var lSlices = myCommand.getUdpSlices();
      var lLength = 0 as num;
      for (var i = 0; i < lSlices.length; i++) {
        var myData = utf8.encode(json.encode(lSlices[i].toJson()));
        //globalData.logger.i('sent $iCommand slice ${i + 1}/${lSlices[i].id}/${lSlices[i].nr}/${lSlices[i].count}\n');
        //globalData.logger.i('sent $iCommand slice ${utf8.decode(myData)}\n');
        lLength += udpListenSocket?.send(myData, InternetAddress(ipAdress), myPort) as num;
      }

      if (iCommand != 'ping_me') {
        globalData.logger.i('sent $iCommand to $ipAdress:$myPort length $lLength in ${lSlices.length + 1} slices\n');
      }
    } catch (e) {
      globalData.logger.e('Error sendCommand() ${e.toString()}\n');
    }
  }

//-//////////////////////////////////////////////////////////////////////////////
  /// executeCommand ping_me, message_bro, candidate_?_pc, desc_offer_?_pc, desc_answer_?_pc
  Future<void> executeCommand(Command lCommand, String ipAdress) async {
    try {
      //if (lCommand.command != 'ping_me') globalData.logger.i("received command ${lCommand.command} from $ipAdress\n");

      /// ping_me ------------------------------------------------
      if (lCommand.command == 'ping_me') {
        var lMessage = BroMessage.fromJson(json.decode(lCommand.data));
        var lBro = Bro.fromJson(json.decode(lMessage.message));
        //globalData.logger.i('ping_me Bro data: \n${json.decode(lCommand.data)} \n${lBro.toJson()}\n from $ipAdress\n');
        if (lBro.publicKey.isEmpty || lBro.publicKey != lMessage.publicKey) {
          throw Exception('listen() data unvalid');
        }

        if (globalData.settings.publicKey != lBro.publicKey) {
          // if (noGroup.getBroByKey(lBro.publicKey) != null) {
          //   //ignore bro
          //   return;
          // }

          //globalData.logger.i("received command ${lCommand.command}  name ${lBro.name} from $ipAdress\n");

          // resiving a bro from someone else
          var lBroIndex = broGroup.getBroIndexByKey(lBro.publicKey);
          if (lBroIndex != null) {
            //this bro is known and myBro
            broGroup.bros[lBroIndex].ipAdress = ipAdress;
            broGroup.bros[lBroIndex].name = lBro.name;
            broGroup.bros[lBroIndex].color = lBro.color;
            broGroup.bros[lBroIndex].pic = lBro.pic;
            broGroup.bros[lBroIndex].myAppLifecycleState = lBro.myAppLifecycleState;
            broGroup.bros[lBroIndex].opponentName = lBro.opponentName;
            if (broGroup.bros[lBroIndex].myStatus != Status.online) {
              await broGroup.broIsOnline(broGroup.bros[lBroIndex]);
              //setState(() {});
              notifyListeners();
            } else {
              await broGroup.broIsOnline(broGroup.bros[lBroIndex]);
              //setState(() {});
              notifyListeners();
            }
          } else {
            //this bro is unknown - push it in broGroup
            lBro.myStatus = Status.offline;
            lBro.ipAdress = ipAdress;
            //lBro.setParentFunction(setState, sendCommand);
            broGroup.addBro(lBro);
            await broGroup.broIsOnline(lBro);
            //setState(() {});
            notifyListeners();
            pingMe(ipAdress: ipAdress);
          }
        }

        /// messageBro ------------------------------------------------
      } else if (lCommand.command == 'message_bro') {
        //globalData.logger.i(
        //    "received ${lCommand.command} data ${lCommand.data}\n");

        var lMessage = BroMessage.fromJson(json.decode(lCommand.data));
        var lBroIndex = broGroup.getBroIndexByKey(lMessage.publicKey);

        if (lBroIndex != null) {
          //myMessageList.insert(0, lMessage);
          if (broGroup.bros[lBroIndex].isOnline() != true) {
            await broGroup.broIsOnline(broGroup.bros[lBroIndex]);
            notifyListeners();
          }

          //if (myAppLifecycleState != AppLifecycleState.resumed && //
          //    ringerStatus != RingerModeStatus.silent) {
          //the App is not in foreground
          // globalData.logger.i('App state is: $myAppLifecycleState\n');

          // var lNoSound = ringerStatus == RingerModeStatus.normal;
          // globalData.logger.i('ringerStatus $ringerStatus lNoSound $lNoSound\n');
          // var lSoundValue = widget.me.valueAlarm ?? 0.8;
          // if (lNoSound) {
          //   lSoundValue = 0.0;
          // }

          // Alarm.set(
          //     alarmSettings: AlarmSettings(
          //   id: 42,
          //   dateTime: DateTime.now(),
          //   assetAudioPath: 'assets/YIPPY.mp3',
          //   loopAudio: false,
          //   vibrate: true,
          //   volume: lSoundValue, //default
          //   fadeDuration: 3.0,
          //   notificationTitle: 'CatShip',
          //   notificationBody: '... is ringing You!',
          //   enableNotificationOnKill: false,
          // )).then((value) {
          //   //Future.delayed(const Duration(seconds: 3), () => Alarm.stop(42));
          // });

          // // The one second delay is needed to get accurate results on IOS...
          // Future.delayed(const Duration(seconds: 1), () async {
          //   try {
          //     ringerStatus = await SoundMode.ringerModeStatus;
          //   } catch (err) {
          //     ringerStatus = RingerModeStatus.unknown;
          //   }
          //   globalData.logger.i('delayed SoundMode status $ringerStatus\n');
          // });
          //}

          //setState(() {});
        }

        /// startRequest ------------------------------------------------
      } else if (lCommand.command == 'startRequest') {
        globalData.logger.i('received ${lCommand.command} data ${lCommand.data}\n');

        var lMessage = BroMessage.fromJson(json.decode(lCommand.data));
        var lBroIndex = broGroup.getBroIndexByKey(lMessage.publicKey);

        if (lBroIndex != null) {
          if (broGroup.bros[lBroIndex].isOnline() != true) {
            await broGroup.broIsOnline(broGroup.bros[lBroIndex]);
          }
          broGroup.bros[lBroIndex].lastRequest = DateTime.now();
          broGroup.bros[lBroIndex].myStatus = Status.online;
          broGroup.bros[lBroIndex].lastCommand = lCommand.command;
          globalData.game.changeStatusByCommand(1, lCommand.command);
          globalData.logger.i('broGroup.bros[lBroIndex].lastRequest ${broGroup.bros[lBroIndex].lastRequest}\n');
          notifyListeners();
        } else {
          globalData.logger.i('bro not found\n');
        }

        /// goIn, deskReady ------------------------------------------------
      } else if (lCommand.command == 'goIn' || lCommand.command == 'deskReady') {
        var lMessage = BroMessage.fromJson(json.decode(lCommand.data));
        var lBroIndex = broGroup.getBroIndexByKey(lMessage.publicKey);

        if (lBroIndex != null) {
          //myMessageList.insert(0, lMessage);
          if (broGroup.bros[lBroIndex].isOnline() != true) {
            await broGroup.broIsOnline(broGroup.bros[lBroIndex]);
          }
          broGroup.bros[lBroIndex].lastRequest = null;
          broGroup.bros[lBroIndex].lastCommand = lCommand.command;
          if (lCommand.command == 'goIn') cancelAcceptTimer();
          globalData.game.changeStatusByCommand(1, lCommand.command);
          if (lCommand.command == 'deskReady') await resolveStarterIfNeeded();
          notifyListeners();
        }

        /// starterPick ------------------------------------------------
      } else if (lCommand.command == 'starterPick') {
        var lMessage = BroMessage.fromJson(json.decode(lCommand.data));
        if (globalData.game.opponent?.publicKey == lMessage.publicKey) {
          var payload = json.decode(lMessage.message) as Map<String, dynamic>;
          globalData.game.applyStarterPick(payload['youStart'] as bool);
          await sendGameCommand(lMessage.publicKey, 'starterPickAck', {});
          notifyListeners();
        }

        /// starterPickAck ------------------------------------------------
      } else if (lCommand.command == 'starterPickAck') {
        var lMessage = BroMessage.fromJson(json.decode(lCommand.data));
        if (globalData.game.opponent?.publicKey == lMessage.publicKey) {
          _starterPickAckPending = false;
          starterPickRetryTimer?.cancel();
          starterPickRetryTimer = null;
          _stuckWatchdog?.cancel();
          gameInterrupted = false;
          notifyListeners();
        }

        /// shot ------------------------------------------------
      } else if (lCommand.command == 'shot') {
        var lMessage = BroMessage.fromJson(json.decode(lCommand.data));
        if (globalData.game.opponent?.publicKey == lMessage.publicKey) {
          var payload = json.decode(lMessage.message) as Map<String, dynamic>;
          final row = payload['row'] as int;
          final col = payload['col'] as int;
          final hit = globalData.game.applyIncomingShot(row, col);
          final allSunk = globalData.game.allBoatsSunk();
          await sendGameCommand(lMessage.publicKey, 'shotResult', {'row': row, 'col': col, 'hit': hit, 'allSunk': allSunk});
          notifyListeners();
        }

        /// shotResult ------------------------------------------------
      } else if (lCommand.command == 'shotResult') {
        var lMessage = BroMessage.fromJson(json.decode(lCommand.data));
        if (globalData.game.opponent?.publicKey == lMessage.publicKey) {
          var payload = json.decode(lMessage.message) as Map<String, dynamic>;
          globalData.game
              .applyShotResult(payload['row'] as int, payload['col'] as int, payload['hit'] as bool, payload['allSunk'] as bool);
          shotRetryTimer?.cancel();
          shotRetryTimer = null;
          _stuckWatchdog?.cancel();
          gameInterrupted = false;
          notifyListeners();
        }

        /// exit ------------------------------------------------
      } else if (lCommand.command == 'exit') {
        globalData.logger.i('received ${lCommand.command} data ${lCommand.data}\n');

        var lMessage = BroMessage.fromJson(json.decode(lCommand.data));
        var lBroIndex = broGroup.getBroIndexByKey(lMessage.publicKey);

        if (lBroIndex != null) {
          if (broGroup.bros[lBroIndex].isOnline() != true) {
            await broGroup.broIsOnline(broGroup.bros[lBroIndex]);
          }
          broGroup.bros[lBroIndex].lastRequest = null;
          broGroup.bros[lBroIndex].myStatus = Status.online;
          broGroup.bros[lBroIndex].lastCommand = lCommand.command;
          cancelGameTimers();
          if (globalData.game.opponent?.publicKey == lMessage.publicKey) {
            globalData.game.clearGame();
          }
          globalData.logger.i('broGroup.bros[lBroIndex].lastRequest ${broGroup.bros[lBroIndex].lastRequest}\n');
          notifyListeners();
        } else {
          globalData.logger.i('bro not found\n');
        }

        /// candidate ------------------------------------------------
      } else {
        globalData.logger.i("do nothing with received ${lCommand.command} data ${lCommand.data}\n");
      }
    } catch (e) {
      globalData.logger.e('Error executeCommand ${e.toString()}');
    }
  }

//-//////////////////////////////////////////////////////////////////////////////
  Future<void> sendMessage(String iMessage, String? iKey, String? iCommand) async {
    try {
      udpListenSocket == null ? await startUDPListener() : null;

      if (iMessage.isEmpty || globalData.settings.publicKey.isEmpty || udpListenSocket == null) {
        return;
      }

      // globalData.logger.i('sendMessage() $iMessage\n');
      // var myBroMessage = BroMessage(
      //   publicKey: widget.me.publicKey,
      //   timestamp: DateTime.now(),
      //   message: iMessage,
      // );
      // var myCommand = Command(command: 'message_bro', data: json.encode(myBroMessage));
      // var myData = utf8.encode(json.encode(myCommand.toJson()));

      for (var bro in broGroup.bros) {
        if (iKey != null && iKey != bro.publicKey) {
          continue; //not this one
        }
        if (bro.isOnline()) {
          if (iCommand != null) {
            sendCommand(iCommand, bro.ipAdress, iCommand);
          } else {
            //udpListenSocket?.send(myData, InternetAddress(bro.ipAdress), myPort);
            sendCommand(iMessage, bro.ipAdress, 'message_bro');
          }
        }
      }
    } catch (e) {
      globalData.logger.e('sendMessage() Error ${e.toString()}\n');
      //globalData.logger.i('sendMessage() Error ${e.toString()}\n');
    }
  }

//-//////////////////////////////////////////////////////////////////////////////
  ///myPingPayload : my public identity plus who I'm currently playing with (if anyone),
  ///so other bros know I'm not available for a new game request
  Map<String, dynamic> myPingPayload() {
    var payload = Map<String, dynamic>.from(globalData.settings.toJsonPub(globalData.myAppLifecycleState));
    payload['opponent_name'] = globalData.game.status != GameStatus.idle ? (globalData.game.opponent?.name ?? '') : '';
    return payload;
  }

//-//////////////////////////////////////////////////////////////////////////////
  ///send ping to all, i am online
  void pingMe({String ipAdress = ''}) async {
    udpListenSocket == null ? await startUDPListener() : null;

    if (globalData.settings.publicKey.isEmpty || udpListenSocket == null) {
      //no me data for public key
      return;
    }
    //if (myAppLifecycleState != AppLifecycleState.resumed) {
    ////app has no focus
    ////return;
    //}

    if (ipAdress.isEmpty) {
      //send ping to all, i am online
      globalData.logger.i('pingMe() send ping to all, i am online\n');

      NetworkInterface.list().then((interfaces) async {
        try {
          for (var interface in interfaces) {
            if (interface.addresses.isNotEmpty) {
              for (var address in interface.addresses) {
                if (address.type == InternetAddressType.IPv4) {
                  //found an ip4 network

                  //build ip for broadcast
                  var ipParts = address.address.split('.');
                  if (ipParts.length == 4) {
                    var ip = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}.255';

                    //send broadcast
                    sendCommand(json.encode(myPingPayload()), ip, 'ping_me');
                    //globalData.logger.i("sent ping_me ${widget.me.name}\n ${widget.me.toJsonPub(myAppLifecycleState)} bytes on $ip\n");
                  }
                }
              }
            }
          }
        } catch (e) {
          globalData.logger.e('Error udp socket ${e.toString()}\n');
        }
      });
    } else {
      ///send ping to ipAdress, i am online
      try {
        //send broadcast
        sendCommand(json.encode(myPingPayload()), ipAdress, 'ping_me');
        //globalData.logger.i("sent ping_me ${widget.me.name}\n ${widget.me.toJsonPub()} bytes on $ipAdress\n");
      } catch (e) {
        globalData.logger.e('Error udp socket ${e.toString()}\n');
      }
    }
  }
}
