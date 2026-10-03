// domain_bloom_filter.go implements a memory-mapped, read-only probabilistic Bloom filter
// designed to eliminate trie traversal for ~90%+ of clean DNS queries.
//
// File Format (24-byte Header):
// - magic (4 bytes): 0x424C4F4D ("BLOM")
// - version (4 bytes): 1
// - bitCount (8 bytes, uint64)
// - hashCount (4 bytes, uint32)
// - padding (4 bytes): zeros
// - bits: bitCount / 8 bytes
//
// Mathematical Optimization & Double Hashing:
// - Optimal bit count: m = -(n * ln(p)) / (ln(2))^2
// - Optimal hash count: k = (m / n) * ln(2)
// - Double hashing formula: h(i) = h1 + i * h2, where h1 is 64-bit FNV-1a and h2 is 64-bit FNV-1.
//   h2 is forced to be odd to prevent cycle degradation in modular arithmetic.
//   This hashing implementation must remain strictly identical between Go and Kotlin.
//
// Query Behavior:
// - Parent domain matching checks hierarchically (e.g., sub.ads.google.com -> ads.google.com -> google.com -> com).
// - Operates fail-open: any unmapped buffer or indexing error falls through to the trie.

package tunnel

import (
	"encoding/binary"
	"fmt"
	"golang.org/x/sys/unix"
	"hash/fnv"
	"math"
	"os"
	"strings"
)

const (
	bloomMagic   = 0x424C4F4D
	bloomVersion = 1

	bloomHeaderSize = 24
)

type BloomFilter struct {
	file      *os.File
	buffer    []byte
	bitCount  uint64
	hashCount uint32
}

type BloomBuilder struct {
	bits      []byte
	bitCount  uint64
	hashCount uint32
}

func OptimalBloomParams(expectedItems int, fpRate float64) (bitCount uint64, hashCount uint32) {
	if expectedItems <= 0 {
		expectedItems = 1
	}
	if fpRate <= 0 || fpRate >= 1 {
		fpRate = 0.001
	}
	n := float64(expectedItems)
	m := -n * math.Log(fpRate) / (math.Ln2 * math.Ln2)
	k := (m / n) * math.Ln2

	bitCount = uint64(math.Ceil(m))
	hashCount = uint32(math.Max(math.Ceil(k), 1))

	if bitCount%8 != 0 {
		bitCount = (bitCount/8 + 1) * 8
	}
	return
}

func NewBloomBuilder(expectedItems int, fpRate float64) *BloomBuilder {
	bitCount, hashCount := OptimalBloomParams(expectedItems, fpRate)
	byteCount := bitCount / 8
	return &BloomBuilder{
		bits:      make([]byte, byteCount),
		bitCount:  bitCount,
		hashCount: hashCount,
	}
}

func (b *BloomBuilder) Add(domain string) {
	for i := uint32(0); i < b.hashCount; i++ {
		idx := b.hash(domain, i) % b.bitCount
		b.bits[idx/8] |= 1 << (idx % 8)
	}
}

func (b *BloomBuilder) MightContain(domain string) bool {
	for i := uint32(0); i < b.hashCount; i++ {
		idx := b.hash(domain, i) % b.bitCount
		if b.bits[idx/8]&(1<<(idx%8)) == 0 {
			return false
		}
	}
	return true
}

func (b *BloomBuilder) SaveToFile(path string) error {
	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("failed to create bloom file: %w", err)
	}
	defer f.Close()

	header := make([]byte, bloomHeaderSize)
	binary.BigEndian.PutUint32(header[0:4], bloomMagic)
	binary.BigEndian.PutUint32(header[4:8], bloomVersion)
	binary.BigEndian.PutUint64(header[8:16], b.bitCount)
	binary.BigEndian.PutUint32(header[16:20], b.hashCount)

	if _, err := f.Write(header); err != nil {
		return fmt.Errorf("failed to write bloom header: %w", err)
	}
	if _, err := f.Write(b.bits); err != nil {
		return fmt.Errorf("failed to write bloom bits: %w", err)
	}
	return nil
}

func (b *BloomBuilder) hash(domain string, i uint32) uint64 {
	h1, h2 := bloomDoubleHash(domain)
	return h1 + uint64(i)*h2
}

func LoadBloomFilter(path string) (*BloomFilter, error) {
	if path == "" {
		return nil, fmt.Errorf("empty path")
	}

	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("failed to open bloom file: %w", err)
	}

	stat, err := f.Stat()
	if err != nil {
		f.Close()
		return nil, fmt.Errorf("failed to stat bloom file: %w", err)
	}

	size := stat.Size()
	if size < bloomHeaderSize {
		f.Close()
		return nil, fmt.Errorf("file too small to be a valid bloom filter")
	}

	data, err := unix.Mmap(int(f.Fd()), 0, int(size), unix.PROT_READ, unix.MAP_SHARED)
	if err != nil {
		f.Close()
		return nil, fmt.Errorf("mmap failed: %w", err)
	}

	magic := binary.BigEndian.Uint32(data[0:4])
	if magic != bloomMagic {
		unix.Munmap(data)
		f.Close()
		return nil, fmt.Errorf("invalid bloom magic: expected %X, got %X", bloomMagic, magic)
	}

	version := binary.BigEndian.Uint32(data[4:8])
	if version != bloomVersion {
		unix.Munmap(data)
		f.Close()
		return nil, fmt.Errorf("invalid bloom version: expected %d, got %d", bloomVersion, version)
	}

	bitCount := binary.BigEndian.Uint64(data[8:16])
	hashCount := binary.BigEndian.Uint32(data[16:20])

	expectedSize := int64(bloomHeaderSize) + int64(bitCount/8)
	if size < expectedSize {
		unix.Munmap(data)
		f.Close()
		return nil, fmt.Errorf("bloom file truncated: expected %d bytes, got %d", expectedSize, size)
	}

	return &BloomFilter{
		file:      f,
		buffer:    data,
		bitCount:  bitCount,
		hashCount: hashCount,
	}, nil
}

func (bf *BloomFilter) Close() {
	if bf.buffer != nil {
		unix.Munmap(bf.buffer)
		bf.buffer = nil
	}
	if bf.file != nil {
		bf.file.Close()
		bf.file = nil
	}
}

func (bf *BloomFilter) MightContain(domain string) bool {
	if bf.buffer == nil {
		return true
	}
	h1, h2 := bloomDoubleHash(domain)
	for i := uint32(0); i < bf.hashCount; i++ {
		idx := (h1 + uint64(i)*h2) % bf.bitCount
		byteIdx := bloomHeaderSize + int(idx/8)
		if byteIdx >= len(bf.buffer) {
			return true
		}
		if bf.buffer[byteIdx]&(1<<(idx%8)) == 0 {
			return false
		}
	}
	return true
}

func (bf *BloomFilter) MightContainDomainOrParent(domain string) bool {
	if bf.buffer == nil {
		return true
	}
	d := domain
	for {
		if bf.MightContain(d) {
			return true
		}
		idx := strings.IndexByte(d, '.')
		if idx < 0 {
			break
		}
		d = d[idx+1:]
	}
	return false
}

func bloomDoubleHash(s string) (uint64, uint64) {
	h1 := fnv.New64a()
	h1.Write([]byte(s))
	v1 := h1.Sum64()

	h2 := fnv.New64()
	h2.Write([]byte(s))
	v2 := h2.Sum64()

	if v2%2 == 0 {
		v2++
	}

	return v1, v2
}
