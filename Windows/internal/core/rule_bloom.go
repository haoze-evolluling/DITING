package core

import (
	"encoding/binary"
	"fmt"
	"math"
	"os"
	"strings"
	"sync"
)

const (
	bloomMagic      = 0x424C4F4D // "BLOM"
	bloomVersion    = 1
	bloomHeaderSize = 24
)

// DomainBloomFilter 高性能布隆过滤器，在遍历 Trie 树前以纳秒级过滤 ~90%+ 的干净域名
type DomainBloomFilter struct {
	mu        sync.RWMutex
	bits      []byte
	bitCount  uint64
	hashCount uint32
}

// OptimalBloomParams 计算最佳位数组大小与哈希函数数量
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
	return bitCount, hashCount
}

// NewDomainBloomFilter 创建指定预期元素量与误报率的布隆过滤器
func NewDomainBloomFilter(expectedItems int, fpRate float64) *DomainBloomFilter {
	bitCount, hashCount := OptimalBloomParams(expectedItems, fpRate)
	return &DomainBloomFilter{
		bits:      make([]byte, bitCount/8),
		bitCount:  bitCount,
		hashCount: hashCount,
	}
}

// Add 插入域名
func (bf *DomainBloomFilter) Add(domain string) {
	bf.mu.Lock()
	defer bf.mu.Unlock()

	domain = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	if domain == "" || bf.bitCount == 0 {
		return
	}

	h1, h2 := bloomDoubleHash(domain)
	for i := uint32(0); i < bf.hashCount; i++ {
		idx := (h1 + uint64(i)*h2) % bf.bitCount
		bf.bits[idx/8] |= 1 << (idx % 8)
	}
}

// MightContain 探测指定域名是否存在 (可能存在或绝对不存在)
func (bf *DomainBloomFilter) MightContain(domain string) bool {
	bf.mu.RLock()
	defer bf.mu.RUnlock()

	domain = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	return bf.mightContainUnlocked(domain)
}

func (bf *DomainBloomFilter) mightContainUnlocked(domain string) bool {
	if bf.bitCount == 0 || len(bf.bits) == 0 {
		return true // fail-open
	}

	if domain == "" {
		return false
	}

	h1, h2 := bloomDoubleHash(domain)
	for i := uint32(0); i < bf.hashCount; i++ {
		idx := (h1 + uint64(i)*h2) % bf.bitCount
		byteIdx := idx / 8
		if byteIdx >= uint64(len(bf.bits)) {
			return true
		}
		if bf.bits[byteIdx]&(1<<(idx%8)) == 0 {
			return false
		}
	}
	return true
}

// MightContainDomainOrParent 层级探测域名及其所有父域 (如 sub.ad.google.com -> ad.google.com -> google.com)
func (bf *DomainBloomFilter) MightContainDomainOrParent(domain string) bool {
	bf.mu.RLock()
	defer bf.mu.RUnlock()

	d := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	if d == "" {
		return false
	}

	for {
		if bf.mightContainUnlocked(d) {
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

// SaveToFile 保存至二进制文件 (.bloom)
func (bf *DomainBloomFilter) SaveToFile(path string) error {
	bf.mu.RLock()
	defer bf.mu.RUnlock()

	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("创建 bloom 文件失败: %w", err)
	}
	defer f.Close()

	header := make([]byte, bloomHeaderSize)
	binary.BigEndian.PutUint32(header[0:4], bloomMagic)
	binary.BigEndian.PutUint32(header[4:8], bloomVersion)
	binary.BigEndian.PutUint64(header[8:16], bf.bitCount)
	binary.BigEndian.PutUint32(header[16:20], bf.hashCount)

	if _, err := f.Write(header); err != nil {
		return fmt.Errorf("写入 bloom 文件头失败: %w", err)
	}
	if _, err := f.Write(bf.bits); err != nil {
		return fmt.Errorf("写入 bloom 位数组失败: %w", err)
	}
	return nil
}

// LoadBloomFilter 从二进制文件加载布隆过滤器
func LoadBloomFilter(path string) (*DomainBloomFilter, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("读取 bloom 文件失败: %w", err)
	}

	if len(data) < bloomHeaderSize {
		return nil, fmt.Errorf("bloom 文件大小不足")
	}

	magic := binary.BigEndian.Uint32(data[0:4])
	if magic != bloomMagic {
		return nil, fmt.Errorf("无效的 bloom magic: 0x%X", magic)
	}

	version := binary.BigEndian.Uint32(data[4:8])
	if version != bloomVersion {
		return nil, fmt.Errorf("不支持的 bloom 版本: %d", version)
	}

	bitCount := binary.BigEndian.Uint64(data[8:16])
	hashCount := binary.BigEndian.Uint32(data[16:20])

	expectedBytes := bitCount / 8
	if uint64(len(data)-bloomHeaderSize) < expectedBytes {
		return nil, fmt.Errorf("bloom 文件已损坏或被截断")
	}

	bits := make([]byte, expectedBytes)
	copy(bits, data[bloomHeaderSize:bloomHeaderSize+int(expectedBytes)])

	return &DomainBloomFilter{
		bits:      bits,
		bitCount:  bitCount,
		hashCount: hashCount,
	}, nil
}

const (
	fnvOffset64 = 14695981039346656037
	fnvPrime64  = 1099511628211
)

func bloomDoubleHash(s string) (uint64, uint64) {
	// FNV-1a (Zero allocations)
	h1 := uint64(fnvOffset64)
	for i := 0; i < len(s); i++ {
		h1 ^= uint64(s[i])
		h1 *= fnvPrime64
	}

	// FNV-1 (Zero allocations)
	h2 := uint64(fnvOffset64)
	for i := 0; i < len(s); i++ {
		h2 *= fnvPrime64
		h2 ^= uint64(s[i])
	}

	if h2%2 == 0 {
		h2++ // 强制奇数防止循环退化
	}

	return h1, h2
}
