/// Pure scheduling policy for playback commands.
///
/// The coordinator still executes operations. This class only preserves the
/// existing classification of urgent transport commands and source requests
/// that may supersede older queued source mutations.
class TransportCommandPolicy {
  const TransportCommandPolicy._();

  static const Set<String> _transportPriorityCommands = {
    'toggle',
    'pause',
    'stop',
    'seek',
    'play',
    'next',
    'previous',
  };

  static const Set<String> _supersedingSourceCommands = {
    'play',
    'next',
    'previous',
  };

  static bool hasTransportPriority(String command) =>
      _transportPriorityCommands.contains(command);

  static bool supersedesPendingSource(String command) =>
      _supersedingSourceCommands.contains(command);
}
