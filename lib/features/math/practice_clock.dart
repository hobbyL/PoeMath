import 'package:flutter/widgets.dart';

/// Stopwatch 仅记录前台练习用时，不把系统时钟跳变和后台停留算入学习时长。
class PracticeClock with WidgetsBindingObserver {
  PracticeClock() {
    WidgetsBinding.instance.addObserver(this);
  }

  final Stopwatch _watch = Stopwatch();
  int _previousMilliseconds = 0;
  bool _finished = false;
  VoidCallback? onPause;

  int get elapsedMilliseconds =>
      _previousMilliseconds + _watch.elapsedMilliseconds;
  int get elapsedSeconds => elapsedMilliseconds ~/ 1000;

  void start({int elapsedMilliseconds = 0}) {
    _previousMilliseconds = elapsedMilliseconds;
    _finished = false;
    _watch.reset();
    if (WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _watch.start();
    }
  }

  void finish() {
    _finished = true;
    _watch.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_finished) _watch.start();
    } else {
      _watch.stop();
      onPause?.call();
    }
  }

  void dispose() {
    _watch.stop();
    WidgetsBinding.instance.removeObserver(this);
  }
}
