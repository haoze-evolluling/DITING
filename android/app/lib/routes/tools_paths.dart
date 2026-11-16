/// The four probe tools pushed over the tools tab. Kept apart from `tools_routes.dart` so the hub
/// page can build the same paths without importing the route table that imports its pages.
abstract final class ToolPaths {
  static const speedTest = '/tools/speed-test';
  static const ping = '/tools/ping';
  static const dnsLookup = '/tools/dns-lookup';
  static const traceroute = '/tools/traceroute';
}
