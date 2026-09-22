// mitm_cosmetic_inject.go provides streaming HTML rewriting for cosmetic ad-blocking CSS injection.
//
// Injection Architecture:
// - Scans the uncompressed response stream for <head> tags (case-insensitive) using a sliding buffer.
// - Injects a lightweight <link rel="stylesheet"> pointing to the in-memory asset host (local.pwhs.app),
//   avoiding inline injection of 50-100KB CSS payloads and enabling client browser caching.

package tunnel

import (
	"bytes"
	"io"
	"strings"
	"sync"
)

const injectionTags = `<link rel="stylesheet" href="https://local.pwhs.app/cosmetic.css">`

var headTagBytes = []byte("<head")

const scanLimit = 16 * 1024

var (
	cosmeticMu  sync.RWMutex
	cosmeticCSS string
)

func SetCosmeticCSS(css string) {
	cosmeticMu.Lock()
	cosmeticCSS = css
	cosmeticMu.Unlock()
	logf("Cosmetic CSS updated: %d bytes", len(css))
}

func ShouldInjectHTML(contentType string) bool {
	ct := strings.ToLower(contentType)
	return strings.Contains(ct, "text/html")
}

type injectingReader struct {
	upstream     io.Reader
	injected     bool
	pending      []byte
	carry        []byte
	scannedBytes int
}

func NewInjectingReader(upstream io.Reader) io.Reader {
	return &injectingReader{
		upstream: upstream,
	}
}

func (r *injectingReader) Read(p []byte) (int, error) {
	if len(r.pending) > 0 {
		n := copy(p, r.pending)
		r.pending = r.pending[n:]
		return n, nil
	}

	n, err := r.upstream.Read(p)
	if n == 0 || r.injected {
		return n, err
	}

	var data []byte
	if len(r.carry) > 0 {
		data = make([]byte, len(r.carry)+n)
		copy(data, r.carry)
		copy(data[len(r.carry):], p[:n])
		r.carry = nil
	} else {
		data = make([]byte, n)
		copy(data, p[:n])
	}

	r.scannedBytes += len(data)
	if r.scannedBytes > scanLimit {
		r.injected = true
		nn := copy(p, data)
		if nn < len(data) {
			r.pending = data[nn:]
		}
		if err == io.EOF && len(r.pending) > 0 {
			return nn, nil
		}
		return nn, err
	}

	lower := bytes.ToLower(data)
	idx := bytes.Index(lower, headTagBytes)

	if idx < 0 {

		carryLen := len(headTagBytes) - 1
		if carryLen > len(data) {
			carryLen = len(data)
		}
		endBytes := bytes.ToLower(data[len(data)-carryLen:])
		hasPartial := false
		for i := 1; i <= carryLen; i++ {
			if bytes.Equal(endBytes[carryLen-i:], headTagBytes[:i]) {
				r.carry = make([]byte, i)
				copy(r.carry, data[len(data)-i:])
				hasPartial = true
				outData := data[:len(data)-i]
				if len(outData) == 0 {

					return 0, err
				}
				nn := copy(p, outData)
				if nn < len(outData) {
					r.pending = outData[nn:]
				}
				if err == io.EOF && len(r.pending) > 0 {
					return nn, nil
				}
				return nn, err
			}
		}
		if !hasPartial {
			nn := copy(p, data)
			if nn < len(data) {
				r.pending = data[nn:]
			}
			if err == io.EOF && len(r.pending) > 0 {
				return nn, nil
			}
			return nn, err
		}

		nn := copy(p, data)
		return nn, err
	}

	closeIdx := bytes.IndexByte(lower[idx:], '>')
	if closeIdx < 0 {

		r.carry = make([]byte, len(data)-idx)
		copy(r.carry, data[idx:])
		outData := data[:idx]
		if len(outData) == 0 {
			return 0, err
		}
		nn := copy(p, outData)
		if nn < len(outData) {
			r.pending = outData[nn:]
		}
		if err == io.EOF && len(r.pending) > 0 {
			return nn, nil
		}
		return nn, err
	}

	tagEnd := idx + closeIdx + 1
	return r.doInject(p, data, tagEnd, err)
}

func (r *injectingReader) doInject(p []byte, data []byte, tagEnd int, upstreamErr error) (int, error) {
	r.injected = true

	script := []byte(injectionTags)

	before := data[:tagEnd]
	after := data[tagEnd:]

	total := len(before) + len(script) + len(after)

	if total <= len(p) {
		n := copy(p, before)
		n += copy(p[n:], script)
		n += copy(p[n:], after)
		return n, upstreamErr
	}

	var combined []byte
	combined = append(combined, before...)
	combined = append(combined, script...)
	combined = append(combined, after...)

	n := copy(p, combined)
	r.pending = combined[n:]

	if upstreamErr == io.EOF && len(r.pending) > 0 {
		return n, nil
	}
	return n, upstreamErr
}
