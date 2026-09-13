enum CallTone {
  incoming(fileName: 'call_incoming_loop.wav', volume: 1.0),
  outgoing(fileName: 'call_outgoing_loop.wav', volume: 1.0);

  const CallTone({required this.fileName, required this.volume});

  final String fileName;
  final double volume;

  String get assetPath => 'audio/ui/v5/$fileName';
}
