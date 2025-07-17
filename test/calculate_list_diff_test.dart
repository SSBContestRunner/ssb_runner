import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/common/calculate_list_diff.dart';

void main() {
  test('test no match', () {
    expect(
      calculateMismatch(answer: "ABCD", submit: "EF"),
      4,
    ); // Already uses named args
  });

  test('test part of match', () {
    expect(calculateMismatch(answer: "ABCD", submit: "BCF"), 2); // Updated
  });

  test('test multipart of match', () {
    expect(
      calculateMismatch(answer: "ABCDEFGHIJ", submit: "CDXEFGHYW"),
      4,
    ); // Updated
  });

  test('test misorder', () {
    expect(calculateMismatch(answer: "ABC", submit: "BCA"), 1); // Updated
    expect(calculateMismatch(answer: "ABCD", submit: "DCBA"), 3); // Updated
  });

  test('test match', () {
    expect(calculateMismatch(answer: "ABCD", submit: "ABCD"), 0); // Updated
  });

  test('test real case', () {
    expect(calculateMismatch(answer: "BI1QJQ", submit: "BY1QQQ"), 2);
  });
}
