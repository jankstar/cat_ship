import 'package:flutter/material.dart';
import 'package:badges/badges.dart' as badges;
import 'package:cat_ship/data/icon_lib.dart';
import 'color_lib.dart';

enum Status {
  isNew, //unBro and new
  online, //bro is online
  offline, //bro is offline
  onHold, //bro is online but on hold
  blocked, //unBro and blocked
}

class BroMessage {
  String publicKey;
  DateTime timestamp;
  String message;
  BroMessage({required this.publicKey, required this.timestamp, required this.message});

  factory BroMessage.fromJson(Map<String, dynamic> json) {
    var timestampString = json['timestamp'] as String? ?? '';
    return BroMessage(publicKey: json['public_key'] as String? ?? '', timestamp: DateTime.parse(timestampString), message: json['message'] as String? ?? '');
  }

  Map<String, dynamic> toJson() => {
        'public_key': publicKey,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'message': message,
      };
}

///Bro object
class Bro {
  String publicKey;
  String name;
  String pic;
  String color;
  String ipAdress;
  DateTime? lastPing;
  Status? myStatus;
  AppLifecycleState? myAppLifecycleState;

//
  Bro(
      {required this.publicKey,
      required this.name,
      required this.pic,
      required this.color, //
      required this.ipAdress,
      this.myStatus = Status.offline,
      this.myAppLifecycleState = AppLifecycleState.inactive});

//
  factory Bro.fromJson(Map<String, dynamic> json) {
    var lAppLifState = AppLifecycleState.inactive;
    switch (json['lifecycle_state'] as String?) {
      case 'AppLifecycleState.inactive':
        lAppLifState = AppLifecycleState.inactive;
        break;
      case 'AppLifecycleState.active' || 'AppLifecycleState.resumed':
        lAppLifState = AppLifecycleState.resumed;
        break;
      case 'AppLifecycleState.paused':
        lAppLifState = AppLifecycleState.paused;
        break;
      case 'AppLifecycleState.detached':
        lAppLifState = AppLifecycleState.detached;
        break;
    }
    //stdout.write('lAppLifState $lAppLifState - ${json['lifecycle_state'] ?? 'null'}\n');
    return Bro(
        publicKey: json['public_key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        pic: json['pic'] as String? ?? '',
        color: json['color'] as String? ?? '',
        ipAdress: json['ip_adress'] as String? ?? '',
        myStatus: json['status'] as Status?,
        myAppLifecycleState: lAppLifState);
  }

//
  dispose() async {}

  ///isOnline : return true if bro is online
  bool isOnline() {
    return (myStatus != null && myStatus == Status.online);
  }

  setOnline() async {
    if (myStatus != Status.online) {
      myStatus = Status.online;
    }
    lastPing = DateTime.now();
  }

  setOffline() {
    myStatus = Status.offline;
    lastPing = null;
  }

  setAppLifecycleState(iAppLifecycleState) {
    myAppLifecycleState = iAppLifecycleState;
  }

  Color getOnlineColor() {
    if (myStatus == Status.online) {
      if (myAppLifecycleState == AppLifecycleState.resumed) {
        return Colors.green;
      }
      return Colors.yellow;
    }
    return Colors.red;
  }

  Color getMyColor() {
    return ColorLib.getColorByName(color).color;
  }

  String getName(iLen) {
    if (name.length > iLen) {
      return name.substring(0, iLen);
    }
    return name;
  }

  bool isOnHold() {
    return (myStatus == Status.onHold);
  }

  bool isBlocked() {
    return (myStatus == Status.blocked);
  }

  bool isLastPing(int iSec) {
    if (lastPing == null) {
      return false;
    }
    return (DateTime.now().difference(lastPing!).inSeconds < iSec);
  }

  Map toJson() {
    return {'public_key': publicKey, 'name': name, 'pic': pic, 'color': color, 'ip_adress': ipAdress, 'status': myStatus};
  }

//
}


class BroGroup {
  List<Bro> bros = [];
  BroGroup();
  Set<String> selection = {};

  String substringName(String iName) {
    if (iName.length > 4) {
      return iName.substring(0, 4);
    }
    return iName;
  }

  List<ButtonSegment<String>> getButtonSegmentList() {
    List<ButtonSegment<String>> myList = [];
    for (var i = 0; i < bros.length; i++) {
      myList.add(ButtonSegment(
          value: i.toString(),
          label: Column(children: [
            Text(substringName(bros[i].name), style: const TextStyle(fontSize: 8)),
            badges.Badge(
              badgeContent: const Text(''),
              badgeStyle: badges.BadgeStyle(
                badgeColor: bros[i].getOnlineColor(),
              ),
              position: badges.BadgePosition.topStart(top: -5, start: -10),
              child: ClipOval(
                child: Image.asset(
                  PngLib.getPngByName(bros[i].pic).path,
                  width: 30,
                  height: 30,
                  fit: BoxFit.cover,
                ),
              ),
            )
          ])));
    }

    return myList;
  }

  Bro? getBroByKey(String iKey) {
    for (var i = 0; i < bros.length; i++) {
      if (bros[i].publicKey == iKey) {
        //stdout.write('getBroByKey bro found index $i\n');
        return bros[i];
      }
    }
    //stdout.write('getBroByKey not bro found key: $iKey\n');
    return null;
  }

  int? getBroIndexByKey(String iKey) {
    for (var i = 0; i < bros.length; i++) {
      if (bros[i].publicKey == iKey) {
        //stdout.write('getBroByKey bro found index $i\n');
        return i;
      }
    }
    //stdout.write('getBroByKey not bro found key: $iKey\n');
    return null;
  }

  addBro(Bro iBro) {
    bros.add(iBro);

    ///new bro - add to selection
    selection.add((bros.length - 1).toString());
  }

  broIsOnline(Bro iBro) async {
    for (var i = 0; i < bros.length; i++) {
      if (bros[i].publicKey == iBro.publicKey) {
        // bros[i].ipAdress = iBro.ipAdress;
        // bros[i].name = iBro.name;
        // bros[i].pic = iBro.pic;
        // bros[i].color = iBro.color;
        await bros[i].setOnline();
        break;
      }
    }
  }

//-//////////////////////////////////////////////////////////////////////////////
}

