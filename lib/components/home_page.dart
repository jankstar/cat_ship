import 'package:cat_ship/data/udp_services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:cat_ship/data/settings.dart';
import 'package:cat_ship/data/icon_lib.dart';
import 'package:cat_ship/components/setting_dialog.dart';

Data globalData = Data();

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  //-//////////////////////////////////////////////////////////////////////////////
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
  }

  //-//////////////////////////////////////////////////////////////////////////////
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

//-//////////////////////////////////////////////////////////////////////////////
  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    //stdout.write('didChangeDependencies name: ${widget.me.name} state: ${myAppLifecycleState.toString()}\n');

    // if (udpListenSocket == null && myAppLifecycleState == AppLifecycleState.resumed) {
    //   await startMyServices();
    //   stdout.write('didChangeDependencies() - startMyServices()\n');
    // }
  }

//-//////////////////////////////////////////////////////////////////////////////
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    globalData.myAppLifecycleState = state;
    stdout.write('didChangeAppLifecycleState() - ${state.toString()}\n');

    // if (udpListenSocket == null && state == AppLifecycleState.inactive) {
    //   ///cancel the timer
    //   loopTimer?.cancel();
    //   loopTimer = null;
    //   // Clean up the listener when the widget is disposed.
    //   udpListenSocket?.close();
    //   udpListenSocket = null;
    //   stdout.write('didChangeAppLifecycleState() - close socket and timer\n');
    //   if (iAmIn) {
    //     iAmIn = false;
    //     //stopVideo();
    //   }
    //   try {
    //     for (var i = 0; i < broGroup.bros.length; i++) {
    //       //await broGroup.bros[i].stopAllPCs();
    //       //await broGroup.bros[i].initPCs();
    //     }
    //     broGroup.bros = [];
    //   } catch (e) {
    //     stdout.write('didChangeAppLifecycleState() error: ${e.toString()}\n');
    //   }
    // }

    // if (state == AppLifecycleState.resumed) {
    //   if (udpListenSocket == null) {
    //     await startMyServices();
    //   } //else {
    //   pingMe();
    //   //}
    // }
  }

  //-//////////////////////////////////////////////////////////////////////////////
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // --------------- AppBar
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          onPressed: () async {
            //await startMyServices();
            //pingMe();
            // ignore: use_build_context_synchronously
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ping to everyone ...')),
            );
          },
          icon: ClipOval(
            child: Image.asset(
              PngLib.getPngByName(globalData.settings.pic).path,
              fit: BoxFit.cover,
            ),
          ),
        ),
        title: Text('Hi ${globalData.settings.name}'),
        actions: <Widget>[
          //IconButton settings
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'edit settings',
            onPressed: () {
              SettingDialog.showDialogText(context, globalData.settings).then((myData) {
                //stdout.write('myData: ${myData?.toJson().toString()}\n');
                if (myData != null && (globalData.settings.name != myData.name || globalData.settings.pic != myData.pic || globalData.settings.color != myData.color)) {
                  setState(() {
                    globalData.settings.setName(myData.name);
                    globalData.settings.setPic(myData.pic);
                    globalData.settings.setColor(myData.color);
                    globalData.settings.save();
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hi ${globalData.settings.name} - data saved, you are ready!')),
                  );
                }
              });
            },
          ),
        ],
      ),
// --------------- body
      body: Center(child: Consumer<UdpServices>(
        builder: (context, udpServices, child) {
          if (udpServices.broGroup.bros.isEmpty) {
            return const Center(child: Text('no bros found - are you alone?'));
          }
          return ListView.builder(
            itemCount: udpServices.broGroup.bros.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(udpServices.broGroup.bros[index].getName(20)),
                subtitle: Text(udpServices.broGroup.bros[index].ipAdress),
              );
            },
          );
        },
      )),
    );
  }
}
