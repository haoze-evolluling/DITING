//go:build cgo

// dns_cache_native_container.go drives the container entry points of
// rust/diting-dns-cache-core through the C ABI in that crate's src/ffi.rs.
//
// Payload layouts are documented at the top of rust/diting-dns-cache-core/src/payload.rs. Every
// payload starts with a layout byte and every list is length-prefixed, so a stale pair is a loud
// decode error instead of a misread field.

package tunnel

/*
#include <stdint.h>
#include <stddef.h>

typedef void* (*diting_dnscache_new_fn)(const void*, size_t, uint8_t*, void**, size_t*);
typedef uint32_t (*diting_dnscache_update_fn)(void*, const void*, size_t, uint8_t*, void**, size_t*);
typedef void (*diting_dnscache_handle_fn)(void*);
typedef uint32_t (*diting_dnscache_get_fn)(void*, const void*, size_t, uint8_t, void**, size_t*);
typedef uint8_t (*diting_dnscache_put_fn)(void*, const void*, size_t, const void*, size_t);
typedef uint8_t (*diting_dnscache_refresh_fn)(void*, const void*, size_t);
typedef void (*diting_dnscache_refresh_done_fn)(void*, const void*, size_t);
typedef void (*diting_dnscache_payload_fn)(void*, void**, size_t*);
typedef void (*diting_dnscache_snapshot_fn)(void*, uint32_t, void**, size_t*);

static void* diting_dnscache_call_new(void* fn, const void* config, size_t config_len,
	uint8_t* flags, void** message, size_t* message_len) {
	return ((diting_dnscache_new_fn)fn)(config, config_len, flags, message, message_len);
}
static uint32_t diting_dnscache_call_update(void* fn, void* handle, const void* config,
	size_t config_len, uint8_t* flags, void** message, size_t* message_len) {
	return ((diting_dnscache_update_fn)fn)(handle, config, config_len, flags, message, message_len);
}
static void diting_dnscache_call_handle(void* fn, void* handle) {
	((diting_dnscache_handle_fn)fn)(handle);
}
static uint32_t diting_dnscache_call_get(void* fn, void* handle, const void* query,
	size_t query_len, uint8_t count, void** payload, size_t* payload_len) {
	return ((diting_dnscache_get_fn)fn)(handle, query, query_len, count, payload, payload_len);
}
static uint8_t diting_dnscache_call_put(void* fn, void* handle, const void* query,
	size_t query_len, const void* response, size_t response_len) {
	return ((diting_dnscache_put_fn)fn)(handle, query, query_len, response, response_len);
}
static uint8_t diting_dnscache_call_refresh(void* fn, void* handle, const void* query,
	size_t query_len) {
	return ((diting_dnscache_refresh_fn)fn)(handle, query, query_len);
}
static void diting_dnscache_call_refresh_done(void* fn, void* handle, const void* query,
	size_t query_len) {
	((diting_dnscache_refresh_done_fn)fn)(handle, query, query_len);
}
static void diting_dnscache_call_stats(void* fn, void* handle, void** payload, size_t* payload_len) {
	((diting_dnscache_payload_fn)fn)(handle, payload, payload_len);
}
static void diting_dnscache_call_snapshot(void* fn, void* handle, uint32_t limit, void** payload,
	size_t* payload_len) {
	((diting_dnscache_snapshot_fn)fn)(handle, limit, payload, payload_len);
}
*/
import "C"

import (
	"encoding/binary"
	"errors"
	"fmt"
	"unsafe"
)

// nativeDNSCacheHandle owns one Rust cache handle.
type nativeDNSCacheHandle struct {
	lib     *dnsCacheNativeLib
	pointer unsafe.Pointer
}

