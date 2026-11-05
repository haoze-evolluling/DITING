package tunnel

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The DTRI fixtures under rust/diting-rule-core/tests/fixtures are produced by the Rust writer
// (and checked byte for byte against the Kotlin/JVM reference in the Rust test suite). This test
// closes the loop from the consumer side: the Go engine, which is what actually mmaps these files,
// must resolve every indexable rule in the shared corpus to the source the corpus says.
//
// It also runs without a device or the Rust toolchain, and fails loudly if the fixtures are ever
// regenerated with a different format.

func TestRustDTRIWriterParsesWithGoReader(t *testing.T) {
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
		reader, err := openDTRI(path)
		if err != nil {
			t.Fatalf("%s: openDTRI: %v", name, err)
		}
		defer reader.close()
		index := rustDTRIExpectedSources(t, corpus)
		if len(index) < 2 {
			t.Fatalf("%s: corpus has no indexable rules", name)
		}
		for pattern := range index {
			for _, query := range []string{pattern, strings.ToUpper(pattern), "sub." + pattern} {
				// The reader returns the first terminal node it meets walking labels from the
				// TLD down, so a shorter indexed suffix shadows the queried pattern.
				source, want := rustDTRILookup(index, query)
				ok, got := reader.containsOrParent(query)
				if !want || !ok || got != source {
					t.Errorf("%s: lookup %q = (%q, %v), want (%q, %v)", name, query, got, ok, source, want)
				}
			}
		}
		if ok, got := reader.containsOrParent("not-in-this-fixture.example"); ok {
			t.Errorf("%s: unexpected match %q for a domain outside the fixture", name, got)
		}
	}
}

// rustDTRIExpectedSources replays the writer's filter on the shared corpus: the smallest source
// per lowercased, trailing-dot-trimmed pattern, skipping the families a trie cannot hold.
func rustDTRIExpectedSources(t *testing.T, corpus []byte) map[string]string {
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

// rustDTRILookup mirrors the reader: walk the labels from the TLD down and stop at the first
// indexed suffix. A missing edge before any terminal is a miss, which for a suffix set means
// "no indexed suffix of this domain".
func rustDTRILookup(index map[string]string, domain string) (string, bool) {
	labels := strings.Split(strings.ToLower(strings.TrimRight(domain, ".")), ".")
	for start := len(labels) - 1; start >= 0; start-- {
		suffix := strings.Join(labels[start:], ".")
		if source, ok := index[suffix]; ok {
			return source, true
		}
	}
	return "", false
}
