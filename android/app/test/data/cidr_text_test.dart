import 'package:diting_android/data/vpn/cidr_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('接受合法的 CIDR', () {
    for (final value in [
      '10.0.0.0/8',
      '0.0.0.0/0',
      '255.255.255.255/32',
      '2001:db8::/32',
      '::/0',
      'fd00:abcd::1/128',
      ' 10.0.0.0/8 ',
    ]) {
      expect(isCidrText(value), isTrue, reason: value);
    }
  });

  test('拒绝非法的 CIDR', () {
    for (final value in [
      '',
      '10.0.0.0',
      '10.0.0.0/',
      '/8',
      '10.0.0.0/33',
      '10.0.0.0/08',
      '256.0.0.1/8',
      '01.2.3.4/8',
      '2001:db8::/129',
      'fe80::1%eth0/64',
      '10.0.0.0/8/9',
      'foo/8',
    ]) {
      expect(isCidrText(value), isFalse, reason: value);
    }
  });
}
