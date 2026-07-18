import 'package:intl/intl.dart';
import 'package:cat_ship/data/game_data.dart';
import 'package:cat_ship/lib/udp_services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cat_ship/data/global_data.dart';
import 'package:cat_ship/data/icon_data.dart';
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
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

//-//////////////////////////////////////////////////////////////////////////////
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    globalData.myAppLifecycleState = state;
    globalData.logger.i('didChangeAppLifecycleState() - ${state.toString()}\n');

    if (state == AppLifecycleState.resumed) {
      //iOS/macOS can suspend or break the UDP socket while backgrounded; restarting
      //services rebuilds a fresh socket + heartbeat timer instead of a dead one
      await Provider.of<UdpServices>(context, listen: false).startMyServices();
    }
  }

  final timeFormat = DateFormat('HH:mm'); // 24-Stunden-Format
  bool _interruptedDialogShown = false;

  //-//////////////////////////////////////////////////////////////////////////////
  ///abort the current game in any phase after the request was accepted
  void _abortGame(UdpServices udpServices) {
    if (globalData.game.opponent != null) {
      udpServices.sendMessage('Hello !', globalData.game.opponent!.publicKey, 'exit');
    }
    udpServices.cancelGameTimers();
    globalData.game.clearGame();
    setState(() {});
  }

  //-//////////////////////////////////////////////////////////////////////////////
  Widget _cancelGameButton(UdpServices udpServices) {
    return TextButton(
      onPressed: () => _abortGame(udpServices),
      child: const Text('Abort game'),
    );
  }

  //-//////////////////////////////////////////////////////////////////////////////
  ///show a modal dialog once a shot/starterPick has gone unanswered for ~20s despite
  ///retrying every second - offers to keep retrying or abort the game
  void _showInterruptedDialogIfNeeded(BuildContext context, UdpServices udpServices) {
    if (!udpServices.gameInterrupted) {
      _interruptedDialogShown = false;
      return;
    }
    if (_interruptedDialogShown) return;
    _interruptedDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Spiel wurde unterbrochen'),
          content: const Text('Keine Antwort vom Mitspieler erhalten.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _interruptedDialogShown = false;
                udpServices.continueAfterInterruption();
                setState(() {});
              },
              child: const Text('Weiter'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _interruptedDialogShown = false;
                _abortGame(udpServices);
              },
              child: const Text('Spiel abbrechen'),
            ),
          ],
        ),
      );
    });
  }

  //-//////////////////////////////////////////////////////////////////////////////
  @override
  Widget build(BuildContext context) {
    return Consumer<UdpServices>(builder: (context, udpServices, child) {
      return Scaffold(
          // --------------- AppBar
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            leading: IconButton(
              onPressed: () async {
                //await startMyServices();
                udpServices.pingMe();
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
                    //globalData.logger.i('myData: ${myData?.toJson().toString()}\n');
                    if (myData != null &&
                        (globalData.settings.name != myData.name ||
                            globalData.settings.pic != myData.pic ||
                            globalData.settings.color != myData.color)) {
                      setState(() {
                        globalData.settings.setName(myData.name);
                        globalData.settings.setPic(myData.pic);
                        globalData.settings.setColor(myData.color);
                        globalData.settings.save();
                      });
                      // ignore: use_build_context_synchronously
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
          body: Center(
            child: Builder(builder: (context) {
              globalData.logMe(udpServices);
              _showInterruptedDialogIfNeeded(context, udpServices);

              if (udpServices.broGroup.bros.isEmpty) {
                return const Center(child: Text('no bros found - are you alone?'));
              } else
////////////////////////////////////////////////////////////////////////////////
              if (globalData.game.status == GameStatus.startRequestAndWait) {
                return Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  ElevatedButton(
                    style: styleButton,
                    onPressed: () {
                      udpServices.sendMessage('Hello !', globalData.game.opponent!.publicKey, 'exit');
                      udpServices.cancelGameTimers();
                      globalData.game.clearGame();
                      setState(() {});
                    },
                    child: const Icon(Icons.cancel, color: Colors.red),
                  ),
                  const Text('request to bro to start game ... please wait (~20s)!')
                ]));
              } else
////////////////////////////////////////////////////////////////////////////////
              if (globalData.game.status == GameStatus.buildMyDeskAndWait || //both still placing boats
                  globalData.game.status == GameStatus.buildMyDesk) {
                //opponent is already waiting for buildMyDesk
                final placed = globalData.game.getCount(bootFeld);
                final ready = placed == boatCount;
                return Center(
                    child: SingleChildScrollView(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  globalData.game.buildMatrix(setState),
                  Text('place your boats ($placed/$boatCount)'),
                  ElevatedButton(
                    onPressed: ready
                        ? () {
                            udpServices.sendMessage('Hello !', globalData.game.opponent!.publicKey, 'deskReady');
                            globalData.game.status = globalData.game.status == GameStatus.buildMyDeskAndWait
                                ? GameStatus.waitRemoteDesk
                                : GameStatus.inGame;
                            udpServices.resolveStarterIfNeeded();
                            setState(() {});
                          }
                        : null,
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.check_circle),
                      Text(' Ready')
                    ]),
                  ),
                  _cancelGameButton(udpServices),
                ])));
              } else if (globalData.game.status == GameStatus.waitRemoteDesk) {
                return Center(
                    child: SingleChildScrollView(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  globalData.game.buildMatrix(setState, readOnly: true),
                  const Text('board ready - waiting for opponent ...'),
                  _cancelGameButton(udpServices),
                ])));
              } else {
////////////////////////////////////////////////////////////////////////////////
                if (globalData.game.status == GameStatus.inGameMyStep || //me and opponent play game
                    globalData.game.status == GameStatus.inGameRemoteStep) {
                  return Padding(
                      padding: const EdgeInsets.all(3.0),
                      child: SingleChildScrollView(
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(globalData.game.status == GameStatus.inGameMyStep
                            ? 'Your turn - fire at the enemy grid!'
                            : 'Waiting for opponent to fire ...'),
                        const Text('Enemy board:'),
                        globalData.game.buildShootMatrix(setState, udpServices),
                        const SizedBox(height: 12),
                        const Text('Your board:'),
                        globalData.game.buildMatrix(setState, readOnly: true),
                        Text('Score - you: ${globalData.game.myScore}  opponent: ${globalData.game.remoteScore}'),
                        _cancelGameButton(udpServices),
                      ])));
                }
