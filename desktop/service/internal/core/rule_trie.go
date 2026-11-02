package core

import (
	"strings"
	"sync"
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
