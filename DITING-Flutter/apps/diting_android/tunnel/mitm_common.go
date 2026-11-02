// mitm_common.go defines shared data structures, interfaces, and HTTP utility functions for MITM interception.
//
// Core Interfaces & Filtering Helpers:
// - adBlockChecker: Abstraction allowing the MITM handler to query the engine's policy rules and resolve domain IPs.
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

func wrapResponseForInjection(resp *http.Response, host string) {
	// Nothing to inject when no cosmetic rule exists at all; leaving the body
	// untouched also keeps Content-Length and Content-Encoding intact.
	if cosmeticRulesEmpty() {
		return
	}
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

	resp.Body = io.NopCloser(NewInjectingReader(bodyReader, host))
	resp.ContentLength = -1
	resp.Header.Del("Content-Length")
	resp.Header.Del("Content-Encoding")
	resp.Header.Del("Transfer-Encoding")
	resp.Header.Del("Content-Security-Policy")
	resp.Header.Del("Content-Security-Policy-Report-Only")
	resp.TransferEncoding = nil
	resp.Uncompressed = true
	// The body length is only known after injection, so the response cannot carry
	// a Content-Length, and buffering it just to compute one would defeat the
	// streaming design on large pages. That leaves connection-close delimiting as
	// the only option: net/http's Response.Write only adds "Connection: close"
	// automatically when ContentLength == -1 && !Uncompressed, and we deliberately
	// keep Uncompressed = true, so Close must be set here explicitly. Without it
	// the response goes out with no Content-Length, no Transfer-Encoding and no
	// Connection header, and an HTTP/1.1 keep-alive client waits for a body
	// boundary that never arrives (the relay only closes the socket on
	// resp.Close), so the page never finishes loading.
	resp.Close = true
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

// privateIPv4Nets are the RFC 1918 ranges, parsed once instead of on every flow.
var privateIPv4Nets = func() []*net.IPNet {
	var nets []*net.IPNet
	for _, cidrStr := range []string{"10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"} {
		_, cidr, _ := net.ParseCIDR(cidrStr)
		nets = append(nets, cidr)
	}
	return nets
}()

func isPrivateIP(ip net.IP) bool {
	for _, cidr := range privateIPv4Nets {
		if cidr.Contains(ip) {
			return true
		}
	}
	return false
}
