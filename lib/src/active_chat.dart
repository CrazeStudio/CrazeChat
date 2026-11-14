/// Tracks which conversations are open (through their realtime socket) so the
/// in-app message banner does not announce messages for a chat the user is
/// already reading.
class ActiveChat {
  const ActiveChat._();

  static final Map<String, int> _open = <String, int>{};

  static bool isOpen(String chatId) => (_open[chatId] ?? 0) > 0;

  static void opened(String chatId) {
    _open[chatId] = (_open[chatId] ?? 0) + 1;
  }

  static void closed(String chatId) {
    final next = (_open[chatId] ?? 0) - 1;
    if (next <= 0) {
      _open.remove(chatId);
    } else {
      _open[chatId] = next;
    }
  }
}