func newNativeDNSCache(cfg dnsCacheConfig) (*nativeDNSCacheHandle, uint32, error) {
	lib, err := dnsCacheKernel()
	if err != nil {
		return nil, 0, err
	}
	payload := encodeDNSCacheConfig(cfg)
	var flags C.uint8_t
	var message unsafe.Pointer
	var messageLen C.size_t
	pointer := C.diting_dnscache_call_new(
		lib.newCache,
		unsafe.Pointer(&payload[0]),
		C.size_t(len(payload)),
		&flags,
		&message,
		&messageLen,
	)
	refusal := copyDNSCachePayload(lib, message, messageLen)
	if pointer == nil {
		if len(refusal) > 0 {
			return nil, 0, errors.New(string(refusal))
		}
		return nil, 0, errors.New("dns cache kernel refused the configuration")
	}
	return &nativeDNSCacheHandle{lib: lib, pointer: pointer}, uint32(flags), nil
}

func (h *nativeDNSCacheHandle) updatePolicy(cfg dnsCacheConfig) (uint32, error) {
	if h == nil || h.pointer == nil {
		return 0, errors.New("dns cache handle is not open")
	}
	payload := encodeDNSCacheConfig(cfg)
	var flags C.uint8_t
	var message unsafe.Pointer
	var messageLen C.size_t
	status := C.diting_dnscache_call_update(
		h.lib.updatePolicy,
		h.pointer,
		unsafe.Pointer(&payload[0]),
		C.size_t(len(payload)),
		&flags,
		&message,
		&messageLen,
	)
	refusal := copyDNSCachePayload(h.lib, message, messageLen)
	if status != 0 {
		if len(refusal) > 0 {
			return 0, errors.New(string(refusal))
		}
		return 0, fmt.Errorf("dns cache kernel rejected the policy (status %d)", status)
	}
	return uint32(flags), nil
}

func (h *nativeDNSCacheHandle) close() {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_dnscache_call_handle(h.lib.closeHandle, h.pointer)
}

func (h *nativeDNSCacheHandle) free() {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_dnscache_call_handle(h.lib.freeHandle, h.pointer)
	h.pointer = nil
}

func (h *nativeDNSCacheHandle) clear() {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_dnscache_call_handle(h.lib.clear, h.pointer)
}

// lookup returns the decoded hit, or nil for a miss.
func (h *nativeDNSCacheHandle) lookup(rawQuery []byte, count bool) (*dnsCacheHit, error) {
	if h == nil || h.pointer == nil {
		return nil, nil
	}
	countFlag := C.uint8_t(0)
	if count {
		countFlag = 1
	}
	var payload unsafe.Pointer
	var payloadLen C.size_t
	status := C.diting_dnscache_call_get(
		h.lib.get,
		h.pointer,
		unsafe.Pointer(unsafe.SliceData(rawQuery)),
		C.size_t(len(rawQuery)),
		countFlag,
		&payload,
		&payloadLen,
	)
	switch status {
	case dnsCacheGetMiss:
		return nil, nil
	case dnsCacheGetFresh, dnsCacheGetStale:
		data := copyDNSCachePayload(h.lib, payload, payloadLen)
		hit, err := decodeDNSCacheHit(data)
		if err != nil {
			return nil, err
		}
		hit.stale = status == dnsCacheGetStale
		return hit, nil
	default:
		return nil, fmt.Errorf("dns cache kernel returned status %d", status)
	}
}

func (h *nativeDNSCacheHandle) put(rawQuery, rawResponse []byte) bool {
	if h == nil || h.pointer == nil {
		return false
	}
	stored := C.diting_dnscache_call_put(
		h.lib.put,
		h.pointer,
		unsafe.Pointer(unsafe.SliceData(rawQuery)),
		C.size_t(len(rawQuery)),
		unsafe.Pointer(unsafe.SliceData(rawResponse)),
		C.size_t(len(rawResponse)),
	)
	return stored == 1
}

func (h *nativeDNSCacheHandle) refreshBegin(rawQuery []byte) bool {
	if h == nil || h.pointer == nil {
		return false
	}
	owned := C.diting_dnscache_call_refresh(
		h.lib.refreshBegin,
		h.pointer,
		unsafe.Pointer(unsafe.SliceData(rawQuery)),
		C.size_t(len(rawQuery)),
	)
	return owned == 1
}

