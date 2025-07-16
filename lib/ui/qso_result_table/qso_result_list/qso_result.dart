class QsoResult {
  final QsoResultField call;
  final QsoResultField rst;
  final QsoResultField exchange;
  final String utc;
  final String corrections;

  QsoResult({
    required this.call,
    required this.rst,
    required this.exchange,
    required this.utc,
    required this.corrections,
  });
}

class QsoResultField {
  final String data;
  final bool isCorrect;

  QsoResultField({required this.data, required this.isCorrect});
}