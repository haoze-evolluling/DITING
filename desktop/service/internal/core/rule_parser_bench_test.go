package core

// rule_parser_bench_test.go 是整份列表解析的端到端基准：编码 + FFI + 内核解析 + 解码 + Go 侧补做
// （正则编译、$dnsrewrite 取值解析）。
//
// 语料由外部提供，避免把几 MB 的合成列表塞进仓库：
//
//	python - <<'PY' > /tmp/bench100k.txt
//	... 10 万行：纯域名 / 白名单 / 通配 / $important / $dnstype / $denyallow / 正则 / punycode IDN
//	PY
//	DITING_PARSE_BENCH=/tmp/bench100k.txt \
//	  go test -run XXX -bench BenchmarkParseRulesLarge -benchtime 5x ./internal/core
//
// 纯内核（不含跨边界编解码）用 `cargo run --release -p diting-filter-core --example parse_bench --
// /tmp/bench100k.txt` 测；两条命令的数字一起写进 rust/README.md 的「性能」。

import (
	"bytes"
	"os"
	"testing"
)

func BenchmarkParseRulesLarge(b *testing.B) {
	path := os.Getenv("DITING_PARSE_BENCH")
	data, err := os.ReadFile(path)
	if err != nil {
		b.Skipf("DITING_PARSE_BENCH 未指向可读语料: %v", err)
	}
	b.SetBytes(int64(len(data)))
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		rules, err := ParseRules(bytes.NewReader(data), "bench")
		if err != nil {
			b.Fatalf("ParseRules: %v", err)
		}
		if len(rules) == 0 {
			b.Fatal("语料一行都没解析出来")
		}
	}
}