////////////////////////////////////////////////////////////////////////////////
                if (globalData.game.status == GameStatus.inGameFinish) {
                  final won = globalData.game.iWon == true;
                  return Padding(
                      padding: const EdgeInsets.all(3.0),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(won ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                            size: 64, color: won ? Colors.amber : Colors.grey),
                        Text(won ? 'You won!' : 'You lost!'),
                        Text('Score - you: ${globalData.game.myScore}  opponent: ${globalData.game.remoteScore}'),
                        ElevatedButton(
                          onPressed: () => _abortGame(udpServices),
                          child: const Text('Back to lobby'),
                        ),
                      ]));
                }
////////////////////////////////////////////////////////////////////////////////
                // game.status == GameStatus.idle
                return Padding(
                    padding: const EdgeInsets.all(3.0),
                    child: ListView.builder(
                      itemCount: udpServices.broGroup.bros.length,
                      itemBuilder: (context, index) {
                        return Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.all(Radius.circular(3)),
                              color: udpServices.broGroup.bros[index].getOnlineColor(),

                              //Theme.of(context).colorScheme.inversePrimary,
                            ),
                            child: Padding(
                                padding: const EdgeInsets.all(3.0),
                                child: Row(children: <Widget>[
                                  ClipOval(
                                      child: Image.asset(
                                    PngLib.getPngByName(udpServices.broGroup.bros[index].pic).path,
                                    width: 30,
                                  )),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(udpServices.broGroup.bros[index].getName(20)),
                                        if (udpServices.broGroup.bros[index].lastRequest != null)
                                          Text(timeFormat.format(udpServices.broGroup.bros[index].lastRequest!)),
                                        //Text(udpServices.broGroup.bros[index].ipAdress),
                                      ],
                                    ),
                                  ),

                                  //tileColor: udpServices.broGroup.bros[index].getOnlineColor(),

                                  if (udpServices.broGroup.bros[index].isOnline() &&
                                      udpServices.broGroup.bros[index].isBusy() &&
                                      udpServices.broGroup.bros[index].lastRequest == null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8.0),
                                      child: Text('playing with ${udpServices.broGroup.bros[index].opponentName}'),
                                    )
                                  else if (udpServices.broGroup.bros[index].isOnline() &&
                                      (udpServices.broGroup.bros[index].lastRequest == null
                                      //||                                          DateTime.now()
                                      //            .difference(udpServices.broGroup.bros[index].lastRequest!)
                                      //            .inSeconds <
                                      //        60
                                      ))
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        //primary: Colors.white, // Hintergrundfarbe des Buttons
                                        //onPrimary: Colors.black, // Textfarbe
                                        side: const BorderSide(color: Colors.white, width: 2), // Rahmen
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10), // Abgerundete Ecken
                                        ),
                                      ),
                                      onPressed: () {
                                        globalData.game.newGame(udpServices.broGroup.bros[index], GameStarter.remote);
                                        globalData.game.status = GameStatus.startRequestAndWait;
                                        udpServices.sendMessage(
                                            'Hello !', udpServices.broGroup.bros[index].publicKey, 'startRequest');
                                        udpServices.startAcceptTimer();
                                        setState(() {});
                                      },
                                      child: const Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: <Widget>[
                                            Padding(
                                                padding: EdgeInsets.all(3.0), //
                                                child: Icon(Icons.connect_without_contact)), //
                                            Text("Start Request")
                                          ]),
                                    )
                                  else if (udpServices.broGroup.bros[index].isOnline())
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        //primary: Colors.white, // Hintergrundfarbe des Buttons
                                        //onPrimary: Colors.black, // Textfarbe
                                        side: const BorderSide(color: Colors.white, width: 2), // Rahmen
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10), // Abgerundete Ecken
                                        ),
                                      ),
                                      onPressed: () {
                                        globalData.game.newGame(udpServices.broGroup.bros[index], GameStarter.me);
                                        globalData.game.status = GameStatus.buildMyDeskAndWait;
                                        udpServices.sendMessage(
                                            'Hello !', udpServices.broGroup.bros[index].publicKey, 'goIn');
                                        setState(() {});
                                      },
                                      child: const Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: <Widget>[
                                            Padding(padding: EdgeInsets.all(3.0), child: Icon(Icons.flag)),
                                            Text("Yes Go In")
                                          ]),
                                    ),
                                ])));
                      },
                    ));
              }
            }),
          ));
    });
  }
}
