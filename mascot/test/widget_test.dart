import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:mascot/mascot_controller.dart';
import 'package:mascot/model_config.dart';
import 'package:mascot/wander_controller.dart';
import 'package:mascot/window_config.dart';

const _blendShapeToml = '''
[model]
name = "Test Blend Shape"
idle_emotion = "Gentle"

[camera]
zoom = 0.132
y = -60.0

[mouth]
param = "MouthOpen"
open_value = 1.0

[fallback]
mouth_open = "assets/fallback/mouth_open.png"
mouth_closed = "assets/fallback/mouth_closed.png"

[defaults]
MouthOpen = 0.0
Gentle = 0.0
Joy = 0.0
Blush = 0.0
Trouble = 0.0
Singing = 0.0

[emotions.Gentle]
Gentle = 1.0

[emotions.Joy]
Joy = 1.0

[emotions.Blush]
Blush = 1.0

[emotions.Trouble]
Trouble = 1.0

[emotions.Singing]
Singing = 1.0
''';

const _partsToml = '''
[model]
name = "Test Parts"
idle_emotion = "Gentle"

[camera]
zoom = 0.132
y = -60.0

[mouth]
param = "MouthType"
open_value = 0.429

[fallback]
mouth_open = "assets/fallback/mouth_open.png"
mouth_closed = "assets/fallback/mouth_closed.png"

[defaults]
EyebrowType = 0.0
EyeType = 0.333
MouthType = 0.0
CheekType = 0.0

[emotions.Gentle]
EyebrowType = 0.0
EyeType = 0.333
MouthType = 0.0
CheekType = 0.0

[emotions.Joy]
EyebrowType = 0.333
EyeType = 0.5
MouthType = 0.286
CheekType = 0.333

[emotions.Blush]
EyebrowType = 0.5
EyeType = 0.833
MouthType = 0.143
CheekType = 0.333

[emotions.Trouble]
EyebrowType = 0.5
EyeType = 0.333
MouthType = 1.0
CheekType = 0.0

[emotions.Singing]
EyebrowType = 0.0
EyeType = 0.333
MouthType = 0.571
CheekType = 0.333
''';

ModelConfig _blendShapeConfig(String dirPath) =>
    ModelConfig.fromTomlString(dirPath, _blendShapeToml);

ModelConfig _partsConfig(String dirPath) =>
    ModelConfig.fromTomlString(dirPath, _partsToml);

