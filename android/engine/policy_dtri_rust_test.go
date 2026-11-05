//go:build cgo

package tunnel

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/miekg/dns"
)

// The DTRI fixtures under rust/diting-rule-core/tests/fixtures are produced by the Rust writer (and
// byte-compared with the Kotlin/JVM reference in the Rust suite). This test closes the loop from
// the consumer side: the policy kernel the engine calls must resolve every indexable rule of the
// corpus to the source the corpus says, through the same file the engine hands it.
//
// It needs the kernel, like the rest of the policy tests: `cargo build --release` in `rust/`.

func TestNativePolicyResolvesDTRI(t *testing.T) {
	requireNativeKernel(t)
	root := filepath.Join("..", "..", "rust", "diting-rule-core", "tests", "fixtures")
	for _, name := range []string{"basic", "sources"} {
		corpus, err := os.ReadFile(filepath.Join(root, name+".rules.txt"))
		if err != nil {
			t.Fatalf("%s corpus: %v", name, err)
		}
		image, err := os.ReadFile(filepath.Join(root, name+".dtri"))
		if err != nil {
			t.Fatalf("%s image: %v", name, err)
		}
		path := filepath.Join(t.TempDir(), name+".dtri")
		if err := os.WriteFile(path, image, 0o600); err != nil {
			t.Fatalf("%s: write image: %v", name, err)
		}
		payload, err := json.Marshal(map[string]any{"blockTriePath": path})
		if err != nil {
			t.Fatal(err)
		}

		pe := newPolicyEngine()
		t.Cleanup(pe.close)
		if err := pe.applySnapshot(string(payload)); err != nil {
			t.Fatalf("%s: applySnapshot: %v", name, err)
		}

		index := dtriExpectedSources(t, corpus)
		if len(index) < 2 {
			t.Fatalf("%s: corpus has no indexable rules", name)
		}
		for pattern := range index {
			source, want := dtriLookup(index, pattern)
			if !want {
				continue
			}
			blocked, reason := pe.evaluate(pattern, "", dns.TypeA)
			if !blocked || reason != source {
				t.Errorf("%s: lookup %q = (%q, %v), want (%q, true)", name, pattern, reason, blocked, source)
			}
		}
		if blocked, reason := pe.evaluate("not-in-this-fixture.example", "", dns.TypeA); blocked {
			t.Errorf("%s: unexpected match %q for a domain outside the fixture", name, reason)
		}
	}
}

// dtriExpectedSources replays the writer's filter on the shared corpus: the smallest source per
// lowercased, trailing-dot-trimmed pattern, skipping the families a trie cannot hold.
func dtriExpectedSources(t *testing.T, corpus []byte) map[string]string {
	t.Helper()
	expected := map[string]string{}
	for _, line := range strings.Split(string(corpus), "\n") {
		if line == "" {
			continue
		}
		fields := strings.Split(line, "\t")
		field := func(index int, fallback string) string {
			if index < len(fields) {
				return fields[index]
			}
			return fallback
		}
		flag := func(index int) bool { return field(index, "0") == "1" }
		// "~" is null and "=" is the empty string: only a non-empty value skips the rule.
		optionalSet := func(index int) bool {
			value := field(index, "~")
			return value != "~" && value != "=" && value != ""
		}
		pattern := field(0, "")
		source := field(1, "")
		if flag(5) || strings.Contains(pattern, "*") || optionalSet(3) || flag(4) ||
			flag(7) || optionalSet(6) || optionalSet(8) {
			continue
		}
		pattern = strings.ToLower(strings.TrimRight(pattern, "."))
		if previous, ok := expected[pattern]; !ok || source < previous {
			expected[pattern] = source
		}
	}
	return expected
}

// dtriLookup walks the labels from the TLD down and stops at the first indexed suffix, which is
// what the trie does: a shorter indexed suffix shadows the queried pattern.
func dtriLookup(index map[string]string, domain string) (string, bool) {
	labels := strings.Split(strings.ToLower(strings.TrimRight(domain, ".")), ".")
	for start := len(labels) - 1; start >= 0; start-- {
		suffix := strings.Join(labels[start:], ".")
		if source, ok := index[suffix]; ok {
			return source, true
		}
	}
	return "", false
}
