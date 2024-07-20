import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cat_ship/data/settings.dart';
import 'package:flutter/material.dart';
import 'package:cat_ship/data/bro_data.dart';
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
    return UdpSlice(id: json['id'] as String, nr: json['nr'] as int, count: json['count'] as int, data: json['data'] as String);
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
        //stdout.write('getUdpClices slice ${i + 1}/${slices[i].id}/${slices[i].nr}/${slices[i].count}\n');
      }
    } catch (e) {
      stdout.write('Error getUdpClices ${e.toString()}\n');
    }
    return slices;
  }
}

class UdpServices with ChangeNotifier {
  final int timerInterval = 5;
  final int myPort = 54321;
  RawDatagramSocket? udpListenSocket;
  Timer? loopTimer;
  BroGroup broGroup = BroGroup();
  List<UdpSliceBuffer> udpSlicesBuffer = [];

//-//////////////////////////////////////////////////////////////////////////////
  Future<void> startMyServices() async {
    stdout.write('startMyServices()\n');
    try {
      loopTimer?.cancel();
      udpListenSocket?.close();
      loopTimer = null;
      udpListenSocket = null;

      udpListenSocket = await startUDPListener();
      if (udpListenSocket == null) {
        stdout.write('udpListenSocket == null fatal error \n');
        exit(0);

        //throw Exception('udpListenSocket == null');
      }

      //send ping to all, i am online
      pingMe();

      loopTimer = Timer.periodic(Duration(seconds: timerInterval), loopCallback);
    } catch (e) {
      stdout.write('Error startMyServices ${e.toString()}\n');
    }
  }

//-//////////////////////////////////////////////////////////////////////////////
  /// loopCallback : ping_me signal and check if bro has not pinged me in timerInterval * 2 seconds
  void loopCallback(dynamic timer) async {
    try {
      for (var i = 0; i < broGroup.bros.length; i++) {
        if (broGroup.bros[i].ipAdress.isNotEmpty) {
          ///request to all
          if (broGroup.bros[i].isLastPing(timerInterval * 2)) {
            Future.microtask(() => () {
                  pingMe(ipAdress: broGroup.bros[i].ipAdress);
                }());
          } else {
            if (broGroup.bros[i].isOnline()) {
              ///bro has not pinged me in timerInterval * 2 seconds
              stdout.write('bro ${broGroup.bros[i].name} has not pinged me in ${timerInterval * 2} seconds\n');
              broGroup.bros[i].setOffline();
              notifyListeners();
            }
          }
        }
      }
    } catch (e) {
      stdout.write('Error loopCallback ${e.toString()}\n');
    }
  }

//-//////////////////////////////////////////////////////////////////////////////
  // Command? getCommandByID(String iID)
  /// select and sort elementes from id <br>
  /// concatinate sclices to command data <br>
  /// convert concatinated data to command by json string
  Command? getCommandByID(String iID, String iIp) {
    ///select and sort elementes from id
    List<UdpSliceBuffer> mySclices = udpSlicesBuffer.where((a) => a.item.id == iID).toList().where((b) => b.ip == iIp).toList();
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
              //stdout.write("received sclice id:${lSclice.id}/nr:${lSclice.nr}/count:${lSclice.count}\n");
              udpSlicesBuffer.add(UdpSliceBuffer(item: lSclice, ip: dg.address.address, timestamp: DateTime.now()));
              //delete older sclices
              udpSlicesBuffer.removeWhere((element) => element.timestamp.isBefore(DateTime.now().subtract(const Duration(minutes: 2))));

              var lCommand = getCommandByID(lSclice.id, dg.address.address);

              if (lCommand != null) {
                executeCommand(lCommand, dg.address.address); //execute command
                udpSlicesBuffer.removeWhere((itemBuffer) => itemBuffer.item.id == lSclice.id); //remove sclice of valide command
              }
            }
          } else {
            stdout.write("listen() event $e \n");
          }
        } catch (e) {
          stdout.write("listen() Socket.receive() error ${e.toString()}\n");
        }
      }, onDone: () {
        stdout.write("listen() onDone \n");
      }, onError: (e) {
        stdout.write("listen() onError ${e.toString()}\n");
      }, cancelOnError: false);

      return mySocket;
    } catch (e) {
      stdout.write('startUDPListener() Error udp socket ${e.toString()}\n');
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
        //stdout.write('sent $iCommand slice ${i + 1}/${lSlices[i].id}/${lSlices[i].nr}/${lSlices[i].count}\n');
        //stdout.write('sent $iCommand slice ${utf8.decode(myData)}\n');
        lLength += udpListenSocket?.send(myData, InternetAddress(ipAdress), myPort) as num;
      }

      if (iCommand != 'ping_me') stdout.write('sent $iCommand to $ipAdress:$myPort length $lLength in ${lSlices.length + 1} slices\n');
    } catch (e) {
      stdout.write('Error sendCommand() ${e.toString()}\n');
    }
  }

