//go:build cgo

// policy_native_test.go is the parity harness for the Rust policy kernel.
//
// The runtime cross-check (policy_native_parity.go) only proves agreement on the probes of one
// snapshot, so this test does the exhaustive version: random snapshots mixing every rule family,
// then every generated query is answered by both engines and the verdict *and* the reason have to
// match. It is skipped when the library is not built, like the Dart fast-path parity tests, so a
// checkout without a Rust toolchain still runs the rest of the suite.

package tunnel

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/miekg/dns"
)

func requireNativeKernel(t *testing.T) {
	t.Helper()
	if nativeKernel() == nil {
		t.Skip("Rust policy kernel not built (cd rust && cargo build --release)")
	}
}

// buildNativeForTest builds the native snapshot for a payload and asserts both engines agree on the
// snapshot shape. It fails (instead of skipping) when the payload cannot be built natively: a
// randomized payload the Rust side rejects is exactly the regression this test exists to catch.
func buildNativeForTest(t *testing.T, jsonSnapshot string) (*policySnapshot, *nativePolicy, *ruleSnapshotJSON) {
	t.Helper()
	pe := newPolicyEngine()
	t.Cleanup(pe.close)
	if err := pe.applySnapshot(jsonSnapshot); err != nil {
		t.Fatalf("applySnapshot(%s): %v", jsonSnapshot, err)
	}
	snap := pe.snapshot.Load()
	var req ruleSnapshotJSON
	if err := json.Unmarshal([]byte(jsonSnapshot), &req); err != nil {
		t.Fatalf("decode payload: %v", err)
	}
	native, err := newNativePolicy(jsonSnapshot, snap.countRegexRules())
	if err != nil {
		t.Fatalf("native build failed for %s: %v", jsonSnapshot, err)
	}
	t.Cleanup(native.release)
	if mismatch := nativeFlagsMismatch(snap, native.flags); mismatch != "" {
		t.Fatalf("snapshot shape differs: %s", mismatch)
	}
	return snap, native, &req
}

// compareEngines drives the real Go entry point (normalization + filterEnabled + decision cache)
// and the native call with exactly the arguments production would pass.
func compareEngines(t *testing.T, snap *policySnapshot, native *nativePolicy, domain, app string, qtype uint16) {
	t.Helper()
	wantBlocked, wantReason := snap.evaluate(domain, app, qtype)
	gotBlocked, gotReason, ok := native.evaluate(normalizePolicyDomain(domain), strings.TrimSpace(app), qtype)
	if !ok {
		t.Fatalf("native evaluate failed for %q/%q/%d", domain, app, qtype)
	}
	if wantBlocked != gotBlocked || wantReason != gotReason {
		t.Fatalf("domain=%q app=%q qtype=%d: go=(%v,%q) rust=(%v,%q)",
			domain, app, qtype, wantBlocked, wantReason, gotBlocked, gotReason)
	}
}

func TestNativePolicyKernelAvailable(t *testing.T) {
	// loadNativeLibrary only hands out a library whose `diting_policy_abi_version` equals
	// nativePolicyABIVersion, so reaching this point proves the Go constant and
	// rust/diting-policy-core/src/ffi.rs agree.
	requireNativeKernel(t)
}

// TestNativeLowerMatchesGoSweepsEveryCodepoint pins the Rust port of `strings.ToLower`, which the
// whole pattern-normalization path depends on. One call per direction, every scalar value.
func TestNativeLowerMatchesGoSweepsEveryCodepoint(t *testing.T) {
	requireNativeKernel(t)
	var builder strings.Builder
	for r := rune(0); r <= 0x10FFFF; r++ {
		if r >= 0xD800 && r <= 0xDFFF {
			continue
		}
		builder.WriteRune(r)
	}
	source := builder.String()
	got, ok := nativeLower(source)
	if !ok {
		t.Fatal("nativeLower failed")
	}
	want := strings.ToLower(source)
	if got != want {
		for i := 0; i < len(source) && i < len(want); i++ {
			if got[i] != want[i] {
				t.Fatalf("lowercase differs at byte %d: rust=%q go=%q", i, got[i:min(i+24, len(got))], want[i:min(i+24, len(want))])
			}
		}
		t.Fatalf("lowercase length differs: rust=%d go=%d", len(got), len(want))
	}
}

