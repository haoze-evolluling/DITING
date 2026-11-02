// policy_wildcard_index.go indexes wildcard domain rules so a lookup no longer runs every
// wildcard regex against every suffix of the queried domain.
//
// Index layout (ASCII patterns only; anything else stays on the linear path):
//   - "*"            -> matches everything, remembered by its list position.
//   - "*.base"       -> equivalent to "domain == base or ends with .base", stored in a hash
//     map keyed by base and probed once per label suffix of the domain.
//   - other globs    -> bucketed by the complete labels after the last "*" (for
//     "ads*.example.org" the key is "example.org"); only buckets whose key is a label
//     suffix of the domain are tried, and the original regex confirms the match.
//   - remaining globs (no complete trailing label) are scanned linearly behind a cheap
//     HasSuffix prefilter on the literal tail.
//
// Every entry keeps its original list position, and match returns the lowest position
// that matches, so the reported pattern is identical to the old first-match linear scan.
// Domains containing non-ASCII bytes fall back to that linear scan, because (?i) regex
// case folding differs from strings.ToLower outside ASCII.

package tunnel

import "strings"

type wildcardGlob struct {
	order int
	tail  string
	m     *wildcardMatcher
}

type wildcardSuffix struct {
	order   int
	pattern string
}

type wildcardIndex struct {
	ordered  []*wildcardMatcher
	allOrder int
	allPat   string
	suffix   map[string]wildcardSuffix
	globs    map[string][]wildcardGlob
	residual []wildcardGlob
}

const noWildcardMatch = int(^uint(0) >> 1)

func newWildcardIndex(ordered []*wildcardMatcher) *wildcardIndex {
	if len(ordered) == 0 {
		return nil
	}
	idx := &wildcardIndex{ordered: ordered, allOrder: noWildcardMatch}
	for order, wc := range ordered {
		idx.add(order, wc)
	}
	return idx
}

func (idx *wildcardIndex) add(order int, wc *wildcardMatcher) {
	p := wc.pattern
	if wc.isAll {
		if order < idx.allOrder {
			idx.allOrder, idx.allPat = order, p
		}
		return
	}
	if !isASCII(p) {
		idx.residual = append(idx.residual, wildcardGlob{order: order, m: wc})
		return
	}
	if strings.HasPrefix(p, "*.") && !strings.Contains(p[2:], "*") && !strings.HasSuffix(p, ".") {
		if base := wc.baseDomain; base != "" {
			if idx.suffix == nil {
				idx.suffix = make(map[string]wildcardSuffix)
			}
			if _, exists := idx.suffix[base]; !exists {
				idx.suffix[base] = wildcardSuffix{order: order, pattern: p}
			}
			return
		}
	}
	tail := p[strings.LastIndexByte(p, '*')+1:]
	if strings.HasSuffix(tail, ".") {
		// baseDomain trims a trailing dot, so the tail is not a safe prefilter.
		idx.residual = append(idx.residual, wildcardGlob{order: order, m: wc})
		return
	}
	if dot := strings.IndexByte(tail, '.'); dot >= 0 && dot < len(tail)-1 {
		key := tail[dot+1:]
		if idx.globs == nil {
			idx.globs = make(map[string][]wildcardGlob)
		}
		idx.globs[key] = append(idx.globs[key], wildcardGlob{order: order, tail: tail, m: wc})
		return
	}
	idx.residual = append(idx.residual, wildcardGlob{order: order, tail: tail, m: wc})
}

// match returns the first pattern (in original list order) matching domain.
// domain must already be lower-cased and trimmed by the caller.
func (idx *wildcardIndex) match(domain string) (string, bool) {
	if idx == nil {
		return "", false
	}
	if !isASCII(domain) {
		for _, wc := range idx.ordered {
			if wc.matches(domain) {
				return wc.pattern, true
			}
		}
		return "", false
	}
	best, bestPat := idx.allOrder, idx.allPat
	d := domain
	for {
		if len(idx.suffix) > 0 {
			if e, ok := idx.suffix[d]; ok && e.order < best {
				best, bestPat = e.order, e.pattern
			}
		}
		if len(idx.globs) > 0 {
			for _, g := range idx.globs[d] {
				if g.order >= best {
					break
				}
				if strings.HasSuffix(domain, g.tail) && g.m.matches(domain) {
					best, bestPat = g.order, g.m.pattern
					break
				}
			}
		}
		dot := strings.IndexByte(d, '.')
		if dot < 0 || dot >= len(d)-1 {
			break
		}
		d = d[dot+1:]
	}
	for _, g := range idx.residual {
		if g.order >= best {
			break
		}
		if strings.HasSuffix(domain, g.tail) && g.m.matches(domain) {
			best, bestPat = g.order, g.m.pattern
			break
		}
	}
	if best == noWildcardMatch {
		return "", false
	}
	return bestPat, true
}

func isASCII(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] >= 0x80 {
			return false
		}
	}
	return true
}
