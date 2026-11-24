part 'model.g.dart';

class Model {
  Model(this.value);

  final int value;

  String encode() => _$encodeModel(this);
}

/// Referenced only from the generated part → must stay alive.
int _usedOnlyByGenerated(int value) => value + 1;

/// Nobody calls this → FLAGGED (hand-written).
int _unusedHandWritten() => 0;
