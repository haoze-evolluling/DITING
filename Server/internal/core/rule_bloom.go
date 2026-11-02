package core

import (
	"math"
	"strings"
	"sync"
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