//-//////////////////////////////////////////////////////////////////////////////
  /// executeCommand ping_me, message_bro, candidate_?_pc, desc_offer_?_pc, desc_answer_?_pc
  Future<void> executeCommand(Command lCommand, String ipAdress) async {
    try {
      if (lCommand.command != 'ping_me') stdout.write("received command ${lCommand.command} from $ipAdress\n");

      /// ping_me ------------------------------------------------
      if (lCommand.command == 'ping_me') {
        var lMessage = BroMessage.fromJson(json.decode(lCommand.data));
        var lBro = Bro.fromJson(json.decode(lMessage.message));
        //stdout.write('ping_me Bro data: \n${json.decode(lCommand.data)} \n${lBro.toJson()}\n from $ipAdress\n');
        if (lBro.publicKey.isEmpty || lBro.publicKey != lMessage.publicKey) {
          throw Exception('listen() data unvalid');
        }

        if (globalData.settings.publicKey != lBro.publicKey) {
          // if (noGroup.getBroByKey(lBro.publicKey) != null) {
          //   //ignore bro
          //   return;
          // }

          stdout.write("received command ${lCommand.command}  name ${lBro.name} from $ipAdress\n");

          // resiving a bro from someone else
          var lBroIndex = broGroup.getBroIndexByKey(lBro.publicKey);
          if (lBroIndex != null) {
            //this bro is known and myBro
            broGroup.bros[lBroIndex].ipAdress = ipAdress;
            broGroup.bros[lBroIndex].name = lBro.name;
            broGroup.bros[lBroIndex].color = lBro.color;
            broGroup.bros[lBroIndex].pic = lBro.pic;
            broGroup.bros[lBroIndex].myAppLifecycleState = lBro.myAppLifecycleState;
            if (broGroup.bros[lBroIndex].myStatus != Status.online) {
              await broGroup.broIsOnline(broGroup.bros[lBroIndex]);
              //setState(() {});
            } else {
              await broGroup.broIsOnline(broGroup.bros[lBroIndex]);
              //setState(() {});
            }
          } else {
            //this bro is unknown - push it in broGroup
            lBro.myStatus = Status.offline;
            lBro.ipAdress = ipAdress;
            //lBro.setParentFunction(setState, sendCommand);
            broGroup.addBro(lBro);
            await broGroup.broIsOnline(lBro);
            //setState(() {});
            pingMe(ipAdress: ipAdress);
          }
        }

        /// messageBro ------------------------------------------------
      } else if (lCommand.command == 'message_bro') {
        //stdout.write(
        //    "received ${lCommand.command} data ${lCommand.data}\n");

        var lMessage = BroMessage.fromJson(json.decode(lCommand.data));
        var lBroIndex = broGroup.getBroIndexByKey(lMessage.publicKey);

        if (lBroIndex != null) {
          //myMessageList.insert(0, lMessage);
          if (broGroup.bros[lBroIndex].isOnline() != true) {
            await broGroup.broIsOnline(broGroup.bros[lBroIndex]);
          }

          //if (myAppLifecycleState != AppLifecycleState.resumed && //
          //    ringerStatus != RingerModeStatus.silent) {
          //the App is not in foreground
          // stdout.write('App state is: $myAppLifecycleState\n');

          // var lNoSound = ringerStatus == RingerModeStatus.normal;
          // stdout.write('ringerStatus $ringerStatus lNoSound $lNoSound\n');
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
          //   stdout.write('delayed SoundMode status $ringerStatus\n');
          // });
          //}

          //setState(() {});
        }

        /// candidate ------------------------------------------------
      } else {
        stdout.write("received ${lCommand.command} data ${lCommand.data}\n");
      }
    } catch (e) {
      stdout.write('Error executeCommand ${e.toString()}\n');
    }
  }

//-//////////////////////////////////////////////////////////////////////////////
  Future<void> sendMessage(String iMessage) async {
    try {
      udpListenSocket == null ? await startUDPListener() : null;

      if (iMessage.isEmpty || globalData.settings.publicKey.isEmpty || udpListenSocket == null) {
        return;
      }

      // stdout.write('sendMessage() $iMessage\n');
      // var myBroMessage = BroMessage(
      //   publicKey: widget.me.publicKey,
      //   timestamp: DateTime.now(),
      //   message: iMessage,
      // );
      // var myCommand = Command(command: 'message_bro', data: json.encode(myBroMessage));
      // var myData = utf8.encode(json.encode(myCommand.toJson()));

      for (var bro in broGroup.bros) {
        if (bro.isOnline()) {
          //udpListenSocket?.send(myData, InternetAddress(bro.ipAdress), myPort);
          sendCommand(iMessage, bro.ipAdress, 'message_bro');
        }
      }
    } catch (e) {
      stdout.write('sendMessage() Error ${e.toString()}\n');
    }
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
      stdout.write('pingMe() send ping to all, i am online\n');

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
                    sendCommand(json.encode(globalData.settings.toJsonPub(globalData.myAppLifecycleState)), ip, 'ping_me');
                    //stdout.write("sent ping_me ${widget.me.name}\n ${widget.me.toJsonPub(myAppLifecycleState)} bytes on $ip\n");
                  }
                }
              }
            }
          }
        } catch (e) {
          stdout.write('Error udp socket ${e.toString()}\n');
        }
      });
    } else {
      ///send ping to ipAdress, i am online
      try {
        //send broadcast
        sendCommand(json.encode(globalData.settings.toJsonPub(globalData.myAppLifecycleState)), ipAdress, 'ping_me');
        //stdout.write("sent ping_me ${widget.me.name}\n ${widget.me.toJsonPub()} bytes on $ipAdress\n");
      } catch (e) {
        stdout.write('Error udp socket ${e.toString()}\n');
      }
    }
  }
}
