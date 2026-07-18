import 'package:flutter/material.dart';
import 'package:cat_ship/lib/udp_services.dart';
import 'package:cat_ship/data/bro_data.dart';

enum GameStatus {
  idle, //nothin to do
  startRequestAndWait, //request to bro to start game
  buildMyDeskAndWait, //build my desk and wait
  buildMyDesk, //build my desk for game
  waitRemoteDesk, //wait for remote desk
  inGame, //in game before set step
  inGameMyStep, //in game and my step
  inGameRemoteStep, //in game and remote step
  inGameFinish, //in game and finish
}

enum GameStarter {
  me,
  remote,
}

const String leeresFeld = '.';
const String trefferFeld = 'T';
const String bootFeld = 'B';
const String verfehltFeld = 'X';
const int matrixSize = 10;
const int boatCount = 5;
const double fieldSize = 28.0;

List<List<String>> buildCharMatrix(int rows, int cols, String defaultChar) {
  return List.generate(rows, (i) => List.generate(cols, (j) => defaultChar));
}

final ButtonStyle styleButton = ElevatedButton.styleFrom(
  padding: const EdgeInsets.all(0.0),
  minimumSize: Size.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.zero, // Keine abgerundeten Ecken
  ),
);

Icon getIconByField(String iField) {
  switch (iField) {
    case bootFeld:
      return const Icon(Icons.sailing, color: Colors.green);
    case trefferFeld:
      return const Icon(Icons.arrow_circle_down, color: Colors.red);
    case verfehltFeld:
      return const Icon(Icons.close, color: Colors.blueGrey);
    default:
      //leeresFeld
      return const Icon(Icons.snowing, color: Colors.grey);
  }
}

class Game {
  GameStatus status;
  int conter;
  List<List<String>> myMatrix;
  List<List<String>> remoteMatrix;
  Bro? opponent;
  GameStarter? starter;
  int myScore = 0;
  int remoteScore = 0;
  bool? iWon;
  int? pendingShotRow;
  int? pendingShotCol;

  Game({required this.status, required this.conter, required this.myMatrix, required this.remoteMatrix});

  factory Game.init() {
    return Game(
        status: GameStatus.idle,
        conter: 0,
        myMatrix: buildCharMatrix(matrixSize, matrixSize, '.'),
        remoteMatrix: buildCharMatrix(matrixSize, matrixSize, '.'));
  }

