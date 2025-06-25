import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_contest_runner/common/calculate_list_diff.dart';

void main() {
  test('test no match', () {
    expect(calculateMismatch("ABCD", "EF"), 4); // 4
  });

  test('test part of match', () {
    expect(calculateMismatch("ABCD", "BCF"), 2); // 2
  });

  test('test multipart of match', () {
    expect(calculateMismatch("ABCDEFGHIJ", "CDXEFGHYW"), 4); // 4
  });

  test('test misorder', () {
    expect(calculateMismatch("ABC", "BCA"), 1); // 1
    expect(calculateMismatch("ABCD", "DCBA"), 3); // 3
  });

  test('test match', () {
    expect(calculateMismatch("ABCD", "ABCD"), 0); // 0
  });

  test('test real case', () {
    expect(calculateMismatch("BI1QJQ", "BY1QQQ"), 2); // 2
  });
}
