import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_contest_runner/contest_run/log/extract_prefix.dart';

void main() {
  test('test 3x3', () {
    expect(extractPrefix('BI1QJQ'), 'BI1');
    expect(extractPrefix('BG2XTW'), 'BG2');

    expect(extractPrefix('JA1OOO'), 'JA1');
    expect(extractPrefix('JG1OXK'), 'JG1');
    expect(extractPrefix('JJ7JJG'), 'JJ7');
    expect(extractPrefix('7K1GGG'), '7K1');
  });

  test('test 1x1', () {
    expect(extractPrefix('B1Z'), 'B1');
    expect(extractPrefix('B2C'), 'B2');
    expect(extractPrefix('M4T'), 'M4');
  });

  test('test 2x2', () {
    expect(extractPrefix('K1CT'), 'K1');
    expect(extractPrefix('K6ND'), 'K6');
  });

  test('test 3x1', () {
    expect(extractPrefix('NT6X'), 'NT6');
    expect(extractPrefix('YT1A'), 'YT1');
  });

  test('test 3x2', () {
    expect(extractPrefix('AK6AM'), 'AK6');
    expect(extractPrefix('BG7SA'), 'BG7');
  });

  test('test special', () {
    expect(extractPrefix('B100IARU'), 'B100');
    expect(extractPrefix('EM100WJZ'), 'EM100');
  });
}
