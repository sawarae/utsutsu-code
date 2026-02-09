import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mascot/mascot_controller.dart';
import 'package:mascot/model_config.dart';

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
}
