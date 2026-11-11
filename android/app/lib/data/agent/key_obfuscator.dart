/// XOR masks plus Base64, byte-identical to the legacy `KeyObfuscator.kt`:
/// `agent_ai_providers_json` holds legacy ciphertext. Obfuscation, not encryption.
///
/// The masks live in `rust/diting-agent-core/src/secret.rs`; keeping them there is what stops the
/// two apps from disagreeing about keys saved by an upgrade install.
library;

import 'package:diting_android/data/agent/rust_agent_core.dart';

String sealApiKey(String plain) => RustAgentCore.instance.sealKey(plain);

/// Restores an obfuscated key. Undecodable input yields an empty string instead of throwing, so one
/// bad row cannot break the whole provider list.
String openApiKey(String sealed) => RustAgentCore.instance.openKey(sealed);