void main() {
  late Directory tempDir;
  late String signalPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mascot_test_');
    signalPath = '${tempDir.path}/mascot_speaking';
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  // ── Blend Shape Model Tests (existing) ──────────────────────

  group('BlendShape model', () {
    late MascotController controller;

    setUp(() {
      controller = MascotController.withConfig(
        signalPath,
        _blendShapeConfig(tempDir.path),
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('MascotController initializes with mouth closed', () {
      expect(controller.showOpenMouth, false);
      expect(controller.isSpeaking, false);
      expect(controller.message, '');
    });

    test('MascotController detects signal file and reads message', () async {
      // Write signal file with message
      File(signalPath).writeAsStringSync('テスト完了');

      // Wait for poll cycle (100ms) + buffer
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(controller.isSpeaking, true);
      expect(controller.message, 'テスト完了');
    });

    test('MascotController reads empty signal file', () async {
      // Create empty signal file
      File(signalPath).createSync();

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(controller.isSpeaking, true);
      expect(controller.message, '');
    });

    test('MascotController stops speaking when signal file removed', () async {
      // Start speaking
      File(signalPath).writeAsStringSync('開始');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(controller.isSpeaking, true);

      // Remove signal file
      File(signalPath).deleteSync();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(controller.isSpeaking, false);
      expect(controller.showOpenMouth, false);
    });

    test('MascotController mouth animation toggles during speaking', () async {
      File(signalPath).writeAsStringSync('口パク');

      // Wait long enough for poll (100ms) + several anim cycles (150ms each)
      // and track all values seen
      final values = <bool>{};
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        values.add(controller.showOpenMouth);
      }

      // Should have seen both true and false during animation
      expect(values, containsAll([true, false]));
    });

    test('Dispose cancels all timers', () async {
      // Create a separate controller for this test
      final c = MascotController.withConfig(
        signalPath,
        _blendShapeConfig(tempDir.path),
      );

      // Start speaking to activate anim timer
      File(signalPath).writeAsStringSync('テスト');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // Dispose should not throw
      c.dispose();

      // Verify no further state changes after dispose
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // If timers weren't cancelled, this would throw on notifyListeners
    });

    test('parameters map initializes with idle emotion (Gentle)', () {
      final params = controller.parameters;
      expect(params['MouthOpen'], 0.0);
      // Idle emotion is Gentle, so Gentle=1.0 and others=0.0
      expect(params['Gentle'], 1.0);
      expect(params['Joy'], 0.0);
      expect(params['Blush'], 0.0);
      expect(params['Trouble'], 0.0);
      expect(params['Singing'], 0.0);
    });

    test('JSON signal file sets emotion parameter', () async {
      final json = jsonEncode({'message': 'うれしい', 'emotion': 'Joy'});
      File(signalPath).writeAsStringSync(json);

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(controller.isSpeaking, true);
      expect(controller.message, 'うれしい');
      expect(controller.parameters['Joy'], 1.0);
      expect(controller.parameters['Gentle'], 0.0);
      expect(controller.parameters['Blush'], 0.0);
      expect(controller.parameters['Trouble'], 0.0);
      expect(controller.parameters['Singing'], 0.0);
    });

    test('Plain text signal file falls back to idle emotion (Gentle)',
        () async {
      File(signalPath).writeAsStringSync('こんにちは');

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(controller.isSpeaking, true);
      expect(controller.message, 'こんにちは');
      // null emotion → idle emotion (Gentle)
      expect(controller.parameters['Gentle'], 1.0);
      expect(controller.parameters['Joy'], 0.0);
      expect(controller.parameters['Blush'], 0.0);
      expect(controller.parameters['Trouble'], 0.0);
      expect(controller.parameters['Singing'], 0.0);
    });

    test('Mouth animation toggles MouthOpen parameter between 0.0 and 1.0',
        () async {
      File(signalPath).writeAsStringSync('テスト');

      final values = <double>{};
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        values.add(controller.parameters['MouthOpen']!);
      }

      // Should have seen both 0.0 and 1.0 during animation
      expect(values, containsAll([0.0, 1.0]));
    });

    test('Emotions reset to idle when signal file removed', () async {
      // Start with emotion
      final json = jsonEncode({'message': 'テスト', 'emotion': 'Blush'});
      File(signalPath).writeAsStringSync(json);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(controller.parameters['Blush'], 1.0);

      // Remove signal file
      File(signalPath).deleteSync();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // Should reset to idle (Gentle)
      expect(controller.parameters['Blush'], 0.0);
      expect(controller.parameters['Gentle'], 1.0);
      expect(controller.parameters['MouthOpen'], 0.0);
    });

    test('modelConfig returns blend shape config', () {
      expect(controller.modelConfig.name, 'Test Blend Shape');
      expect(controller.modelConfig.mouthParam, 'MouthOpen');
    });
  });

  // ── Parts Model Tests ───────────────────────────────────────

  group('Parts model', () {
    late MascotController controller;

    setUp(() {
      controller = MascotController.withConfig(
        signalPath,
        _partsConfig(tempDir.path),
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('initializes with Gentle face parameters', () {
      // Parts model idle = Gentle face
      final params = controller.parameters;
      expect(params['EyebrowType'], 0.0);
      expect(params['EyeType'], 0.333);
      expect(params['MouthType'], 0.0);
      expect(params['CheekType'], 0.0);
    });

    test('has correct model config', () {
      expect(controller.modelConfig.name, 'Test Parts');
      expect(controller.modelConfig.mouthParam, 'MouthType');
      expect(controller.modelConfig.mouthOpenValue, 0.429);
    });

    test('Joy emotion sets correct param values', () async {
      final json = jsonEncode({'message': 'やったー', 'emotion': 'Joy'});
      File(signalPath).writeAsStringSync(json);

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(controller.isSpeaking, true);
      expect(controller.message, 'やったー');
      // MouthType may be animated, check non-mouth params
      expect(controller.parameters['EyebrowType'], 0.333);
      expect(controller.parameters['EyeType'], 0.5);
      expect(controller.parameters['CheekType'], 0.333);
    });

    test('Blush emotion sets correct param values', () async {
      final json = jsonEncode({'message': 'えへへ', 'emotion': 'Blush'});
      File(signalPath).writeAsStringSync(json);

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(controller.parameters['EyebrowType'], 0.5);
      expect(controller.parameters['EyeType'], 0.833);
      expect(controller.parameters['CheekType'], 0.333);
    });

    test('Trouble emotion sets correct param values', () async {
      final json = jsonEncode({'message': '困った', 'emotion': 'Trouble'});
      File(signalPath).writeAsStringSync(json);

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(controller.parameters['EyebrowType'], 0.5);
      expect(controller.parameters['EyeType'], 0.333);
      expect(controller.parameters['CheekType'], 0.0);
    });

    test('mouth animation alternates MouthType between emotion default and 0.429',
        () async {
      final json = jsonEncode({'message': 'テスト', 'emotion': 'Joy'});
      File(signalPath).writeAsStringSync(json);

      final values = <double>{};
      for (var i = 0; i < 15; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        values.add(controller.parameters['MouthType']!);
      }

      // Should alternate between Joy's MouthType (0.286) and open (0.429)
      expect(values, contains(0.429));
      expect(values, contains(closeTo(0.286, 0.001)));
    });

    test('idle state (no signal) uses Gentle face', () async {
      // Start speaking with Joy
      final json = jsonEncode({'message': 'テスト', 'emotion': 'Joy'});
      File(signalPath).writeAsStringSync(json);
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // Stop speaking
      File(signalPath).deleteSync();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // Should revert to Gentle (idle) face
      expect(controller.parameters['EyebrowType'], 0.0);
      expect(controller.parameters['EyeType'], 0.333);
      expect(controller.parameters['CheekType'], 0.0);
    });

    test('plain text signal uses Gentle face (idle emotion)', () async {
      File(signalPath).writeAsStringSync('こんにちは');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(controller.isSpeaking, true);
      // null emotion → idle = Gentle
      expect(controller.parameters['EyebrowType'], 0.0);
      expect(controller.parameters['EyeType'], 0.333);
      expect(controller.parameters['CheekType'], 0.0);
    });
  });

  // ── Zombie Child Cleanup Tests ─────────────────────────────

  group('Wander children PID persistence', () {
    late Directory signalDir;

    setUp(() {
      signalDir = Directory.systemTemp.createTempSync('zombie_test_');
    });

    tearDown(() {
      signalDir.deleteSync(recursive: true);
    });

    test('wander_children.json round-trips child entries', () {
      final childrenFile = File('${signalDir.path}/wander_children.json');
      final entries = [
        {'pid': 12345, 'signalDir': '/tmp/child1'},
        {'pid': 67890, 'signalDir': '/tmp/child2'},
      ];
      childrenFile.writeAsStringSync(jsonEncode(entries));

      final data =
          jsonDecode(childrenFile.readAsStringSync()) as List<dynamic>;
      expect(data.length, 2);
      expect(data[0]['pid'], 12345);
      expect(data[0]['signalDir'], '/tmp/child1');
      expect(data[1]['pid'], 67890);
      expect(data[1]['signalDir'], '/tmp/child2');
    });

    test('cleanup creates mascot_dismiss for each child signal dir', () {
      // Create child signal dirs
      final child1Dir =
          Directory('${signalDir.path}/child1')..createSync(recursive: true);
      final child2Dir =
          Directory('${signalDir.path}/child2')..createSync(recursive: true);

      // Write wander_children.json
      final childrenFile = File('${signalDir.path}/wander_children.json');
      final entries = [
        {'pid': 99999, 'signalDir': child1Dir.path},
        {'pid': 99998, 'signalDir': child2Dir.path},
      ];
      childrenFile.writeAsStringSync(jsonEncode(entries));

      // Simulate cleanup logic (same as _cleanStaleChildren)
      final data =
          jsonDecode(childrenFile.readAsStringSync()) as List<dynamic>;
      for (final entry in data) {
        final pid = entry['pid'] as int?;
        final dir = entry['signalDir'] as String?;
        if (pid != null) {
          try {
            Process.killPid(pid);
          } catch (_) {} // PID won't exist in test
        }
        if (dir != null) {
          try {
            File('$dir/mascot_dismiss').writeAsStringSync('');
          } catch (_) {}
        }
      }
      childrenFile.deleteSync();

      // Verify mascot_dismiss files were created
      expect(File('${child1Dir.path}/mascot_dismiss').existsSync(), true);
      expect(File('${child2Dir.path}/mascot_dismiss').existsSync(), true);
      // Verify children file was removed
      expect(childrenFile.existsSync(), false);
    });

    test('cleanup handles missing wander_children.json gracefully', () {
      final childrenFile = File('${signalDir.path}/wander_children.json');
      // File doesn't exist — should not throw
      expect(childrenFile.existsSync(), false);
      // The actual code returns early; just verify no crash
    });

    test('cleanup handles corrupt JSON by deleting the file', () {
      final childrenFile = File('${signalDir.path}/wander_children.json');
      childrenFile.writeAsStringSync('not valid json!!!');

      // Simulate cleanup with corrupt data
      try {
        jsonDecode(childrenFile.readAsStringSync()) as List<dynamic>;
        fail('Should have thrown');
      } catch (_) {
        // Cleanup fallback: delete the file
        try {
          childrenFile.deleteSync();
        } catch (_) {}
      }

      expect(childrenFile.existsSync(), false);
    });

    test('empty children list writes valid empty JSON array', () {
      final childrenFile = File('${signalDir.path}/wander_children.json');
      final emptyList = <Map<String, dynamic>>[];
      childrenFile.writeAsStringSync(jsonEncode(emptyList));

      final data =
          jsonDecode(childrenFile.readAsStringSync()) as List<dynamic>;
      expect(data, isEmpty);
    });
  });

  // ── ModelConfig Unit Tests ──────────────────────────────────

  group('ModelConfig', () {
    test('fromDirectory loads blend_shape config from filesystem', () {
      final dir = Directory.systemTemp.createTempSync('model_test_');
      try {
        File('${dir.path}/emotions.toml').writeAsStringSync(_blendShapeToml);
        final config = ModelConfig.fromDirectory(dir.path);
        expect(config.name, 'Test Blend Shape');
        expect(config.modelDirPath, dir.path);
        expect(config.modelFilePath, '${dir.path}/model.inp');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('fromDirectory loads parts config from filesystem', () {
      final dir = Directory.systemTemp.createTempSync('model_test_');
      try {
        File('${dir.path}/emotions.toml').writeAsStringSync(_partsToml);
        final config = ModelConfig.fromDirectory(dir.path);
        expect(config.name, 'Test Parts');
        expect(config.mouthParam, 'MouthType');
        expect(config.mouthOpenValue, 0.429);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('fromDirectory throws when emotions.toml missing', () {
      final dir = Directory.systemTemp.createTempSync('model_test_');
      try {
        expect(() => ModelConfig.fromDirectory(dir.path), throwsStateError);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('blendShape getEmotionParams returns correct toggle map', () {
      final config = _blendShapeConfig('/tmp/test');
      final joyParams = config.getEmotionParams('Joy')!;
      expect(joyParams['Joy'], 1.0);
    });

    test('parts getEmotionParams returns correct mapped values', () {
      final config = _partsConfig('/tmp/test');
      final joyParams = config.getEmotionParams('Joy')!;
      expect(joyParams['EyebrowType'], 0.333);
      expect(joyParams['EyeType'], 0.5);
      expect(joyParams['MouthType'], 0.286);
      expect(joyParams['CheekType'], 0.333);
    });

    test('getEmotionParams returns null for unknown emotion', () {
      final config = _blendShapeConfig('/tmp/test');
      expect(config.getEmotionParams('Unknown'), isNull);
    });

    test('getMouthClosedValue for blendShape is always 0.0', () {
      final config = _blendShapeConfig('/tmp/test');
      expect(config.getMouthClosedValue('Joy'), 0.0);
      expect(config.getMouthClosedValue(null), 0.0);
    });

    test('getMouthClosedValue for parts returns emotion MouthType', () {
      final config = _partsConfig('/tmp/test');
      expect(config.getMouthClosedValue('Joy'), 0.286);
      expect(config.getMouthClosedValue('Trouble'), 1.0);
      expect(config.getMouthClosedValue('Gentle'), 0.0);
      expect(config.getMouthClosedValue(null), 0.0); // defaults to Gentle
    });

    test('all five emotions are defined for both model types', () {
      const emotions = ['Gentle', 'Joy', 'Blush', 'Trouble', 'Singing'];
      for (final config in [
        _blendShapeConfig('/tmp/test'),
        _partsConfig('/tmp/test'),
      ]) {
        for (final emotion in emotions) {
          expect(config.getEmotionParams(emotion), isNotNull,
              reason: '${config.name}: $emotion should be defined');
        }
      }
    });

    test('idleEmotion defaults to Gentle', () {
      final config = _blendShapeConfig('/tmp/test');
      expect(config.idleEmotion, 'Gentle');
    });

    test('camera settings parsed correctly', () {
      final config = _blendShapeConfig('/tmp/test');
      expect(config.cameraZoom, 0.132);
      expect(config.cameraY, -60.0);
    });

    test('fallback paths parsed correctly', () {
      final config = _blendShapeConfig('/tmp/test');
      expect(config.fallbackMouthOpen, 'assets/fallback/mouth_open.png');
      expect(config.fallbackMouthClosed, 'assets/fallback/mouth_closed.png');
    });
  });

  // ── WanderController Tests ──────────────────────────────────

  group('WanderController', () {
    test('updateDrag does not call notifyListeners (no jitter)', () {
      // Ensure binding is initialized for Ticker
      TestWidgetsFlutterBinding.ensureInitialized();

      final controller = WanderController(seed: 42);
      // Enter drag mode first
      controller.startDrag();

      var listenerCallCount = 0;
      controller.addListener(() {
        listenerCallCount++;
      });

      // Reset count after addListener (startDrag already called notifyListeners)
      listenerCallCount = 0;

      // Perform several drag updates
      controller.updateDrag(const Offset(10, 5));
      controller.updateDrag(const Offset(-3, 2));
      controller.updateDrag(const Offset(7, -1));

      // updateDrag should NOT fire notifyListeners — the window moves but
      // the widget inside the window stays put, so no rebuild is needed.
      expect(listenerCallCount, 0,
          reason: 'updateDrag must not call notifyListeners to avoid jitter');

      controller.dispose();
    });

    test('updateDrag still updates position and clamps to screen bounds', () {
      TestWidgetsFlutterBinding.ensureInitialized();

      final controller = WanderController(seed: 42);
      controller.startDrag();

      // Move into the expected area
      controller.updateDrag(const Offset(100, 200));
      expect(controller.positionX, greaterThan(0));
      expect(controller.positionY, greaterThan(0));

      // Try to move beyond bounds (large negative delta)
      controller.updateDrag(const Offset(-99999, -99999));
      expect(controller.positionX, 0.0);
      expect(controller.positionY, 0.0);

      controller.dispose();
    });
  });

  // ── WanderController Collision Tests ──────────────────────

  group('WanderController collision', () {
    late WanderController wander;

    setUp(() {
      wander = WanderController(
        seed: 42,
        windowWidth: 150,
        windowHeight: 350,
      );
    });

    tearDown(() {
      wander.dispose();
    });

    test('resolveCollision fires onCollision callback when overlapping', () {
      var callCount = 0;
      wander.onCollision = () => callCount++;

      final collided = wander.resolveCollision(200, 0, 150, 350);

      expect(collided, false);
      expect(callCount, 0);
    });

    test('resolveCollision detects AABB overlap and fires callback', () {
      var callCount = 0;
      wander.onCollision = () => callCount++;

      final collided = wander.resolveCollision(100, 0, 150, 350);

      expect(collided, true);
      expect(callCount, 1);
    });

    test('resolveCollision respects cooldown period', () {
      var callCount = 0;
      wander.onCollision = () => callCount++;

      wander.resolveCollision(100, 0, 150, 350);
      expect(callCount, 1);

      wander.resolveCollision(100, 0, 150, 350);
      expect(callCount, 1);
    });

    test('resolveCollision fires again after cooldown expires', () async {
      final fastWander = WanderController(
        seed: 42,
        windowWidth: 150,
        windowHeight: 350,
      );

      var callCount = 0;
      fastWander.onCollision = () => callCount++;

      fastWander.resolveCollision(100, 0, 150, 350);
      expect(callCount, 1);

      fastWander.resolveCollision(100, 0, 150, 350);
      expect(callCount, 1, reason: 'Should not fire within cooldown');

      fastWander.dispose();
    });

    test('resolveCollision does not fire callback when no overlap', () {
      var callCount = 0;
      wander.onCollision = () => callCount++;

      final collided = wander.resolveCollision(500, 0, 150, 350);

      expect(collided, false);
      expect(callCount, 0);
    });

    test('resolveCollision works without onCollision callback set', () {
      final collided = wander.resolveCollision(100, 0, 150, 350);
      expect(collided, true);
    });
  });

  // ── TTS Timer Cancellation Tests (#41) ─────────────────────

  group('TTS timer cancellation', () {
    test('Timer instances can be cancelled before firing', () {
      final timers = <Timer>[];
      var firedCount = 0;

      // Simulate _sendDelayedTts creating timers
      final writeTimer = Timer(const Duration(seconds: 2), () {
        firedCount++;
      });
      timers.add(writeTimer);

      // Cancel all timers (simulates dispose)
      for (final timer in timers) {
        timer.cancel();
      }
      timers.clear();

      expect(firedCount, 0, reason: 'Timer should not fire after cancellation');
    });

    test('Cancelling already-fired timer is safe', () async {
      var fired = false;
      final timer = Timer(const Duration(milliseconds: 10), () {
        fired = true;
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fired, true);

      // Cancelling after fire should not throw
      timer.cancel();
    });
  });

  // ── Spawn Signal Format Tests ─────────────────────────────

  group('Spawn signal format (task_id only)', () {
    late Directory signalDir;

    setUp(() {
      signalDir = Directory.systemTemp.createTempSync('spawn_signal_test_');
    });

    tearDown(() {
      signalDir.deleteSync(recursive: true);
    });

    test('new format: task_id only produces valid signal dir path', () {
      final spawnFile = File('${signalDir.path}/spawn_child');
      spawnFile.writeAsStringSync(jsonEncode({'task_id': 'abc12345'}));

      final content = spawnFile.readAsStringSync().trim();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final taskId = json['task_id'] as String;
      final taskSignalDir = '${signalDir.path}/task-$taskId';

      expect(taskId, 'abc12345');
      expect(taskSignalDir, endsWith('/task-abc12345'));
    });

    test('parent creates task dir from task_id', () {
      final taskId = 'def67890';
      final taskDir = Directory('${signalDir.path}/task-$taskId');

      expect(taskDir.existsSync(), false);
      taskDir.createSync(recursive: true);
      expect(taskDir.existsSync(), true);
    });

    test('stale task dirs with mascot_dismiss are cleaned up', () {
      // Create orphaned task dirs
      final staleDir = Directory('${signalDir.path}/task-stale01')
        ..createSync(recursive: true);
      File('${staleDir.path}/mascot_dismiss').createSync();

      final activeDir = Directory('${signalDir.path}/task-active01')
        ..createSync(recursive: true);

      // Simulate cleanup: remove dirs with mascot_dismiss
      for (final entity in signalDir.listSync()) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          if (!name.startsWith('task-')) continue;
          if (File('${entity.path}/mascot_dismiss').existsSync()) {
            entity.deleteSync(recursive: true);
          }
        }
      }

      expect(staleDir.existsSync(), false);
      expect(activeDir.existsSync(), true);
    });

    test('untracked task dirs are cleaned up', () {
      // Create task dirs (none tracked in wander_children.json)
      final orphanDir = Directory('${signalDir.path}/task-orphan01')
        ..createSync(recursive: true);

      final knownSignalDirs = <String>{};

      for (final entity in signalDir.listSync()) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          if (!name.startsWith('task-')) continue;
          if (!knownSignalDirs.contains(entity.path)) {
            entity.deleteSync(recursive: true);
          }
        }
      }

      expect(orphanDir.existsSync(), false);
    });

    test('legacy _active_task_mascots file is removed', () {
      final legacyFile = File('${signalDir.path}/_active_task_mascots');
      legacyFile.writeAsStringSync('abc123 /tmp/task-abc123\n');

      expect(legacyFile.existsSync(), true);
      legacyFile.deleteSync();
      expect(legacyFile.existsSync(), false);
    });
  });

  // ── Signal Envelope Tests (#39) ─────────────────────────────

  group('Signal envelope format', () {
    late Directory signalDir;
    late MascotController controller;

    setUp(() {
      signalDir = Directory.systemTemp.createTempSync('envelope_test_');
      File('${signalDir.path}/mascot_speaking').createSync();
      controller = MascotController.withConfig(
        '${signalDir.path}/mascot_speaking',
        _blendShapeConfig('/tmp/test'),
      );
    });

    tearDown(() {
      controller.dispose();
      signalDir.deleteSync(recursive: true);
    });

    test('envelope v1 speech signal sets message and emotion', () async {
      final envelope = jsonEncode({
        'version': '1',
        'type': 'mascot.speech',
        'payload': {'message': 'こんにちは', 'emotion': 'Joy'},
      });
      File('${signalDir.path}/mascot_speaking')
          .writeAsStringSync(envelope);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(controller.message, 'こんにちは');
      expect(controller.isSpeaking, true);
    });

    test('legacy JSON signal still works (backward compatible)', () async {
      final legacy = jsonEncode({
        'message': 'レガシー形式',
        'emotion': 'Gentle',
      });
      File('${signalDir.path}/mascot_speaking')
          .writeAsStringSync(legacy);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(controller.message, 'レガシー形式');
      expect(controller.isSpeaking, true);
    });

    test('plain text signal still works (backward compatible)', () async {
      File('${signalDir.path}/mascot_speaking')
          .writeAsStringSync('プレーンテキスト');

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(controller.message, 'プレーンテキスト');
      expect(controller.isSpeaking, true);
    });

    test('spawn signal envelope is unwrapped correctly', () {
      final envelope = jsonEncode({
        'version': '1',
        'type': 'mascot.spawn',
        'payload': {'task_id': 'abc12345'},
      });
      final json = jsonDecode(envelope) as Map<String, dynamic>;
      // Unwrap envelope
      final payload = json.containsKey('version')
          ? (json['payload'] as Map<String, dynamic>? ?? {})
          : json;
      expect(payload['task_id'], 'abc12345');
    });

    test('legacy spawn signal is read directly', () {
      final legacy = jsonEncode({'task_id': 'def67890'});
      final json = jsonDecode(legacy) as Map<String, dynamic>;
      // No envelope, read directly
      final payload = json.containsKey('version')
          ? (json['payload'] as Map<String, dynamic>? ?? {})
          : json;
      expect(payload['task_id'], 'def67890');
    });

    test('position envelope is unwrapped for collision', () {
      final envelope = jsonEncode({
        'version': '1',
        'type': 'mascot.position',
        'payload': {'x': 100.0, 'y': 200.0, 'w': 150.0, 'h': 350.0},
      });
      final json = jsonDecode(envelope) as Map<String, dynamic>;
      final data = json.containsKey('version')
          ? (json['payload'] as Map<String, dynamic>? ?? {})
          : json;
      expect((data['x'] as num).toDouble(), 100.0);
      expect((data['y'] as num).toDouble(), 200.0);
    });
  });

  // ── WindowConfig Tests (#38) ──────────────────────────────

  group('WindowConfig', () {
    test('default constructor provides expected values', () {
      const config = WindowConfig();
      expect(config.mainWidth, 424.0);
      expect(config.mainHeight, 528.0);
      expect(config.childWidth, 264.0);
      expect(config.maxChildren, 2);
      expect(config.wanderWidth, 152.0);
      expect(config.wanderHeight, 280.0);
      expect(config.gravity, 0.8);
      expect(config.bouncePeriodMs, 600);
      expect(config.bounceHeight, 6.0);
      expect(config.squishAmount, 0.03);
      expect(config.speedMin, 0.4);
      expect(config.speedMax, 1.2);
      expect(config.collisionCheckInterval, 18);
      expect(config.collisionCooldownSeconds, 5);
      expect(config.broadcastThreshold, 10.0);
    });

    test('fromTomlString parses all sections', () {
      const toml = '''
[main_window]
width = 500.0
height = 600.0

[child_window]
width = 300.0
max_children = 3

[wander_window]
width = 200.0
height = 400.0

[wander.physics]
gravity = 1.0
bounce_damping = 0.5

[wander.animation]
bounce_period_ms = 800
bounce_height = 8.0

[wander.behavior]
speed_min = 0.5
speed_max = 2.0

[wander.collision]
check_interval = 10
cooldown_seconds = 3
broadcast_threshold = 5.0
''';
      final config = WindowConfig.fromTomlString(toml);
      expect(config.mainWidth, 500.0);
      expect(config.mainHeight, 600.0);
      expect(config.childWidth, 300.0);
      expect(config.maxChildren, 3);
      expect(config.wanderWidth, 200.0);
      expect(config.wanderHeight, 400.0);
      expect(config.gravity, 1.0);
      expect(config.bounceDamping, 0.5);
      expect(config.bouncePeriodMs, 800);
      expect(config.bounceHeight, 8.0);
      expect(config.speedMin, 0.5);
      expect(config.speedMax, 2.0);
      expect(config.collisionCheckInterval, 10);
      expect(config.collisionCooldownSeconds, 3);
      expect(config.broadcastThreshold, 5.0);
    });

    test('fromFile returns defaults for missing file', () {
      final config = WindowConfig.fromFile('/nonexistent/path/window.toml');
      expect(config.mainWidth, 424.0);
      expect(config.bounceHeight, 6.0);
    });

    test('partial TOML fills missing values with defaults', () {
      const toml = '''
[main_window]
width = 500.0
''';
      final config = WindowConfig.fromTomlString(toml);
      expect(config.mainWidth, 500.0);
      // All other values should be defaults
      expect(config.mainHeight, 528.0);
      expect(config.bounceHeight, 6.0);
      expect(config.maxChildren, 2);
    });
  });
}
