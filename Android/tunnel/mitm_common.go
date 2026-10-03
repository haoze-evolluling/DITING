// mitm_common.go defines shared data structures, interfaces, and HTTP utility functions for MITM interception.
//
// Core Interfaces & Filtering Helpers:
// - adBlockChecker: Abstraction allowing the MITM handler to query the engine's trie and resolve domain IPs.
// - requestAcceptsHTML: Inspects client Accept headers to conditionally strip Accept-Encoding, allowing HTML responses
//   to arrive uncompressed for streaming cosmetic CSS tag injection.

package tunnel

import (
	"bytes"
	"compress/flate"
	"compress/gzip"
	"compress/zlib"
	"io"
	"net"
	"net/http"
	"strings"
)

type adBlockChecker interface {
	IsDomainBlocked(host string) bool
	lookupIP(host string) (net.IP, error)
	domainForIP(ip net.IP) string
}

func requestAcceptsHTML(req *http.Request) bool {
	accept := req.Header.Get("Accept")
	return strings.Contains(strings.ToLower(accept), "text/html")
}

func wrapResponseForInjection(resp *http.Response) {
	encoding := strings.ToLower(strings.TrimSpace(resp.Header.Get("Content-Encoding")))

	var bodyReader io.Reader
	switch encoding {
	case "", "identity":
		bodyReader = resp.Body
	case "gzip":
		gr, err := gzip.NewReader(resp.Body)
		if err != nil {
			return
		}
		bodyReader = gr
	case "deflate":

		raw, err := io.ReadAll(resp.Body)
		if err != nil {
			return
		}
		if zr, err := zlib.NewReader(bytes.NewReader(raw)); err == nil {
			bodyReader = zr
		} else {
			bodyReader = flate.NewReader(bytes.NewReader(raw))
		}
	default:
		return
	}

	resp.Body = io.NopCloser(NewInjectingReader(bodyReader))
	resp.ContentLength = -1
	resp.Header.Del("Content-Length")
	resp.Header.Del("Content-Encoding")
	resp.Header.Del("Transfer-Encoding")
	resp.Header.Del("Content-Security-Policy")
	resp.Header.Del("Content-Security-Policy-Report-Only")
	resp.TransferEncoding = nil
	resp.Uncompressed = true
}

func isLoopbackOrInternal(hostname string) bool {
	lower := strings.ToLower(hostname)
	if lower == "localhost" || lower == "0.0.0.0" || lower == "::" {
		return true
	}

	ip := net.ParseIP(hostname)
	if ip == nil {
		return false
	}

	return ip.IsLoopback() || ip.IsUnspecified() || ip.IsLinkLocalUnicast() || isPrivateIP(ip)
}

func isPrivateIP(ip net.IP) bool {
	privateRanges := []string{
		"10.0.0.0/8",
		"172.16.0.0/12",
		"192.168.0.0/16",
	}
	for _, cidrStr := range privateRanges {
		_, cidr, _ := net.ParseCIDR(cidrStr)
		if cidr.Contains(ip) {
			return true
		}
	}
	return false
}
