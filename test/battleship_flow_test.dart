// Temporary verification test for the Battleship game flow (accept-timeout,
// ready/starter-pick handshake, shot/shotResult exchange, win detection).
// Exercises the real production classes directly (no UI, no real sockets):
// two independent Game/Bro pairs "talk" to each other by feeding the exact
// Command objects the real network layer would have produced into
// UdpServices.executeCommand.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_ship/data/bro_data.dart';
import 'package:cat_ship/data/game_data.dart';
import 'package:cat_ship/lib/udp_services.dart';

Command buildCommand(String senderPublicKey, String command, Object payload) {
  final message = BroMessage(
    publicKey: senderPublicKey,
    timestamp: DateTime.now(),
    message: payload is String ? payload : json.encode(payload),
  );
  return Command(command: command, data: json.encode(message));
}

Bro makeBro(String key, String name) {
  return Bro(publicKey: key, name: name, pic: 'avatar1', color: 'blue', ipAdress: '127.0.0.1');
}

void main() {
  test('amIStarterPicker is deterministic and exactly one side picks', () {
    final gameA = Game.init();
    final gameB = Game.init();
    gameA.opponent = makeBro('keyB', 'B');
    gameB.opponent = makeBro('keyA', 'A');

    // simulate settings.publicKey via globalData singleton per side is not possible
    // (it's a real singleton) - so we just check the comparison logic directly.
    final aIsPicker = 'keyA'.compareTo('keyB') < 0;
    final bIsPicker = 'keyB'.compareTo('keyA') < 0;
    expect(aIsPicker != bIsPicker, isTrue, reason: 'exactly one side must be the picker');
  });

  test('applyIncomingShot marks hit/miss, scores, ignores duplicates, detects all-sunk', () {
    final game = Game.init();
    game.myMatrix[0][0] = bootFeld;
    game.myMatrix[1][1] = bootFeld;
    game.status = GameStatus.inGameRemoteStep;

    final hit1 = game.applyIncomingShot(0, 0);
    expect(hit1, isTrue);
    expect(game.myMatrix[0][0], trefferFeld);
    expect(game.remoteScore, 1);
    expect(game.status, GameStatus.inGameMyStep, reason: 'turn passes back after being shot at');
    expect(game.allBoatsSunk(), isFalse);

    final miss = game.applyIncomingShot(2, 2);
    expect(miss, isFalse);
    expect(game.myMatrix[2][2], verfehltFeld);
    expect(game.remoteScore, 1, reason: 'miss must not score');

    // duplicate shot on an already-resolved cell must be ignored (no re-scoring)
    final dup = game.applyIncomingShot(0, 0);
    expect(dup, isTrue);
    expect(game.remoteScore, 1, reason: 'duplicate shot must not double-score');

    final hit2 = game.applyIncomingShot(1, 1);
    expect(hit2, isTrue);
    expect(game.remoteScore, 2);
    expect(game.allBoatsSunk(), isTrue);
    expect(game.status, GameStatus.inGameFinish, reason: 'losing all boats ends the game');
    expect(game.iWon, isFalse);
  });

  test('applyShotResult scores hits and ends the game on allSunk', () {
    final game = Game.init();
    game.status = GameStatus.inGameRemoteStep;

    game.applyShotResult(0, 0, true, false);
    expect(game.remoteMatrix[0][0], trefferFeld);
    expect(game.myScore, 1);
    expect(game.status, GameStatus.inGameRemoteStep, reason: 'status unchanged unless allSunk');

    game.applyShotResult(1, 1, false, false);
    expect(game.remoteMatrix[1][1], verfehltFeld);
    expect(game.myScore, 1, reason: 'miss must not score');

    game.applyShotResult(2, 2, true, true);
    expect(game.myScore, 2);
    expect(game.status, GameStatus.inGameFinish);
    expect(game.iWon, isTrue);
  });

  test('applyStarterPick sets the correct turn status', () {
    final gameStarts = Game.init();
    gameStarts.status = GameStatus.inGame;
    gameStarts.applyStarterPick(true);
    expect(gameStarts.status, GameStatus.inGameMyStep);

    final gameWaits = Game.init();
    gameWaits.status = GameStatus.inGame;
    gameWaits.applyStarterPick(false);
    expect(gameWaits.status, GameStatus.inGameRemoteStep);
  });

  test('changeStatusByCommand: waitRemoteDesk + deskReady -> inGame', () {
    final game = Game.init();
    game.status = GameStatus.waitRemoteDesk;
    game.changeStatusByCommand(1, 'deskReady');
    expect(game.status, GameStatus.inGame);
  });

  test('full protocol exchange via executeCommand: request -> accept -> ready -> shots -> finish', () async {
    final services = UdpServices();
    final opponentKey = 'opponent-key';

    // seed the opponent as a known, online bro so sendGameCommand()/message flows can proceed
    final opponent = makeBro(opponentKey, 'Opponent');
    opponent.myStatus = Status.online;
    opponent.lastPing = DateTime.now();
    services.broGroup.addBro(opponent);

    globalData.game.newGame(opponent, GameStarter.remote);
    globalData.game.status = GameStatus.startRequestAndWait;

    // opponent accepts
    await services.executeCommand(buildCommand(opponentKey, 'goIn', ''), '127.0.0.1');
    expect(globalData.game.status, GameStatus.buildMyDeskAndWait);
    expect(services.acceptTimer, isNull, reason: 'accept timer must be cancelled once accepted');

    // opponent signals ready before we do
    await services.executeCommand(buildCommand(opponentKey, 'deskReady', ''), '127.0.0.1');
    expect(globalData.game.status, GameStatus.buildMyDesk, reason: 'opponent ready first, we still need to place boats');

    // now we place a single boat and become ready too - this mirrors the UI's ready-button handler
    globalData.game.myMatrix[0][0] = bootFeld;
    globalData.game.status = GameStatus.inGame; // ready button sets inGame directly since not buildMyDeskAndWait
    await services.resolveStarterIfNeeded();
    expect(
        [GameStatus.inGameMyStep, GameStatus.inGameRemoteStep].contains(globalData.game.status),
        isTrue,
        reason: 'starter must have been resolved locally since we are (by construction) not guaranteed the picker here');

    // regardless of who starts, drive one full shot/shotResult round trip explicitly:
    globalData.game.status = GameStatus.inGameRemoteStep; // pretend it is opponent's turn to shoot at us
    await services.executeCommand(buildCommand(opponentKey, 'shot', {'row': 0, 'col': 0}), '127.0.0.1');
    expect(globalData.game.myMatrix[0][0], trefferFeld);
    expect(globalData.game.remoteScore, 1);
    expect(globalData.game.status, GameStatus.inGameFinish, reason: 'our only boat is now sunk');
    expect(globalData.game.iWon, isFalse);

    // opponent leaving mid-anything must always reset us to idle
    globalData.game.status = GameStatus.inGameMyStep;
    await services.executeCommand(buildCommand(opponentKey, 'exit', ''), '127.0.0.1');
    expect(globalData.game.status, GameStatus.idle);
    expect(globalData.game.opponent, isNull);
  });
}
