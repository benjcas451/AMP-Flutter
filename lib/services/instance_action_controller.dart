class InstanceActionController {
  final Map<String, _InstanceActionEntry> _entries = {};

  bool isLocked(String id) => isConfirming(id) || isBusy(id);

  bool isConfirming(String id) => _entries[id]?.confirming == true;

  bool isBusy(String id) => _entries[id]?.busy == true;

  bool isPendingStart(String id) =>
      _entries[id]?.busy == true && _entries[id]?.targetRunning == true;

  bool isPendingStop(String id) =>
      _entries[id]?.busy == true && _entries[id]?.targetRunning == false;

  void beginConfirmation(String id) {
    final current = _entries[id] ?? const _InstanceActionEntry();
    _entries[id] = current.copyWith(confirming: true);
  }

  void clearConfirmation(String id) {
    final current = _entries[id];
    if (current == null) return;
    final next = current.copyWith(confirming: false);
    if (next.busy || next.confirming) {
      _entries[id] = next;
      return;
    }
    _entries.remove(id);
  }

  void beginBusy(String id, {required bool running}) {
    _entries[id] = _InstanceActionEntry(
      busy: true,
      confirming: false,
      targetRunning: running,
    );
  }

  void finish(String id) => _entries.remove(id);

  void clearAll() => _entries.clear();
}

class _InstanceActionEntry {
  const _InstanceActionEntry({
    this.busy = false,
    this.confirming = false,
    this.targetRunning = false,
  });

  final bool busy;
  final bool confirming;
  final bool targetRunning;

  _InstanceActionEntry copyWith({
    bool? busy,
    bool? confirming,
    bool? targetRunning,
  }) => _InstanceActionEntry(
    busy: busy ?? this.busy,
    confirming: confirming ?? this.confirming,
    targetRunning: targetRunning ?? this.targetRunning,
  );
}