func (h *nativeDNSCacheHandle) refreshDone(rawQuery []byte) {
	if h == nil || h.pointer == nil {
		return
	}
	C.diting_dnscache_call_refresh_done(
		h.lib.refreshDone,
		h.pointer,
		unsafe.Pointer(unsafe.SliceData(rawQuery)),
		C.size_t(len(rawQuery)),
	)
}

func (h *nativeDNSCacheHandle) stats() (dnsCacheStats, error) {
	if h == nil || h.pointer == nil {
		return dnsCacheStats{}, errors.New("dns cache handle is not open")
	}
	var payload unsafe.Pointer
	var payloadLen C.size_t
	C.diting_dnscache_call_stats(h.lib.stats, h.pointer, &payload, &payloadLen)
	data := copyDNSCachePayload(h.lib, payload, payloadLen)
	return decodeDNSCacheStats(data)
}

func (h *nativeDNSCacheHandle) snapshot(limit uint32) ([]dnsCacheEntrySnapshot, error) {
	if h == nil || h.pointer == nil {
		return nil, errors.New("dns cache handle is not open")
	}
	var payload unsafe.Pointer
	var payloadLen C.size_t
	C.diting_dnscache_call_snapshot(h.lib.snapshot, h.pointer, C.uint32_t(limit), &payload, &payloadLen)
	data := copyDNSCachePayload(h.lib, payload, payloadLen)
	return decodeDNSCacheSnapshot(data)
}

// copyDNSCachePayload copies a payload out of the library and frees it.
func copyDNSCachePayload(lib *dnsCacheNativeLib, pointer unsafe.Pointer, length C.size_t) []byte {
	if pointer == nil {
		return nil
	}
	defer freeDNSCachePayload(lib, pointer, uintptr(length))
	if length == 0 {
		return nil
	}
	return C.GoBytes(pointer, C.int(length))
}

// encodeDNSCacheConfig writes the config payload the kernel decodes.
func encodeDNSCacheConfig(cfg dnsCacheConfig) []byte {
	var flags byte
	if cfg.Enabled {
		flags |= dnsCacheFlagEnabled
	}
	if cfg.MinTTLEnabled {
		flags |= dnsCacheFlagMinTTL
	}
	if cfg.StaleFallbackEnabled {
		flags |= dnsCacheFlagStaleFallback
	}
	if cfg.NegativeTTLEnabled {
		flags |= dnsCacheFlagNegativeTTL
	}
	payload := make([]byte, 0, 2+5*8+4+len(cfg.Mode))
	payload = append(payload, dnsCachePayloadLayoutVersion, flags)
	for _, value := range []int64{
		cfg.MaxTTLSeconds,
		cfg.FixedTTLSeconds,
		cfg.MinTTLSeconds,
		cfg.StaleFallbackSeconds,
		cfg.NegativeTTLSeconds,
	} {
		payload = binary.LittleEndian.AppendUint64(payload, uint64(value))
	}
	payload = binary.LittleEndian.AppendUint32(payload, uint32(len(cfg.Mode)))
	payload = append(payload, cfg.Mode...)
	return payload
}

