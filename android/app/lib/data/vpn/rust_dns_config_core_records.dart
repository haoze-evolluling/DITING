part of 'rust_dns_config_core.dart';

typedef ProviderRow = ({
  String id,
  String name,
  String protocolStorage,
  String url,
  String host,
  int port,
});

typedef BootstrapEntryRow = ({String id, String name, String ip});

typedef BootstrapRow = ({String id, String name, String ip, bool enabled});

typedef TunnelDocument = ({
  String mode,
  String document,
  List<ProviderRow> providers,
  List<BootstrapEntryRow> bootstrap,
});
