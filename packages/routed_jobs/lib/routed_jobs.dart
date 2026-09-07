/// Laravel-inspired jobs and queue primitives for Routed applications.
///
/// The public API deliberately contains no Stem types. Stem is used only as
/// the portable execution engine behind [RoutedJobs]. Queue adapters implement
/// [JobQueue] and host runtimes decide how messages are acknowledged,
/// retried, or dead-lettered.
library;

import 'dart:async';

import 'package:artisanal/args.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_jobs/src/command_output.dart';
import 'package:stem/portable.dart' as stem;
// Beat is not yet exported from Stem's portable barrel. Keep this import
// private to Routed until the portable scheduler surface lands upstream.
// ignore: implementation_imports
import 'package:stem/src/core/clock.dart' as stem_clock;
// Beat is not yet exported from Stem's portable barrel. Keep this import
// private to Routed until the portable scheduler surface lands upstream.
// ignore: implementation_imports
import 'package:stem/src/scheduler/beat.dart' as stem_beat;

part 'src/context.dart';
part 'src/commands.dart';
part 'src/definition.dart';
part 'src/message.dart';
part 'src/provider.dart';
part 'src/queue.dart';
part 'src/result.dart';
part 'src/routed_jobs.dart';
part 'src/scheduler.dart';
part 'src/stem_beat_runner.dart';
