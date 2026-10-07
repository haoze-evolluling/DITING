package core

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"os"
	"sort"
	"strings"
	"sync"
)

const (
	trieMagic      = 0x54524945 // "TRIE"
	trieVersion    = 2
	trieHeaderSize = 16
)

// DomainTrie 基于倒序域标签的反向字典树 (Reversed-Label Trie)
type DomainTrie struct {
	mu   sync.RWMutex
	root *trieNode
	size int
}

type trieNode struct {
	children   map[string]*trieNode
	isTerminal bool
	exactOnly  bool
	rule       *ParsedRule
}

func newTrieNode() *trieNode {
	return &trieNode{
		children: make(map[string]*trieNode),
	}
}

// NewDomainTrie 创建空的字典树
func NewDomainTrie() *DomainTrie {
	return &DomainTrie{
		root: newTrieNode(),
	}
}

// Insert 向树中插入一条规则
func (t *DomainTrie) Insert(rule *ParsedRule) {
	if rule == nil || rule.Pattern == "" {
		return
	}

	t.mu.Lock()
	defer t.mu.Unlock()

	labels := strings.Split(strings.TrimSuffix(strings.ToLower(rule.Pattern), "."), ".")
	curr := t.root

	// 倒序插入各域标签 (如 ads.google.com -> com -> google -> ads)
	for i := len(labels) - 1; i >= 0; i-- {
		label := labels[i]
		child, exists := curr.children[label]
		if !exists {
			child = newTrieNode()
			curr.children[label] = child
		}
		curr = child
	}

	curr.isTerminal = true
	curr.exactOnly = rule.IsExact
	curr.rule = rule
	t.size++
}

// Match 匹配域名，支持全域及父域通配继承 (例如 ||google.com^ 匹配 mail.google.com)
func (t *DomainTrie) Match(domain string) (bool, *ParsedRule) {
	t.mu.RLock()
	defer t.mu.RUnlock()

	domain = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	if domain == "" || t.root == nil {
		return false, nil
	}

	labels := strings.Split(domain, ".")
	return matchNode(t.root, labels, len(labels)-1)
}

func matchNode(curr *trieNode, labels []string, index int) (bool, *ParsedRule) {
	if curr == nil {
		return false, nil
	}

	// 若当前节点已是终结节点且非 ExactOnly，则其所有子域名均自动命中 (例如 ||ad.com^ 命中 a.b.ad.com)
	if curr.isTerminal && !curr.exactOnly {
		return true, curr.rule
	}

	// 已耗尽全部标签
	if index < 0 {
		if curr.isTerminal {
			return true, curr.rule
		}
		return false, nil
	}

	targetLabel := labels[index]

	// 1. 精确标签匹配
	if child, ok := curr.children[targetLabel]; ok {
		matched, rule := matchNode(child, labels, index-1)
		if matched {
			return true, rule
		}
	}

	// 2. 通配标签 (*) 匹配
	if wildcardChild, ok := curr.children["*"]; ok {
		matched, rule := matchNode(wildcardChild, labels, index-1)
		if matched {
			return true, rule
		}
	}

	return false, nil
}

// Size 返回树中存储的终结规则条数
func (t *DomainTrie) Size() int {
	t.mu.RLock()
	defer t.mu.RUnlock()
	return t.size
}

// SaveToFile 将 Trie 树以二进制紧凑格式序列化持久化至文件
func (t *DomainTrie) SaveToFile(path string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()

	type bfsEntry struct {
		node   *trieNode
		offset int
	}

	nodeCount := 0
	domainCount := 0
	var countNodes func(n *trieNode)
	countNodes = func(n *trieNode) {
		nodeCount++
		if n.isTerminal {
			domainCount++
		}
		for _, child := range n.children {
			countNodes(child)
		}
	}
	countNodes(t.root)

	// 第一遍 BFS: 计算各节点绝对文件内偏移
	queue := []bfsEntry{{node: t.root, offset: trieHeaderSize}}
	currentOffset := trieHeaderSize
	offsets := make(map[*trieNode]int)

	for len(queue) > 0 {
		entry := queue[0]
		queue = queue[1:]

		offsets[entry.node] = currentOffset

		nodeSize := 1 + 4
		sortedLabels := sortedChildKeys(entry.node.children)
		for _, label := range sortedLabels {
			nodeSize += 2 + len(label) + 4
		}
		currentOffset += nodeSize

		for _, label := range sortedLabels {
			queue = append(queue, bfsEntry{node: entry.node.children[label]})
		}
	}

	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("创建 trie 文件失败: %w", err)
	}
	defer f.Close()

	w := bufio.NewWriter(f)

	header := make([]byte, trieHeaderSize)
	binary.BigEndian.PutUint32(header[0:4], trieMagic)
	binary.BigEndian.PutUint32(header[4:8], trieVersion)
	binary.BigEndian.PutUint32(header[8:12], uint32(nodeCount))
	binary.BigEndian.PutUint32(header[12:16], uint32(domainCount))
	if _, err := w.Write(header); err != nil {
		return err
	}

	// 第二遍 BFS: 逐节点写入二进制
	queue2 := []*trieNode{t.root}
	for len(queue2) > 0 {
		node := queue2[0]
		queue2 = queue2[1:]

		if node.isTerminal {
			w.WriteByte(1)
		} else {
			w.WriteByte(0)
		}

		sortedLabels := sortedChildKeys(node.children)
		countBuf := make([]byte, 4)
		binary.BigEndian.PutUint32(countBuf, uint32(len(sortedLabels)))
		w.Write(countBuf)

		for _, label := range sortedLabels {
			child := node.children[label]

			lenBuf := make([]byte, 2)
			binary.BigEndian.PutUint16(lenBuf, uint16(len(label)))
			w.Write(lenBuf)
			w.WriteString(label)

			offBuf := make([]byte, 4)
			binary.BigEndian.PutUint32(offBuf, uint32(offsets[child]))
			w.Write(offBuf)
		}

		for _, label := range sortedLabels {
			queue2 = append(queue2, node.children[label])
		}
	}

	return w.Flush()
}

func sortedChildKeys(m map[string]*trieNode) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