  Widget buildMatrix(void Function(void Function()) callBack, {bool readOnly = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
      Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(globalData.game.myMatrix.length, (i) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(globalData.game.myMatrix[i].length, (j) {
                //
                return Padding(
                  padding: const EdgeInsets.all(1.5),
                  child: SizedBox(
                    width: fieldSize,
                    height: fieldSize,
                    child: ElevatedButton(
                      style: styleButton,
                      onPressed: readOnly
                          ? null
                          : () {
                              if (globalData.game.myMatrix[i][j] == leeresFeld) {
                                if (globalData.game.getCount(bootFeld) == boatCount) {
                                  return;
                                }
                                globalData.game.myMatrix[i][j] = bootFeld;
                              } else {
                                globalData.game.myMatrix[i][j] = leeresFeld;
                              }
                              globalData.logger.i('Button $i, $j pressed');
                              callBack(() {});
                              //setState(() {});
                            },
                      child: getIconByField(globalData.game.myMatrix[i][j]),
                    ),
                  ),
                );
              }),
            );
          })),
    ]);
  }

  ///buildShootMatrix : clickable enemy grid, shoot when it is my turn
  Widget buildShootMatrix(void Function(void Function()) callBack, UdpServices udpServices) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
      Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(remoteMatrix.length, (i) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(remoteMatrix[i].length, (j) {
                final canShoot = status == GameStatus.inGameMyStep &&
                    opponent != null &&
                    remoteMatrix[i][j] == leeresFeld &&
                    pendingShotRow == null;
                return Padding(
                  padding: const EdgeInsets.all(1.5),
                  child: SizedBox(
                    width: fieldSize,
                    height: fieldSize,
                    child: ElevatedButton(
                      style: styleButton,
                      onPressed: canShoot
                          ? () {
                              udpServices.fireShot(i, j);
                              callBack(() {});
                            }
                          : null,
                      child: getIconByField(remoteMatrix[i][j]),
                    ),
                  ),
                );
              }),
            );
          })),
    ]);
  }

  void clearGame() {
    status = GameStatus.idle;
    conter = 0;
    myMatrix = buildCharMatrix(matrixSize, matrixSize, '.');
    remoteMatrix = buildCharMatrix(matrixSize, matrixSize, '.');
    opponent = null;
    starter = null;
    myScore = 0;
    remoteScore = 0;
    iWon = null;
    pendingShotRow = null;
    pendingShotCol = null;
  }

  void changeStatusByCommand(int iMode, String iCommand) {
    globalData.logger.i('changeStatusByCommand iMode $iMode iCommand $iCommand');
    if (iMode == 0) {
      //mode sending
    } else {
      //mode receive
      if (status == GameStatus.idle) {
        if (iCommand == 'startRequest') {
          status = GameStatus.idle;
        }
      } else if (status == GameStatus.startRequestAndWait) {
        if (iCommand == 'goIn') {
          status = GameStatus.buildMyDeskAndWait;
        }
      } else if (status == GameStatus.buildMyDeskAndWait) {
        if (iCommand == 'deskReady') {
          status = GameStatus.buildMyDesk;
        }
      } else if (status == GameStatus.buildMyDesk) {
        if (iCommand == 'deskReady') {
          status = GameStatus.inGame;
        }
      } else if (status == GameStatus.waitRemoteDesk) {
        if (iCommand == 'deskReady') {
          status = GameStatus.inGame;
        }
      }
    }
  }

  void newGame(Bro iBro, GameStarter iStarter) {
    clearGame();
    status = GameStatus.startRequestAndWait;
    opponent = iBro;
    starter = iStarter;
  }

  ///amIStarterPicker : deterministic tie-break so exactly one side picks the random starter <br>
  ///both devices know both public keys already, so this needs no extra handshake
  bool amIStarterPicker() {
    if (opponent == null) return false;
    return globalData.settings.publicKey.compareTo(opponent!.publicKey) < 0;
  }

  ///allBoatsSunk : true once all of my own boats have been hit
  bool allBoatsSunk() {
    return getCount(bootFeld) == 0;
  }

  ///applyIncomingShot : defender side, mark the shot on myMatrix and return whether it was a hit
  bool applyIncomingShot(int row, int col) {
    if (myMatrix[row][col] == trefferFeld || myMatrix[row][col] == verfehltFeld) {
      return myMatrix[row][col] == trefferFeld; //already resolved, ignore duplicate
    }
    final hit = myMatrix[row][col] == bootFeld;
    myMatrix[row][col] = hit ? trefferFeld : verfehltFeld;
    if (hit) remoteScore += 1;
    if (allBoatsSunk()) {
      status = GameStatus.inGameFinish;
      iWon = false;
    } else {
      status = GameStatus.inGameMyStep;
    }
    return hit;
  }

  ///applyShotResult : shooter side, mark the result on remoteMatrix <br>
  ///arrival of this ack is what actually passes the turn - the shot itself is
  ///retried by [UdpServices] until this is received, so a lost 'shot' or 'shotResult'
  ///packet can never leave both sides waiting on each other. <br>
  ///each cell can only ever be legitimately shot once, so a cell that's already marked
  ///means this is a late/duplicate ack for a shot we've already resolved (e.g. the
  ///retry fired again after the first ack was merely delayed, not lost) - it must be
  ///ignored completely, otherwise it would re-apply an old turn-pass onto whatever
  ///turn is actually current by now
  void applyShotResult(int row, int col, bool hit, bool allSunk) {
    if (remoteMatrix[row][col] != leeresFeld) return; //stale/duplicate ack - already resolved, ignore
    remoteMatrix[row][col] = hit ? trefferFeld : verfehltFeld;
    if (hit) myScore += 1;
    pendingShotRow = null;
    pendingShotCol = null;
    if (allSunk) {
      status = GameStatus.inGameFinish;
      iWon = true;
    } else if (status != GameStatus.inGameFinish) {
      status = GameStatus.inGameRemoteStep;
    }
  }

  ///applyStarterPick : apply the starter decision received from the picker <br>
  ///the picker retries this until acked, so a late/duplicate resend (e.g. because only
  ///the ack was lost, not the original pick) must be ignored once the starter is already
  ///decided - otherwise it would reset an already-progressed game back to the initial turn
  void applyStarterPick(bool youStart) {
    if (status != GameStatus.inGame) return; //already decided (or moved on) - ignore stale retransmission
    status = youStart ? GameStatus.inGameMyStep : GameStatus.inGameRemoteStep;
  }

  int getCountRemote(String iChar) {
    var count = 0;
    for (var i = 0; i < remoteMatrix.length; i++) {
      for (var j = 0; j < remoteMatrix[i].length; j++) {
        if (remoteMatrix[i][j] == iChar) {
          count += 1;
        }
      }
    }

    return count;
  }

  int getCount(String iChar) {
    var count = 0;
    for (var i = 0; i < myMatrix.length; i++) {
      for (var j = 0; j < myMatrix[i].length; j++) {
        if (myMatrix[i][j] == iChar) {
          count += 1;
        }
      }
    }

    return count;
  }

//
}
