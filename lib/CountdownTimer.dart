class CountdownTimer {
  int _ticket = 0;
  bool complete = false;

  Future<void> delay(Duration delay) async {
    if (complete) {
      throw Exception("Already complete");
    }
    _ticket++;
    int ticket = _ticket;
    await Future.delayed(delay);
    if (ticket == _ticket) {
      complete = true;
      return;
    } else {
      throw Exception("Cancelled");
    }
  }

  /**
   * Sets up the CountdownTimer so it can be used again.  Any pending task will be cancelled.
   */
  void reset() {
    _ticket++;
    complete = false;
  }
}