// nativeSnapshotGenerators keeps the random payloads readable: every family the walk knows about.
func nativeSnapshotGenerators(rng *rand.Rand) (patterns []string, snapshot string) {
	labels := []string{"a", "b", "example", "com", "org", "net", "ads", "cdn", "cn", "xn--fiqs8s", "中国"}
	pick := func() string { return labels[rng.Intn(len(labels))] }
	domain := func() string {
		parts := make([]string, 1+rng.Intn(3))
		for i := range parts {
			parts[i] = pick()
		}
		return strings.Join(parts, ".")
	}
	pattern := func() string {
		switch rng.Intn(6) {
		case 0:
			return "*"
		case 1:
			return "*." + domain()
		case 2:
			return "ads*." + domain()
		case 3:
			return domain() + ".*"
		case 4:
			return strings.ToUpper(domain())
		default:
			return domain()
		}
	}

	globalBlock := make([]string, rng.Intn(4))
	globalAllow := make([]string, rng.Intn(4))
	globalImportant := make([]string, rng.Intn(3))
	disabled := make([]string, rng.Intn(3))
	for i := range globalBlock {
		globalBlock[i] = pattern()
		patterns = append(patterns, globalBlock[i])
	}
	for i := range globalAllow {
		globalAllow[i] = pattern()
		patterns = append(patterns, globalAllow[i])
	}
	for i := range globalImportant {
		globalImportant[i] = pattern()
		patterns = append(patterns, globalImportant[i])
	}
	for i := range disabled {
		disabled[i] = domain()
		patterns = append(patterns, disabled[i])
	}

	appRules := map[string]map[string][]string{}
	for _, app := range []string{"com.a", "com.b", "com.C"} {
		if rng.Intn(2) == 0 {
			continue
		}
		bucket := map[string][]string{}
		for _, key := range []string{"allow", "block", "important"} {
			if rng.Intn(2) != 0 {
				continue
			}
			values := make([]string, 1+rng.Intn(2))
			for i := range values {
				values[i] = pattern()
				patterns = append(patterns, values[i])
			}
			bucket[key] = values
		}
		appRules[app] = bucket
	}

	special := func(isAllow bool) []map[string]any {
		count := rng.Intn(3)
		rules := make([]map[string]any, 0, count)
		for i := 0; i < count; i++ {
			target := pattern()
			rule := map[string]any{"pattern": target, "source": fmt.Sprintf("src%d", i), "important": rng.Intn(4) == 0}
			switch rng.Intn(5) {
			case 0:
				rule["isRegex"] = true
				rule["pattern"] = fmt.Sprintf(`^ad[s0-9]*\.%s$`, strings.ReplaceAll(domain(), "中国", "cn"))
			case 1:
				rule["appScope"] = "com.a|com.b"
				rule["appInverted"] = rng.Intn(2) == 0
			case 2:
				rule["denyallow"] = domain() + "|" + domain()
			case 3:
				rule["dnsType"] = []string{"AAAA", "~AAAA", "A|HTTPS", "~A"}[rng.Intn(4)]
			}
			if strings.Contains(fmt.Sprint(rule["pattern"]), "中国") && rule["isRegex"] == true {
				delete(rule, "isRegex")
			}
			patterns = append(patterns, fmt.Sprint(rule["pattern"]))
			rules = append(rules, rule)
		}
		if isAllow {
			for _, rule := range rules {
				delete(rule, "important")
			}
		}
		return rules
	}

	inverted := func(important bool) []map[string]any {
		count := rng.Intn(2)
		rules := make([]map[string]any, 0, count)
		for i := 0; i < count; i++ {
			rule := map[string]any{"pattern": pattern(), "source": fmt.Sprintf("inv%d", i)}
			if important {
				rule["important"] = true
			}
			if rng.Intn(2) == 0 {
				rule["excludedApps"] = []string{"com.a", "com.b"}
			}
			patterns = append(patterns, fmt.Sprint(rule["pattern"]))
			rules = append(rules, rule)
		}
		return rules
	}

	payload := map[string]any{
		"filterEnabled":   rng.Intn(6) != 0,
		"globalBlock":     globalBlock,
		"globalAllow":     globalAllow,
		"globalImportant": globalImportant,
		"disabledRules":   disabled,
		"appRules":        appRules,
		"invertedBlock":   inverted(false),
		"invertedAllow":   inverted(false),
		"specialBlock":    special(false),
		"specialAllow":    special(true),
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		panic(err)
	}
	return patterns, string(raw)
}

