library;

import 'package:diting_android/data/agent/rust_agent_core.dart';

String sealApiKey(String plain) => RustAgentCore.instance.sealKey(plain);

String openApiKey(String sealed) => RustAgentCore.instance.openKey(sealed);
