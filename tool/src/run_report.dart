import 'dart:convert';
import 'dart:io';

enum RunOutputFormat { text, json }

class RunStep {
  const RunStep({
    required this.id,
    required this.command,
    required this.workingDirectory,
    required this.environment,
  });

  final String id;
  final List<String> command;
  final String workingDirectory;
  final Map<String, String> environment;
}

Future<int> runDevCommand({
  required String command,
  required RunOutputFormat format,
  required String? reportPath,
  required Directory repoRoot,
  required String runDirectory,
  required List<RunStep> steps,
  required Map<String, String> artifactPaths,
}) async {
  final runDirectoryPath = _join(repoRoot.path, runDirectory);
  await Directory(runDirectoryPath).create(recursive: true);
  final eventsPath = _join(runDirectoryPath, 'events.jsonl');
  final events = File(eventsPath).openWrite();
  final startedAt = DateTime.now().toUtc();
  final stopwatch = Stopwatch()..start();
  final stepResults = <_StepResult>[];

  Future<void> recordEvent(String name, Map<String, Object?> fields) async {
    events.writeln(
      jsonEncode({
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'run_id': _lastSegment(runDirectory),
        'event': name,
        ...fields,
      }),
    );
    await events.flush();
  }

  await recordEvent('run_started', {'command': command});
  if (format == RunOutputFormat.text) {
    stderr.writeln('Run ${_lastSegment(runDirectory)}: $command');
  }

  for (var index = 0; index < steps.length; index++) {
    final step = steps[index];
    await recordEvent('step_started', {
      'step_id': step.id,
      'command': step.command,
      'working_directory': step.workingDirectory,
    });
    if (format == RunOutputFormat.text) {
      stderr.writeln('==> ${index + 1}/${steps.length} ${step.id}');
    }

    final result = await _runStep(
      step: step,
      repoRoot: repoRoot,
      runDirectoryPath: runDirectoryPath,
      runDirectory: runDirectory,
      format: format,
    );
    stepResults.add(result);
    await recordEvent('step_finished', {
      'step_id': step.id,
      'status': result.status,
      'exit_code': result.exitCode,
      'duration_ms': result.durationMs,
    });
    if (format == RunOutputFormat.text) {
      stderr.writeln(
        '<== ${step.id}: ${result.status} (${result.durationMs} ms)',
      );
    }
    if (result.status == 'failed') {
      break;
    }
  }

  stopwatch.stop();
  final finishedAt = DateTime.now().toUtc();
  final status = stepResults.every((result) => result.status == 'passed')
      ? 'passed'
      : 'failed';
  final reportFile = reportPath == null
      ? File(_join(runDirectoryPath, 'report.json'))
      : _resolveFile(repoRoot, reportPath);
  await reportFile.parent.create(recursive: true);

  final resolvedArtifacts = <String, String>{
    'run_directory': _relativePath(repoRoot, runDirectoryPath),
    'events': _relativePath(repoRoot, eventsPath),
    for (final entry in artifactPaths.entries)
      entry.key: _relativePath(repoRoot, _join(repoRoot.path, entry.value)),
  };
  final report = <String, Object?>{
    'schema_version': 1,
    'run_id': _lastSegment(runDirectory),
    'command': command,
    'status': status,
    'started_at': startedAt.toIso8601String(),
    'finished_at': finishedAt.toIso8601String(),
    'duration_ms': stopwatch.elapsedMilliseconds,
    'artifacts': resolvedArtifacts,
    'steps': [for (final result in stepResults) result.toJson()],
    'report_path': _relativePath(repoRoot, reportFile.path),
    if (command == 'verify-perf' &&
        stepResults.any(
          (result) =>
              result.id == 'performance.aggregate' && result.status == 'passed',
        ))
      'performance': await _readPerformanceSummary(
        _join(repoRoot.path, 'build/perf/scene_report.json'),
      ),
  };

  await recordEvent('run_finished', {
    'status': status,
    'duration_ms': stopwatch.elapsedMilliseconds,
    'report_path': _relativePath(repoRoot, reportFile.path),
  });
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  await events.close();

  if (format == RunOutputFormat.json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  } else {
    stderr.writeln(
      'Run $status. Report: ${_relativePath(repoRoot, reportFile.path)}',
    );
    stderr.writeln('Logs: ${_relativePath(repoRoot, runDirectoryPath)}');
  }
  return status == 'passed' ? 0 : 1;
}