// decodeDNSCacheHit reads the hit payload the kernel encodes.
func decodeDNSCacheHit(payload []byte) (*dnsCacheHit, error) {
	reader := &dnsCachePayloadReader{data: payload, kind: "hit"}
	if err := reader.expectLayout(); err != nil {
		return nil, err
	}
	stale, err := reader.u8("stale")
	if err != nil {
		return nil, err
	}
	flags, err := reader.u8("flags")
	if err != nil {
		return nil, err
	}
	wireLen, err := reader.u32("wire_len")
	if err != nil {
		return nil, err
	}
	wire, err := reader.bytes("wire", int(wireLen))
	if err != nil {
		return nil, err
	}
	hit := &dnsCacheHit{
		stale:      stale != 0,
		isNegative: flags&1 != 0,
		wire:       wire,
	}
	targetCount, err := reader.u16("chain_target_count")
	if err != nil {
		return nil, err
	}
	if targetCount > 0 {
		hit.chainTargets = make([]chainTarget, 0, targetCount)
	}
	for index := 0; index < int(targetCount); index++ {
		code, err := reader.u8("chain_target_kind")
		if err != nil {
			return nil, err
		}
		var kind string
		switch code {
		case 0:
			kind = "cname"
		case 1:
			kind = "svcb"
		default:
			return nil, fmt.Errorf("dns cache hit payload has unknown chain kind %d", code)
		}
		domain, err := reader.text("chain_target_domain")
		if err != nil {
			return nil, err
		}
		hit.chainTargets = append(hit.chainTargets, chainTarget{domain: domain, kind: kind})
	}
	ipCount, err := reader.u16("ip_count")
	if err != nil {
		return nil, err
	}
	if ipCount > 0 {
		hit.ipList = make([]string, 0, ipCount)
	}
	for index := 0; index < int(ipCount); index++ {
		ip, err := reader.text("ip")
		if err != nil {
			return nil, err
		}
		hit.ipList = append(hit.ipList, ip)
	}
	if hit.resolvedIPs, err = reader.text("resolved_ips"); err != nil {
		return nil, err
	}
	return hit, reader.expectEnd()
}

// decodeDNSCacheStats reads the stats payload the kernel encodes.
func decodeDNSCacheStats(payload []byte) (dnsCacheStats, error) {
	reader := &dnsCachePayloadReader{data: payload, kind: "stats"}
	if err := reader.expectLayout(); err != nil {
		return dnsCacheStats{}, err
	}
	flags, err := reader.u8("flags")
	if err != nil {
		return dnsCacheStats{}, err
	}
	stats := dnsCacheStats{Enabled: flags&dnsCacheFlagEnabled != 0}
	values := make([]uint64, 5)
	for index := range values {
		if values[index], err = reader.u64("counter"); err != nil {
			return dnsCacheStats{}, err
		}
	}
	stats.TotalHits = values[0]
	stats.TotalMisses = values[1]
	stats.StaleHits = values[2]
	stats.NegativeHits = values[3]
	stats.EvictionCount = values[4]
	entryCount, err := reader.u32("entry_count")
	if err != nil {
		return dnsCacheStats{}, err
	}
	maxEntries, err := reader.u32("max_entries")
	if err != nil {
		return dnsCacheStats{}, err
	}
	stats.EntryCount = int(entryCount)
	stats.MaxEntries = int(maxEntries)
	if total := stats.TotalHits + stats.TotalMisses; total > 0 {
		stats.HitRatio = float64(stats.TotalHits) / float64(total)
	}
	return stats, reader.expectEnd()
}

// decodeDNSCacheSnapshot reads the snapshot payload the kernel encodes.
func decodeDNSCacheSnapshot(payload []byte) ([]dnsCacheEntrySnapshot, error) {
	reader := &dnsCachePayloadReader{data: payload, kind: "snapshot"}
	if err := reader.expectLayout(); err != nil {
		return nil, err
	}
	count, err := reader.u32("count")
	if err != nil {
		return nil, err
	}
	entries := make([]dnsCacheEntrySnapshot, 0, count)
	for index := 0; index < int(count); index++ {
		key, err := reader.lengthPrefixedBytes("key")
		if err != nil {
			return nil, err
		}
		name, err := reader.lengthPrefixedBytes("query_name")
		if err != nil {
			return nil, err
		}
		queryType, err := reader.u16("query_type")
		if err != nil {
			return nil, err
		}
		queryClass, err := reader.u16("query_class")
		if err != nil {
			return nil, err
		}
		createdAt, err := reader.i64("created_at")
		if err != nil {
			return nil, err
		}
		expiresAt, err := reader.i64("expires_at")
		if err != nil {
			return nil, err
		}
		lastHitAt, err := reader.i64("last_hit_at")
		if err != nil {
			return nil, err
		}
		hitCount, err := reader.u64("hit_count")
		if err != nil {
			return nil, err
		}
		originalTTL, err := reader.u32("original_ttl")
		if err != nil {
			return nil, err
		}
		responseSize, err := reader.u32("response_size")
		if err != nil {
			return nil, err
		}
		entries = append(entries, dnsCacheEntrySnapshot{
			Key:          string(key),
			QueryName:    string(name),
			QueryType:    int(queryType),
			QueryClass:   int(queryClass),
			CreatedAt:    createdAt,
			ExpiresAt:    expiresAt,
			LastHitAt:    lastHitAt,
			HitCount:     hitCount,
			OriginalTTL:  int64(originalTTL),
			ResponseSize: int(responseSize),
		})
	}
	return entries, reader.expectEnd()
}

