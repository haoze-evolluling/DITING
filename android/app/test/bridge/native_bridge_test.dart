// Guards the Dart side of the native channels: validation order, JSON shape, enum
// fallbacks and the one-shot contracts the native side relies on.

import 'package:diting_shared/data/fonts/font_repository.dart';
import 'package:diting_android/data/native/apps_bridge.dart';
import 'package:diting_android/data/native/ca_bridge.dart';
import 'package:diting_android/data/native/db_health_bridge.dart';
import 'package:diting_android/data/native/deep_link_bridge.dart';
import 'package:diting_android/data/native/outbound_proxy_bridge.dart';
import 'package:diting_shared/data/native/platform_bridge.dart';
import 'package:diting_android/data/native/tile_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

part 'native_bridge_test_extras.dart';

void main() {
  group('原生通道', _nativeBridge);
  group('快捷开关启动请求', _tileBridge);
  group('深链通道', _deepLinkBridge);
  group('导入字体', _fontRepository);
  group('数据库写入健康度', _dbHealthBridge);
}

/// Guards the Dart side of three native channels: validation order, JSON shape, enum fallbacks
void _nativeBridge() {
  group('OutboundProxyConfig.validationError', () {
    OutboundProxyConfig base({
      String host = '127.0.0.1',
      int port = 7890,
      String proxyAppPackage = 'com.other.app',
      String username = '',
      String password = '',
    }) => OutboundProxyConfig(
      enabled: true,
      host: host,
      port: port,
      proxyAppPackage: proxyAppPackage,
      username: username,
      password: password,
    );

    const self = 'com.haoze.diting';
    const installed = {'com.other.app'};

    test('合法配置没有错误', () {
      expect(
        base().validationError(selfPackage: self, installedPackages: installed),
        isNull,
      );
    });

    test('::1 与 127.0.0.1 都接受，其余一律拒绝', () {
      for (final host in ['127.0.0.1', '::1']) {
        expect(
          base(host: host).validationError(selfPackage: self),
          isNull,
          reason: '$host 是合法的回环地址',
        );
      }
      for (final host in ['localhost', '0.0.0.0', '192.168.1.1', '[::1]', '']) {
        expect(
          base(host: host).validationError(selfPackage: self),
          '代理地址仅支持 127.0.0.1 或 ::1',
          reason: '$host 不该被接受',
        );
      }
    });

    test('端口边界：0 与 65536 拒绝，1 与 65535 接受', () {
      for (final port in [0, 65536, -1, 100000]) {
        expect(
          base(port: port).validationError(selfPackage: self),
          '代理端口必须在 1 到 65535 之间',
          reason: '$port 越界',
        );
      }
      for (final port in [1, 65535]) {
        expect(base(port: port).validationError(selfPackage: self), isNull);
      }
    });

    test('代理应用为空（含纯空白）报「请选择」', () {
      for (final value in ['', '   ', '\t']) {
        expect(
          base(proxyAppPackage: value).validationError(selfPackage: self),
          '请选择提供本地代理端口的应用',
        );
      }
    });

    test('不能选谛听自身', () {
      expect(
        base(proxyAppPackage: self).validationError(selfPackage: self),
        '不能选择 DITING 自身作为代理应用',
      );
    });

    test('未安装的应用报「未安装」', () {
      expect(
        base(proxyAppPackage: 'com.gone.app')
            .validationError(selfPackage: self, installedPackages: installed),
        '所选代理应用未安装',
      );
    });

    test('installedPackages 为 null 时跳过「未安装」判据', () {
      expect(
        base(proxyAppPackage: 'com.gone.app')
            .validationError(selfPackage: self, installedPackages: null),
        isNull,
      );
    });

    test('账号或密码 256 个字符报「过长」，255 通过', () {
      final ok = 'a' * 255;
      final tooLong = 'a' * 256;
      expect(base(username: ok).validationError(selfPackage: self), isNull);
      expect(base(password: ok).validationError(selfPackage: self), isNull);
      expect(
        base(username: tooLong).validationError(selfPackage: self),
        '代理账号或密码过长',
      );
      expect(
        base(password: tooLong).validationError(selfPackage: self),
        '代理账号或密码过长',
      );
    });

    test('判据顺序：地址先于端口、端口先于应用', () {
      expect(
        OutboundProxyConfig(
          enabled: true,
          host: 'bad',
          port: 0,
          proxyAppPackage: '',
        ).validationError(selfPackage: self),
        '代理地址仅支持 127.0.0.1 或 ::1',
      );
      expect(
        OutboundProxyConfig(
          enabled: true,
          port: 0,
          proxyAppPackage: '',
        ).validationError(selfPackage: self),
        '代理端口必须在 1 到 65535 之间',
      );
    });
  });

  group('OutboundProxyConfig.toEngineJson', () {
    test('protocol 用小写 storageValue', () {
      expect(
        const OutboundProxyConfig(protocol: OutboundProxyProtocol.socks5)
            .toEngineJson(),
        contains('"protocol":"socks5"'),
      );
      expect(
        const OutboundProxyConfig(protocol: OutboundProxyProtocol.http)
            .toEngineJson(),
        contains('"protocol":"http"'),
      );
    });

    test('enabled 是布尔而不是字符串', () {
      final json = const OutboundProxyConfig(enabled: true).toEngineJson();
      expect(json, contains('"enabled":true'));
      expect(json, isNot(contains('"enabled":"true"')));
    });

    test('字段集合固定且顺序稳定', () {
      final json = const OutboundProxyConfig().toEngineJson();
      expect(
        json,
        '{"enabled":false,"protocol":"socks5","host":"127.0.0.1",'
        '"port":7890,"username":"","password":""}',
      );
    });

    test('仅选中应用模式写入 scope 与去掉代理应用后的 packages', () {
      final json = const OutboundProxyConfig(
        enabled: true,
        proxyAppPackage: 'com.proxy',
        scope: OutboundProxyScope.apps,
        targetPackages: {'com.b', 'com.proxy', 'com.a'},
      ).toEngineJson();
      expect(json, endsWith(',"scope":"apps","packages":["com.a","com.b"]}'));
    });

    test('仅选中应用模式没有目标应用时校验失败', () {
      const config = OutboundProxyConfig(
        enabled: true,
        proxyAppPackage: 'com.proxy',
        scope: OutboundProxyScope.apps,
        targetPackages: {'com.proxy'},
      );
      expect(config.validationError(), isNotNull);
      expect(
        config.copyWith(targetPackages: {'com.a'}).validationError(),
        isNull,
      );
    });
  });

  group('OutboundProxyProtocol.fromStorageValue', () {
    test('未知值与 null 回落到 socks5', () {
      for (final value in ['quic', 'SOCKS5', 'HTTP', '', null]) {
        expect(
          OutboundProxyProtocol.fromStorageValue(value),
          OutboundProxyProtocol.socks5,
          reason: '$value 应当回落到 socks5',
        );
      }
    });
  });

  group('CaCertificateState.ready', () {
    test('只有 available 且 installed 同时为真才 ready', () {
      expect(
        const CaCertificateState(available: true, installed: true).ready,
        isTrue,
      );
      expect(
        const CaCertificateState(available: true, installed: false).ready,
        isFalse,
      );
      expect(
        const CaCertificateState(available: false, installed: true).ready,
        isFalse,
      );
      expect(
        const CaCertificateState(available: false, installed: false).ready,
        isFalse,
      );
    });
  });

  group('InstalledApp.matches', () {
    const app = InstalledApp(
      packageName: 'com.Example.Maps',
      label: '地图 Maps',
      isSystem: false,
      uid: 10123,
    );

    test('匹配标签与包名，大小写不敏感', () {
      for (final query in [
        '地图',
        'maps',
        'MAPS',
        'com.example',
        'COM.EXAMPLE.MAPS',
        'example',
      ]) {
        expect(app.matches(query), isTrue, reason: '$query 应当命中');
      }
    });
  });

  group('InstalledApp.fromMap', () {
    test('缺失字段取安全默认值', () {
      final app = InstalledApp.fromMap(const {});
      expect(app.packageName, '');
      expect(app.label, '');
      expect(app.isSystem, isFalse);
      expect(app.uid, -1);
    });

    test('isSystem 只认 boolean true，uid 接受 num', () {
      final app = InstalledApp.fromMap(const {
        'packageName': 'com.x',
        'label': 'X',
        'isSystem': 1,
        'uid': 10001.0,
      });
      expect(app.isSystem, isFalse);
      expect(app.uid, 10001);
    });
  });

  group('AppListFilter / AppListSort', () {
    const system = InstalledApp(
      packageName: 'com.android.systemui',
      label: 'System UI',
      isSystem: true,
      uid: 1000,
    );
    const userA = InstalledApp(
      packageName: 'com.b.app',
      label: 'Alpha',
      isSystem: false,
      uid: 10101,
    );
    const userB = InstalledApp(
      packageName: 'com.a.app',
      label: 'beta',
      isSystem: false,
      uid: 10102,
    );

    test('过滤枚举与 1.4.3 的四个名字一致', () {
      expect(AppListFilter.values.map((item) => item.storageValue), [
        'ALL',
        'SYSTEM',
        'USER',
        'SELECTED',
      ]);
      expect(AppListSort.values.map((item) => item.storageValue), [
        'LABEL_ASC',
        'LABEL_DESC',
        'PACKAGE_ASC',
        'PACKAGE_DESC',
      ]);
    });

    test('未知存储值回落到 USER / LABEL_ASC', () {
      expect(AppListFilter.fromStorageValue('SOMETHING'), AppListFilter.user);
      expect(AppListFilter.fromStorageValue(null), AppListFilter.user);
      expect(AppListSort.fromStorageValue('RANDOM'), AppListSort.labelAsc);
    });

    test('排序：标签升/降序，同级用包名升序兜底', () {
      final apps = [system, userA, userB];
      final asc = [...apps]..sort(AppListSort.labelAsc.compare);
      expect(asc.map((app) => app.label), ['Alpha', 'beta', 'System UI']);
      final desc = [...apps]..sort(AppListSort.labelDesc.compare);
      expect(desc.map((app) => app.label), ['System UI', 'beta', 'Alpha']);
      final byPackage = [...apps]..sort(AppListSort.packageAsc.compare);
      expect(byPackage.map((app) => app.packageName), [
        'com.a.app',
        'com.android.systemui',
        'com.b.app',
      ]);
      final byPackageDesc = [...apps]..sort(AppListSort.packageDesc.compare);
      expect(byPackageDesc.map((app) => app.packageName), [
        'com.b.app',
        'com.android.systemui',
        'com.a.app',
      ]);
    });
  });
}
