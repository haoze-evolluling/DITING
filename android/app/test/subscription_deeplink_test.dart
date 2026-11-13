// Pure parser for the external subscription-import deep link. No native channel is involved, so the
// accepted grammar is pinned here.

import 'package:diting_android/data/subscriptions/subscription_deeplink.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSubscriptionDeepLink', () {
    test('接受 install-config 并解码 url 参数', () {
      expect(
        parseSubscriptionDeepLink(
          'diting://install-config?url=https%3A%2F%2Fexample.com%2Frules.txt',
        ),
        'https://example.com/rules.txt',
      );
    });

    test('install-sub 为等价别名', () {
      expect(
        parseSubscriptionDeepLink(
          'diting://install-sub?url=https%3A%2F%2Fexample.com%2Frules.txt',
        ),
        'https://example.com/rules.txt',
      );
    });

    test('未编码的 http 地址也能解析', () {
      expect(
        parseSubscriptionDeepLink('diting://install-config?url=http://a.com/r.txt'),
        'http://a.com/r.txt',
      );
    });

    test('忽略 scheme 大小写并去除首尾空白', () {
      expect(
        parseSubscriptionDeepLink(
          '  DITING://install-config?url=https%3A%2F%2Fa.com%2Fr.txt  ',
        ),
        'https://a.com/r.txt',
      );
    });

    test('拒绝非 diting scheme', () {
      expect(
        parseSubscriptionDeepLink(
          'clash://install-config?url=https%3A%2F%2Fa.com%2Fr.txt',
        ),
        isNull,
      );
    });

    test('拒绝未知 host', () {
      expect(
        parseSubscriptionDeepLink(
          'diting://other?url=https%3A%2F%2Fa.com%2Fr.txt',
        ),
        isNull,
      );
    });

    test('缺少 url 参数返回 null', () {
      expect(parseSubscriptionDeepLink('diting://install-config'), isNull);
    });

    test('空 url 返回 null', () {
      expect(
        parseSubscriptionDeepLink('diting://install-config?url='),
        isNull,
      );
    });

    test('非 http(s) 地址返回 null', () {
      expect(
        parseSubscriptionDeepLink(
          'diting://install-config?url=ftp%3A%2F%2Fa.com%2Fr.txt',
        ),
        isNull,
      );
    });

    test('无法解析的字符串返回 null', () {
      expect(parseSubscriptionDeepLink('not a uri'), isNull);
    });
  });
}
