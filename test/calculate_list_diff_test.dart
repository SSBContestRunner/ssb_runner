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

  group('shouldRepeatCallsign', () {
    test('完全抄对时不重放', () {
      expect(
        shouldRepeatCallsign(answer: "B100IARU", submit: "B100IARU"),
        isFalse,
      );
    });

    test('抄到对方呼号开头时重放，即使超过阈值', () {
      // 只抄到前缀 B100，diff = 4 > 阈值 3，仍需重放
      expect(shouldRepeatCallsign(answer: "B100IARU", submit: "B100"), isTrue);
      expect(shouldRepeatCallsign(answer: "B100IARU", submit: "B10"), isTrue);
    });

    test('差异未超过阈值时重放', () {
      expect(shouldRepeatCallsign(answer: "BI1QJQ", submit: "BY1QQQ"), isTrue);
      expect(shouldRepeatCallsign(answer: "ABCD", submit: "DCBA"), isTrue);
    });

    test('差异超过阈值且非前缀时不重放', () {
      expect(shouldRepeatCallsign(answer: "ABCD", submit: "EF"), isFalse);
      expect(
        shouldRepeatCallsign(answer: "B100IARU", submit: "X9ZZZZ"),
        isFalse,
      );
    });

    test('空输入不重放', () {
      expect(shouldRepeatCallsign(answer: "B100IARU", submit: ""), isFalse);
    });
  });
}
