<p align="right">🌐 <b>English</b> | <a href="README.zh-CN.md">简体中文</a></p>

# DITING

DITING is a local DNS resolution optimization and network traffic filtering tool built for Android. By default, it establishes a lightweight local channel through Android `VpnService` that takes over only DNS requests; it can also optionally enable a Go userspace network stack for fine-grained per-app network control and optional HTTPS traffic inspection. All resolution, filtering, and statistics are performed locally on the device — secure, transparent, and with no remote data collection of any kind.

***

## Key Features

### 📡 DNS Resolution & Upstream Strategies

- **Multi-protocol support**: standard DNS (UDP/TCP 53), DNS-over-HTTPS (DoH), and DNS-over-TLS (DoT).
- **Multi-strategy scheduling**: four resolution modes — **Single Provider**, **Smart Selection** (dynamic weighting based on recent latency and success rate), **Fastest Response** (concurrent racing), and **Sequential Fallback** (primary/backup disaster recovery).
- **Provider management**: ships with major public DNS providers built in; freely add and edit custom DoH/DoT nodes, and flexibly customize the home-screen provider list.
- **Bootstrap resolution**: supports built-in and custom Bootstrap IPs for resolving upstream domains, avoiding recursive resolution deadlocks with smart weight-based optimization.

### ⚡ Smart Caching & Resilience

- **Flexible cache policies**: multiple presets — follow upstream TTL, standard balance, and high hit-rate — balancing resolution freshness and response efficiency.
- **Optimistic fallback**: when an upstream lookup fails or times out, briefly reuses expired cache entries that are still within their validity window, keeping weak-network environments usable.

### 🛡️ Rule Filtering & Address Overrides

- **Multi-dimensional rules**: domain allow/block lists, IPv4/IPv6 address overrides, and CNAME redirection.
- **AdGuard rule subscriptions**: supports AdGuard DNS format subscriptions with rule groups, mirror-site template acceleration, and scheduled background auto-updates.
- **Flexible block responses**: four modes — NXDOMAIN, NODATA, REFUSED, and zero-address (`0.0.0.0` / `::`).

### 🔒 Per-App Control & Traffic Splitting

- **Excluded apps**: bypass the VPN per app so they use the system network and system DNS directly.
- **Network blocking**: drop all network connections for selected apps, preventing unauthorized background connections.
- **App whitelist access**: only allow specified apps to connect to valid IPs resolved from whitelisted domains, blocking other direct connections.
- **Outbound proxy integration**: forward filtered traffic to a local SOCKS5 or HTTP CONNECT proxy.

### 🔍 HTTPS Traffic Inspection (Optional Advanced Feature)

- **On-demand decryption**: built on a Go userspace network stack (gVisor netstack) and a local CA root certificate; only decrypts and performs URL-level rule matching for apps the user explicitly selects and trusts.
- **Safety-adaptive bypass**: automatically passes through connections with certificate pinning, mutual TLS, EV certificates, and sensitive domains.
- **QUIC / HTTP/3 control**: can block QUIC traffic for target apps, guiding clients to fall back smoothly to TCP for analysis.

### 📊 Full Observability & Utilities

- **Real-time monitoring dashboards**: DNS request logs, HTTP inspection logs, cache details, racing speed tests, provider health, and rule interception statistics.
- **Per-app traffic insight**: per-app traffic metering and rankings, plus an optional real-time speed indicator in the status bar.
- **Floating log window**: view live background resolution activity in a floating window.
- **Built-in diagnostics**: DNS lookup and ping tools, with configurable log retention and one-tap data cleanup.
- **Convenient management**: import/export custom configurations and rule subscriptions, plus an Android Quick Settings tile.

### ✨ Personalization & Advanced Tools

- **Optional AI assistant**: bring-your-own LLM API for on-demand domain and traffic-summary analysis; disabled by default and configured entirely by the user.
- **IPv6 mode**: toggle AAAA resolution behavior to match your network environment.
- **Localization & themes**: Chinese/English UI, preset color palettes with light/dark modes and custom backgrounds, plus searchable settings.
- **In-app updates**: built-in version update checks.

***

## Architecture & Security Boundaries

- **Default mode (DNS-Only)**: routes only DNS query traffic; regular app data and TCP/UDP transfers are never proxied — lightweight and power-efficient.
- **Advanced mode (Go userspace network stack)**: when HTTPS inspection, network blocking, or app whitelist access is enabled, the Go tunnel takes over the relevant traffic for precise handling; all other unconfigured apps are forwarded unchanged.
- **Privacy guarantee**: all DNS caches, rule libraries, logs, and configuration data are stored entirely on the device — no data uploads, no telemetry.

***

## Requirements & Build

### Runtime Environment

- **Minimum version**: Android 10 (API 29)
- **Target version**: Target SDK 36
- **Architecture support**: `arm64-v8a`

### Development & Build Requirements

- Android Studio and the Android SDK
- JDK 11 or later (the JBR bundled with Android Studio is recommended)
- (Optional) To rebuild the Go tunnel AAR, you need Go 1.23+, `gomobile`, and the Android NDK. See the [Go AAR Build Notes](docs/development/aar-build-notes.md).

### Build Commands

Using the Gradle Wrapper directly (recommended — works on Windows, Linux, and CI):

```bash
# Build a debug APK
./gradlew :app:assembleDebug --console=plain    # use gradlew.bat on Windows

# Build a release APK (minified)
./gradlew :app:assembleRelease --console=plain
```

On Windows you can also run the interactive helper `build_apk.bat`: pick Debug/Release and it builds via the wrapper, locates the output APK, and optionally installs it over ADB (wireless `IP:PORT` connections supported).

Build output paths:

- Standard APK: `app/build/outputs/apk/<buildType>/app-<buildType>.apk`
- Versioned installers: `app/build/outputs/apk/versioned/<buildType>/DITING-<buildType>-v<versionName>.apk`

***

## Tech Stack

- **UI & architecture**: Kotlin / Jetpack Compose / Material 3 / Coroutines & Flow / Navigation Compose
- **Userspace network stack**: Go / gVisor netstack / `gomobile`
- **Networking & system services**: Android `VpnService` / OkHttp / WorkManager
- **Local storage**: Room / Paging 3 / DataStore

***

## Sponsorship

If you find this project helpful, you're welcome to support it through the payment QR codes below. Please include your nickname or preferred display name with your payment so it can be added to the sponsor list.

| Alipay | WeChat Pay |
| :---: | :---: |
| ![Alipay QR code](docs/assets/alipay_code.png) | ![WeChat Pay QR code](docs/assets/wechatpay_code.png) |

For how the sponsor and co-builder lists are dynamically maintained, see the [cloud-managed contributor list notes](docs/features/recognition-members.md).

***

## Author & License

- **Author**: [haoze-evolluling](https://github.com/haoze-evolluling)
- **License**: This project is released under the [GNU General Public License v3.0 (GPL-3.0)](https://www.gnu.org/licenses/gpl-3.0.html).