type dnsCachePayloadReader struct {
	data     []byte
	position int
	kind     string
}

func (r *dnsCachePayloadReader) remaining() int {
	return len(r.data) - r.position
}

func (r *dnsCachePayloadReader) truncated(field string) error {
	return fmt.Errorf("dns cache %s payload is truncated (%s)", r.kind, field)
}

func (r *dnsCachePayloadReader) expectLayout() error {
	if r.remaining() < 1 {
		return r.truncated("layout")
	}
	if r.data[0] != dnsCachePayloadLayoutVersion {
		return fmt.Errorf("dns cache %s payload layout %d, expected %d",
			r.kind, r.data[0], dnsCachePayloadLayoutVersion)
	}
	r.position = 1
	return nil
}

func (r *dnsCachePayloadReader) u8(field string) (byte, error) {
	if r.remaining() < 1 {
		return 0, r.truncated(field)
	}
	value := r.data[r.position]
	r.position++
	return value, nil
}

func (r *dnsCachePayloadReader) u16(field string) (uint16, error) {
	if r.remaining() < 2 {
		return 0, r.truncated(field)
	}
	value := binary.LittleEndian.Uint16(r.data[r.position:])
	r.position += 2
	return value, nil
}

func (r *dnsCachePayloadReader) u32(field string) (uint32, error) {
	if r.remaining() < 4 {
		return 0, r.truncated(field)
	}
	value := binary.LittleEndian.Uint32(r.data[r.position:])
	r.position += 4
	return value, nil
}

func (r *dnsCachePayloadReader) u64(field string) (uint64, error) {
	if r.remaining() < 8 {
		return 0, r.truncated(field)
	}
	value := binary.LittleEndian.Uint64(r.data[r.position:])
	r.position += 8
	return value, nil
}

func (r *dnsCachePayloadReader) i64(field string) (int64, error) {
	value, err := r.u64(field)
	return int64(value), err
}

func (r *dnsCachePayloadReader) bytes(field string, length int) ([]byte, error) {
	if length < 0 || r.remaining() < length {
		return nil, r.truncated(field)
	}
	value := r.data[r.position : r.position+length]
	r.position += length
	return value, nil
}

func (r *dnsCachePayloadReader) lengthPrefixedBytes(field string) ([]byte, error) {
	length, err := r.u32(field)
	if err != nil {
		return nil, err
	}
	if uint64(length) > uint64(r.remaining()) {
		return nil, r.truncated(field)
	}
	return r.bytes(field, int(length))
}

func (r *dnsCachePayloadReader) text(field string) (string, error) {
	value, err := r.lengthPrefixedBytes(field)
	if err != nil {
		return "", err
	}
	return string(value), nil
}

func (r *dnsCachePayloadReader) expectEnd() error {
	if r.remaining() != 0 {
		return fmt.Errorf("dns cache %s payload has %d trailing bytes", r.kind, r.remaining())
	}
	return nil
}