// nativeParityRounds/nativeParitySeed let a longer fuzz run be started without editing the test:
//
//	DITING_POLICY_PARITY_ROUNDS=2000 go test -run TestNativePolicyMatchesGoOnRandomSnapshots
func nativeParityRounds() int {
	rounds := 60
	if value := strings.TrimSpace(os.Getenv("DITING_POLICY_PARITY_ROUNDS")); value != "" {
		if parsed, err := strconv.Atoi(value); err == nil && parsed > 0 {
			rounds = parsed
		}
	}
	return rounds
}

func nativeParitySeed() int64 {
	seed := int64(20240921)
	if value := strings.TrimSpace(os.Getenv("DITING_POLICY_PARITY_SEED")); value != "" {
		if parsed, err := strconv.ParseInt(value, 10, 64); err == nil {
			seed = parsed
		}
	}
	return seed
}

func TestNativePolicyMatchesGoOnRandomSnapshots(t *testing.T) {
	requireNativeKernel(t)
	rng := rand.New(rand.NewSource(nativeParitySeed()))
	apps := []string{"", "com.a", "com.b", "com.c", "com.C"}
	qtypes := []uint16{0, dns.TypeA, dns.TypeAAAA, dns.TypeHTTPS}
	for round := 0; round < nativeParityRounds(); round++ {
		patterns, snapshot := nativeSnapshotGenerators(rng)
		snap, native, req := buildNativeForTest(t, snapshot)
		for _, pattern := range patterns {
			probes := []string{
				strings.ToLower(pattern),
				strings.ReplaceAll(strings.ToLower(pattern), "*", "x"),
				strings.TrimPrefix(strings.ToLower(pattern), "*."),
			}
			for _, probe := range probes {
				for _, app := range apps {
					for _, qtype := range qtypes {
						compareEngines(t, snap, native, probe, app, qtype)
					}
				}
			}
		}
		// The cross-check the engine runs at apply time must pass for every generated payload too.
		if disagreement := nativeDisagreement(snap, native, policyProbes(req)); disagreement != "" {
			t.Fatalf("round %d: %s\npayload: %s", round, disagreement, snapshot)
		}
	}
}

// TestNativePolicyMatchesGoOnProbeHeavyPayloads covers the hand-written shapes the unit tests pin:
// denyallow, app scopes, dnsType and the priority ladder.
func TestNativePolicyMatchesGoOnProbeHeavyPayloads(t *testing.T) {
	requireNativeKernel(t)
	payloads := []string{
		`{"globalBlock":["ads.example.com","*.tracker.net"],"globalAllow":["safe.tracker.net"]}`,
		`{"specialBlock":[{"pattern":"example.com","denyallow":"good.example.com|safe.example.com"}]}`,
		`{"specialBlock":[{"pattern":"^ad[s0-9]*\\.test\\.com$","isRegex":true}],"specialAllow":[{"pattern":"^ad999\\.test\\.com$","isRegex":true}]}`,
		`{"specialBlock":[{"pattern":"v6-only-block.com","dnsType":"AAAA"},{"pattern":"non-v6-block.com","dnsType":"~AAAA"}]}`,
		`{"specialBlock":[{"pattern":"target.com","source":"global-normal"},{"pattern":"target-important.com","source":"app-important","important":true,"appScope":"com.test.app"}],"specialAllow":[{"pattern":"target.com","appScope":"com.test.app"},{"pattern":"target-important.com"}]}`,
		`{"globalImportant":["important.com"],"globalAllow":["*.allow.com"],"globalBlock":["*.block.com"],"appRules":{"com.a":{"allow":["x.com"],"block":["y.com"],"important":["z.com"]}}}`,
		`{"invertedBlock":[{"pattern":"*.track.com","source":"inv","important":true,"excludedApps":["com.a"]}],"invertedAllow":[{"pattern":"keep.track.com","excludedApps":["com.b"]}]}`,
	}
	domains := []string{
		"ads.example.com", "x.ads.example.com", "tracker.net", "attacker.net", "a.tracker.net",
		"safe.tracker.net", "good.example.com", "sub.good.example.com", "ad12.test.com",
		"ad999.test.com", "v6-only-block.com", "non-v6-block.com", "target.com",
		"target-important.com", "important.com", "a.allow.com", "a.block.com", "x.com", "y.com",
		"z.com", "q.track.com", "keep.track.com", "other.org", "",
	}
	apps := []string{"", "com.a", "com.b", "com.test.app", "com.other.app"}
	qtypes := []uint16{0, dns.TypeA, dns.TypeAAAA, dns.TypeHTTPS}
	for _, payload := range payloads {
		snap, native, _ := buildNativeForTest(t, payload)
		for _, domain := range domains {
			for _, app := range apps {
				for _, qtype := range qtypes {
					compareEngines(t, snap, native, domain, app, qtype)
				}
			}
		}
	}
}

