import 'dart:async';

/// Calls [onReady] exactly once: when [deviceIdStream] emits [targetDevId],
/// or after [timeout] – whichever comes first.
///
/// The boolean [_fired] guard ensures [onReady] is never called twice even if
/// the stream event and the timer land in the same event-loop batch.
///
/// Returns a cancel function. Call it (e.g. from widget dispose) to prevent
/// [onReady] from firing if it hasn't already.
void Function() waitFirstDpOrTimeout({
  required Stream<String> deviceIdStream,
  required String targetDevId,
  required Duration timeout,
  required void Function() onReady,
}) {
  StreamSubscription<String>? sub;
  Timer? timer;
  var fired = false;

  void fire() {
    if (fired) return;
    fired = true;
    sub?.cancel();
    timer?.cancel();
    onReady();
  }

  sub = deviceIdStream
      .where((id) => id == targetDevId)
      .take(1)
      .listen((_) => fire(), onError: (_) {/* stream errors don't fire; timeout handles it */});

  timer = Timer(timeout, fire);

  return () {
    fired = true;
    sub?.cancel();
    timer?.cancel();
  };
}
