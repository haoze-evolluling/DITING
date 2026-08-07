package tunnel

import (
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"
)

// ─────────────────────────────────────────────────────────────────────────────
// WireGuard Config — JSON parsing + UAPI IPC builder.
//
// Kotlin serializes WireGuardConfig → JSON → passed to Engine.Start().
// This file parses that JSON and builds the UAPI IPC config string for
// wireguard-go's device.IpcSet().
// ─────────────────────────────────────────────────────────────────────────────

// WgConfig represents the JSON format of a WireGuard configuration.
// Must match Kotlin's WireGuardConfig serialization format.
type WgConfig struct {
	Interface WgInterface `json:"interfaceConfig"`
	Peers     []WgPeer    `json:"peers"`
}

// WgInterface is the [Interface] section.
type WgInterface struct {
	PrivateKey string   `json:"privateKey"`
	Address    []string `json:"address"`
	ListenPort *int     `json:"listenPort,omitempty"`
	DNS        []string `json:"dns"`
}

// WgPeer is a [Peer] section.
type WgPeer struct {
	PublicKey           string   `json:"publicKey"`
	PresharedKey        *string  `json:"presharedKey,omitempty"`
	Endpoint            *string  `json:"endpoint,omitempty"`
	AllowedIPs          []string `json:"allowedIPs"`
	PersistentKeepalive *int     `json:"persistentKeepalive,omitempty"`
}

// ParseWgConfigJSON parses a JSON string into WgConfig.
func ParseWgConfigJSON(jsonStr string) (*WgConfig, error) {
	var cfg WgConfig
	if err := json.Unmarshal([]byte(jsonStr), &cfg); err != nil {
		return nil, fmt.Errorf("parse WireGuard config JSON: %w", err)
	}
	if cfg.Interface.PrivateKey == "" {
		return nil, fmt.Errorf("WireGuard config missing private key")
	}
	if len(cfg.Peers) == 0 {
		return nil, fmt.Errorf("WireGuard config has no peers")
	}
	return &cfg, nil
}

// BuildIpcConfig constructs the WireGuard UAPI IPC configuration string
// from a parsed WgConfig.
//
// UAPI format expected by device.IpcSet():
//
//	private_key=<hex>
//	listen_port=<port>
//	replace_peers=true
//	public_key=<hex>
//	preshared_key=<hex>
//	endpoint=<ip:port>
//	persistent_keepalive_interval=<seconds>
//	replace_allowed_ips=true
//	allowed_ip=<cidr>
func BuildIpcConfig(cfg *WgConfig) (string, error) {
	// Convert private key from base64 to hex (UAPI uses hex encoding)
	privKeyHex, err := base64ToHex(cfg.Interface.PrivateKey)
	if err != nil {
		return "", fmt.Errorf("invalid private key: %w", err)
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("private_key=%s\n", privKeyHex))

	listenPort := 0
	if cfg.Interface.ListenPort != nil {
		listenPort = *cfg.Interface.ListenPort
	}
	sb.WriteString(fmt.Sprintf("listen_port=%d\n", listenPort))
	sb.WriteString("replace_peers=true\n")

	// Build peer configs
	for _, peer := range cfg.Peers {
		pubKeyHex, err := base64ToHex(peer.PublicKey)
		if err != nil {
			return "", fmt.Errorf("invalid peer public key: %w", err)
		}

		sb.WriteString(fmt.Sprintf("public_key=%s\n", pubKeyHex))

		if peer.PresharedKey != nil && *peer.PresharedKey != "" {
			pskHex, err := base64ToHex(*peer.PresharedKey)
			if err != nil {
				return "", fmt.Errorf("invalid preshared key: %w", err)
			}
			sb.WriteString(fmt.Sprintf("preshared_key=%s\n", pskHex))
		}

		if peer.Endpoint != nil && *peer.Endpoint != "" {
			sb.WriteString(fmt.Sprintf("endpoint=%s\n", *peer.Endpoint))
		}

		if peer.PersistentKeepalive != nil && *peer.PersistentKeepalive > 0 {
			sb.WriteString(fmt.Sprintf("persistent_keepalive_interval=%d\n", *peer.PersistentKeepalive))
		}

		sb.WriteString("replace_allowed_ips=true\n")
		for _, cidr := range peer.AllowedIPs {
			cidr = strings.TrimSpace(cidr)
			if cidr != "" {
				sb.WriteString(fmt.Sprintf("allowed_ip=%s\n", cidr))
			}
		}
	}

	return sb.String(), nil
}

// base64ToHex converts a base64-encoded WireGuard key to hex (UAPI format).
func base64ToHex(b64 string) (string, error) {
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return "", err
	}
	if len(raw) != 32 {
		return "", fmt.Errorf("key must be 32 bytes, got %d", len(raw))
	}
	return hex.EncodeToString(raw), nil
}