// TestNativePolicyMatchesGoOnDTRI closes the loop for the subscription trie: the same fixture files
// the Go reader test uses are answered by both readers through both walks.
func TestNativePolicyMatchesGoOnDTRI(t *testing.T) {
	requireNativeKernel(t)
	root := filepath.Join("..", "..", "rust", "diting-rule-core", "tests", "fixtures")
	for _, name := range []string{"basic", "sources", "unicode"} {
		image, err := os.ReadFile(filepath.Join(root, name+".dtri"))
		if err != nil {
			t.Fatalf("%s image: %v", name, err)
		}
		path := filepath.Join(t.TempDir(), name+".dtri")
		if err := os.WriteFile(path, image, 0o600); err != nil {
			t.Fatalf("%s: write image: %v", name, err)
		}
		corpus, err := os.ReadFile(filepath.Join(root, name+".rules.txt"))
		if err != nil {
			t.Fatalf("%s corpus: %v", name, err)
		}
		payload, err := json.Marshal(map[string]any{
			"blockTriePath":          path,
			"importantBlockTriePath": path,
			"allowTriePath":          path,
			"importantAllowTriePath": path,
			"disabledRules":          []string{"metrics.sample.net"},
		})
		if err != nil {
			t.Fatal(err)
		}
		snap, native, _ := buildNativeForTest(t, string(payload))
		for _, line := range strings.Split(string(corpus), "\n") {
			if line == "" {
				continue
			}
			pattern := strings.Split(line, "\t")[0]
			for _, query := range []string{pattern, strings.ToUpper(pattern), "sub." + pattern} {
				compareEngines(t, snap, native, query, "", dns.TypeA)
			}
		}
		for _, query := range []string{"not-in-this-fixture.example", "example", "com", "net"} {
			compareEngines(t, snap, native, query, "", dns.TypeA)
		}
	}
}

