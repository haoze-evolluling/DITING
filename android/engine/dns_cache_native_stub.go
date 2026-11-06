//go:build !cgo

// dns_cache_native_stub.go keeps the engine buildable without a C toolchain.
//
// The Rust DNS cache wire kernel is required for caching, so this build flavour compiles but
// refuses every cache write and every lookup: answers go straight to the resolver. Android builds
// cgo (the shipped AAR and the three .so files), so this only affects `go build`/`go vet` on a
// machine without a C compiler. It never changes an answer, only whether it is remembered.

package tunnel

// The stub reports "cannot cache" for every call. There is no second wire parser in Go to fall
// back to: that is what the kernel replaced.
func nativeQuestionKey(rawQuery, dst []byte) (key []byte, nameLen int, qtype, qclass uint16, ok bool) {
	return nil, 0, 0, 0, false
}

func nativeParseResponse(rawResponse []byte) (*dnsCacheResponseMeta, bool) {
	return nil, false
}

func nativePatchResponse(rawResponse []byte, offsets []uint16, queryID uint16, ttl uint32) []byte {
	return nil
}