Future<_StepResult> _runStep({
  required RunStep step,
  required Directory repoRoot,
  required String runDirectoryPath,
  required String runDirectory,
  required RunOutputFormat format,
}) async {
  final startedAt = DateTime.now().toUtc();
  final stopwatch = Stopwatch()..start();
  final logName = step.id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  final stdoutPath = _join(runDirectoryPath, '$logName.stdout.log');
  final stderrPath = _join(runDirectoryPath, '$logName.stderr.log');
  final stdoutLog = File(stdoutPath).openWrite();
  final stderrLog = File(stderrPath).openWrite();
  int? processExitCode;
  Object? failure;

  try {
    final process = await Process.start(
      step.command.first,
      step.command.skip(1).toList(),
      workingDirectory: _join(repoRoot.path, step.workingDirectory),
      environment: step.environment.isEmpty
          ? null
          : {...Platform.environment, ...step.environment},
    );
    final stdoutCopy = _copyOutput(
      process.stdout,
      stdoutLog,
      format == RunOutputFormat.text ? stdout : null,
    );
    final stderrCopy = _copyOutput(
      process.stderr,
      stderrLog,
      format == RunOutputFormat.text ? stderr : null,
    );
    processExitCode = await process.exitCode;
    await Future.wait([stdoutCopy, stderrCopy]);
  } catch (error) {
    failure = error;
    stderrLog.writeln('Could not complete step: $error');
    if (format == RunOutputFormat.text) {
      stderr.writeln('Could not complete step ${step.id}: $error');
    }
  } finally {
    await Future.wait([stdoutLog.flush(), stderrLog.flush()]);
    await Future.wait([stdoutLog.close(), stderrLog.close()]);
  }

  stopwatch.stop();
  final finishedAt = DateTime.now().toUtc();
  final succeeded = failure == null && processExitCode == 0;
  return _StepResult(
    id: step.id,
    command: step.command,
    workingDirectory: step.workingDirectory,
    status: succeeded ? 'passed' : 'failed',
    exitCode: processExitCode,
    startedAt: startedAt,
    finishedAt: finishedAt,
    durationMs: stopwatch.elapsedMilliseconds,
    stdoutLog: _join(runDirectory, '$logName.stdout.log'),
    stderrLog: _join(runDirectory, '$logName.stderr.log'),
    error: failure?.toString(),
  );
}

Future<void> _copyOutput(
  Stream<List<int>> input,
  IOSink log,
  IOSink? mirror,
) async {
  await for (final bytes in input) {
    log.add(bytes);
    mirror?.add(bytes);
  }
  await log.flush();
}

Future<Map<String, Object?>> _readPerformanceSummary(String path) async {
  final decoded = jsonDecode(await File(path).readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('$path must contain a JSON object.');
  }
  final summary = _withoutFrameSamples(decoded);
  for (final field in ['phases', 'action_response_frames']) {
    final phases = summary[field];
    if (phases is Map<String, dynamic>) {
      summary[field] = {
        for (final entry in phases.entries)
          entry.key: entry.value is Map<String, dynamic>
              ? _withoutFrameSamples(entry.value as Map<String, dynamic>)
              : entry.value,
      };
    }
  }
  return summary;
}

Map<String, Object?> _withoutFrameSamples(Map<String, dynamic> value) {
  return Map<String, Object?>.from(value)..remove('frame_samples');
}

File _resolveFile(Directory repoRoot, String path) {
  final file = File(path);
  return file.isAbsolute ? file : File(_join(repoRoot.path, path));
}

String _relativePath(Directory repoRoot, String path) {
  final absolutePath = File(path).absolute.path;
  final rootPath = repoRoot.absolute.path;
  if (absolutePath == rootPath) {
    return '.';
  }
  if (absolutePath.startsWith('$rootPath${Platform.pathSeparator}')) {
    return absolutePath.substring(rootPath.length + 1);
  }
  return absolutePath;
}

String _join(String base, String relative) {
  return '$base${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';
}

String _lastSegment(String path) => path.split(Platform.pathSeparator).last;

class _StepResult {
  const _StepResult({
    required this.id,
    required this.command,
    required this.workingDirectory,
    required this.status,
    required this.exitCode,
    required this.startedAt,
    required this.finishedAt,
    required this.durationMs,
    required this.stdoutLog,
    required this.stderrLog,
    required this.error,
  });

  final String id;
  final List<String> command;
  final String workingDirectory;
  final String status;
  final int? exitCode;
  final DateTime startedAt;
  final DateTime finishedAt;
  final int durationMs;
  final String stdoutLog;
  final String stderrLog;
  final String? error;

  Map<String, Object?> toJson() => {
    'id': id,
    'command': command,
    'working_directory': workingDirectory,
    'status': status,
    'exit_code': exitCode,
    'started_at': startedAt.toIso8601String(),
    'finished_at': finishedAt.toIso8601String(),
    'duration_ms': durationMs,
    'stdout_log': stdoutLog,
    'stderr_log': stderrLog,
    if (error != null) 'error': error,
  };
}