// regexAtomPool is the vocabulary the random regex generator draws from: literals, classes,
// shorthands, anchors and the Unicode escapes rules actually contain.
var regexAtomPool = []string{
	"ads", "ad", "cn", "com", "example", "a1", "x", "track", "banner7",
	"[a-z]", "[0-9]", "[^.]", "[s0-9]", "[a-z0-9-]", "[[:alpha:]]",
	`\d`, `\w`, `\s`, `\D`, `\W`, `\S`, `\p{L}`, `\p{Greek}`,
	`.`, `\.`, `-`, `\`, "ä", "中国", "ß",
	"^", "$", `\b`, `\B`, `\A`, `\z`,
}

// randomRegexPattern builds a syntactically plausible rule pattern.
func randomRegexPattern(rng *rand.Rand) string {
	atom := func() string {
		base := regexAtomPool[rng.Intn(len(regexAtomPool))]
		switch rng.Intn(6) {
		case 0:
			return base + "*"
		case 1:
			return base + "+"
		case 2:
			return base + "?"
		case 3:
			return base + "{2}"
		case 4:
			return base + "{1,3}"
		default:
			return base
		}
	}
	var pattern strings.Builder
	if rng.Intn(3) == 0 {
		pattern.WriteString([]string{"(?i)", "(?s)", "(?m)", "(?U)"}[rng.Intn(4)])
	}
	if rng.Intn(2) == 0 {
		pattern.WriteString("^")
	}
	for i := 0; i < 1+rng.Intn(3); i++ {
		if rng.Intn(4) == 0 {
			pattern.WriteString("(" + atom() + "|" + atom() + ")")
			continue
		}
		pattern.WriteString(atom())
	}
	if rng.Intn(2) == 0 {
		pattern.WriteString("$")
	}
	return pattern.String()
}

func randomRegexDomain(rng *rand.Rand) string {
	alphabet := []string{
		"a", "b", "ads", "ad1", "x", "cn", "com", "example", "0", "9", "-", ".", "_",
		"Ä", "ä", "STRASSE", "straße", "中国", "例子", "İstanbul", "\u017F", "\u212A",
	}
	var domain strings.Builder
	for i := 0; i < 1+rng.Intn(5); i++ {
		domain.WriteString(alphabet[rng.Intn(len(alphabet))])
	}
	return domain.String()
}

// TestNativePolicyMatchesGoOnRandomRegexes is the risky half of the port: user regex rules are
// translated from Go's RE2 syntax into the Rust engine's, so this drives both engines over random
// patterns and random domains. Patterns the Rust engine refuses (and the Go engine accepts) are
// reported instead of failed: that path is a documented whole-snapshot fallback, not a wrong
// answer.
func TestNativePolicyMatchesGoOnRandomRegexes(t *testing.T) {
	requireNativeKernel(t)
	rng := rand.New(rand.NewSource(nativeParitySeed() + 7))
	rounds := nativeParityRounds()
	if rounds > 200 {
		rounds = 200
	}
	refused := 0
	for round := 0; round < rounds; round++ {
		pattern := randomRegexPattern(rng)
		payload, err := json.Marshal(map[string]any{
			"specialBlock": []map[string]any{{"pattern": pattern, "source": "rx", "isRegex": true}},
		})
		if err != nil {
			t.Fatal(err)
		}
		pe := newPolicyEngine()
		t.Cleanup(pe.close)
		if err := pe.applySnapshot(string(payload)); err != nil {
			t.Fatalf("applySnapshot(%s): %v", pattern, err)
		}
		snap := pe.snapshot.Load()
		native, err := newNativePolicy(string(payload), snap.countRegexRules())
		if err != nil {
			refused++
			t.Logf("pattern %q is left to the Go engine: %v", pattern, err)
			continue
		}
		for i := 0; i < 12; i++ {
			domain := randomRegexDomain(rng)
			compareEngines(t, snap, native, domain, "", dns.TypeA)
			compareEngines(t, snap, native, domain, "", 0)
		}
		native.release()
	}
	// A few construct-level gaps are acceptable (they degrade to the Go engine); a systematic
	// accept-set drift is not.
	if refused > rounds/4 {
		t.Fatalf("refused %d of %d patterns", refused, rounds)
	}
}

// The two benchmarks below are the apples-to-apples split of the old
// BenchmarkPolicyEvaluateLargeCold: the same snapshot, the same domains, once through the Rust
// kernel and once through the Go walk. `python rust/verify.py --bench` (or `go test -bench`) keeps
// the numbers in rust/README.md honest.
func benchmarkSnapshotPair(b *testing.B) (*policySnapshot, *nativePolicy) {
	b.Helper()
	snapshotJSON := largePolicySnapshotJSON(b)
	pe := newPolicyEngine()
	if err := pe.applySnapshot(snapshotJSON); err != nil {
		b.Fatal(err)
	}
	snap := pe.snapshot.Load()
	native, err := newNativePolicy(snapshotJSON, snap.countRegexRules())
	if err != nil {
		b.Skipf("Rust policy kernel not built: %v", err)
	}
	b.Cleanup(native.release)
	return snap, native
}

func BenchmarkPolicyEvaluateGoWalkLarge(b *testing.B) {
	snap, _ := benchmarkSnapshotPair(b)
	domains := benchmarkDomains()
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		snap.evaluateReference(domains[i%len(domains)], "", dns.TypeA)
	}
}

func BenchmarkPolicyEvaluateRustKernelLarge(b *testing.B) {
	_, native := benchmarkSnapshotPair(b)
	domains := benchmarkDomains()
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if _, _, ok := native.evaluate(domains[i%len(domains)], "", dns.TypeA); !ok {
			b.Fatal("native evaluate failed")
		}
	}
}

func BenchmarkPolicyApplyLargeWithRust(b *testing.B) {
	snapshotJSON := largePolicySnapshotJSON(b)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		pe := newPolicyEngine()
		if err := pe.applySnapshot(snapshotJSON); err != nil {
			b.Fatal(err)
		}
		pe.close()
	}
}
