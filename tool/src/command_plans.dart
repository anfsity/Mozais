import 'dart:io';

import 'run_report.dart';

List<RunStep> buildStepsFor(
  String command,
  int cycles,
  Directory repoRoot,
  String runDirectory,
) {
  switch (command) {
    case 'verify':
      return [
        _step('toolchain.check', ['bash', 'scripts/check-toolchain.sh']),
        _step('backend.format', [
          'cargo',
          'fmt',
          '--all',
          '--',
          '--check',
        ], workingDirectory: 'backend'),
        _step('backend.check', [
          'cargo',
          'check',
          '--locked',
        ], workingDirectory: 'backend'),
        _step('backend.test', [
          'cargo',
          'test',
          '--locked',
          '--',
          '--test-threads=1',
        ], workingDirectory: 'backend'),
        _step('backend.test_mock', [
          'cargo',
          'test',
          '--locked',
          '--features',
          'mock',
          '--',
          '--test-threads=1',
        ], workingDirectory: 'backend'),
        ..._sceneGenerationSteps(),
        _step('flutter.analyze', ['fvm', 'flutter', 'analyze']),
        _step('flutter.test', ['fvm', 'flutter', 'test']),
        _step('scene_schema.analyze', [
          'fvm',
          'dart',
          'analyze',
        ], workingDirectory: 'packages/mozais_scene_schema'),
        _step('scene_schema.test', [
          'fvm',
          'dart',
          'test',
        ], workingDirectory: 'packages/mozais_scene_schema'),
        _step('scene_codegen.analyze', [
          'fvm',
          'dart',
          'analyze',
        ], workingDirectory: 'packages/mozais_scene_codegen'),
        _step('scene_codegen.test', [
          'fvm',
          'dart',
          'test',
        ], workingDirectory: 'packages/mozais_scene_codegen'),
        _step('scene.analyze', [
          'fvm',
          'flutter',
          'analyze',
        ], workingDirectory: 'packages/mozais_scene'),
        _step('scene.test', [
          'fvm',
          'flutter',
          'test',
        ], workingDirectory: 'packages/mozais_scene'),
        _step('greeter_ui.analyze', [
          'fvm',
          'flutter',
          'analyze',
        ], workingDirectory: 'packages/mozais_greeter_ui'),
        _step('greeter_ui.test', [
          'fvm',
          'flutter',
          'test',
        ], workingDirectory: 'packages/mozais_greeter_ui'),
        _step('scene_editor.analyze', [
          'fvm',
          'flutter',
          'analyze',
        ], workingDirectory: 'packages/mozais_scene_editor'),
        _step('scene_editor.test', [
          'fvm',
          'flutter',
          'test',
        ], workingDirectory: 'packages/mozais_scene_editor'),
        _step(
          'dbus.smoke',
          [
            'bash',
            'scripts/debug-dbus.sh',
            'fvm',
            'dart',
            'run',
            'tool/dbus_gateway_smoke.dart',
          ],
          environment: {
            'MOZAIS_LOG_DIR': _join(repoRoot.path, '$runDirectory/dbus'),
          },
        ),
      ];
    case 'verify-perf':
      final steps = <RunStep>[..._sceneGenerationSteps()];
      final flutter = _flutterCommand();
      for (var cycle = 1; cycle <= cycles; cycle++) {
        final cycleReport = '$runDirectory/perf/scene_report_$cycle.json';
        steps.add(
          _step('performance.drive_$cycle', [
            ...flutter,
            'drive',
            '-d',
            'linux',
            '--profile',
            '--no-dds',
            '--dart-define=MOZAIS_PERF_REPORT_PATH=$cycleReport',
            '--driver=test_driver/integration_test.dart',
            '--target=integration_test/performance/scene_performance_test.dart',
          ]),
        );
      }
      steps.add(
        _step('performance.aggregate', [
          ..._dartCommand(),
          'run',
          'tool/perf/aggregate_perf.dart',
          '--output',
          'build/perf/scene_report.json',
          for (var cycle = 1; cycle <= cycles; cycle++) ...[
            '--input',
            '$runDirectory/perf/scene_report_$cycle.json',
          ],
        ]),
      );
      steps.add(
        _step('performance.compare', [
          ..._dartCommand(),
          'run',
          'tool/perf/compare_perf.dart',
          '--baseline',
          'tool/perf/baselines/default.json',
          '--candidate',
          'build/perf/scene_report.json',
        ]),
      );
      return steps;
    case 'generate-scenes':
      return _sceneGenerationSteps();
    case 'trace-perf':
      final timeline = '$runDirectory/perf/scene_interactions_timeline.json';
      return [
        ..._sceneGenerationSteps(),
        _step('performance.trace', [
          ..._flutterCommand(),
          'drive',
          '-d',
          'linux',
          '--profile',
          '--no-dds',
          '--dart-define=MOZAIS_PERF_TRACE_TIMELINE=true',
          '--dart-define=MOZAIS_PERF_TIMELINE_PATH=$timeline',
          '--driver=test_driver/integration_test.dart',
          '--target=integration_test/performance/scene_performance_test.dart',
        ]),
        _step('performance.summarize_trace', [
          ..._dartCommand(),
          'run',
          'tool/perf/summarize_timeline.dart',
          '--input',
          timeline,
        ]),
      ];
    default:
      throw StateError('No step plan for command $command.');
  }
}

List<RunStep> _sceneGenerationSteps() {
  return [
    _step('scenes.generate_default', [
      ..._dartCommand(),
      'run',
      'build_runner',
      'build',
    ], workingDirectory: 'packages/mozais_theme_default'),
    _step('scenes.generate_fallback', [
      ..._dartCommand(),
      'run',
      'build_runner',
      'build',
    ], workingDirectory: 'packages/mozais_theme_fallback'),
  ];
}

RunStep _step(
  String id,
  List<String> command, {
  String workingDirectory = '.',
  Map<String, String> environment = const {},
}) {
  return RunStep(
    id: id,
    command: command,
    workingDirectory: workingDirectory,
    environment: environment,
  );
}

List<String> _flutterCommand() {
  final customFlutter = Platform.environment['MOZAIS_FLUTTER_BIN'];
  return customFlutter == null || customFlutter.isEmpty
      ? ['fvm', 'flutter']
      : [customFlutter];
}

List<String> _dartCommand() {
  final customDart = Platform.environment['MOZAIS_DART_BIN'];
  if (customDart != null && customDart.isNotEmpty) {
    return [customDart];
  }
  final customFlutter = Platform.environment['MOZAIS_FLUTTER_BIN'];
  if (customFlutter != null && customFlutter.isNotEmpty) {
    return [_join(File(customFlutter).absolute.parent.path, 'dart')];
  }
  return ['fvm', 'dart'];
}

Map<String, String> artifactPathsFor(String command, String runDirectory) {
  return switch (command) {
    'verify-perf' => {
      'performance_report': 'build/perf/scene_report.json',
      'performance_raw_reports': '$runDirectory/perf',
    },
    'trace-perf' => {
      'timeline': '$runDirectory/perf/scene_interactions_timeline.json',
    },
    _ => const {},
  };
}

String _join(String base, String relative) {
  return '$base${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';
}
