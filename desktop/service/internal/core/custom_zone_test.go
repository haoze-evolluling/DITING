package core

import (
	"strings"
	"testing"

	"github.com/miekg/dns"
)

func zoneQuery(t *testing.T, engine *ZoneEngine, name string, qtype uint16) ([]dns.RR, dns.RR, bool) {
	t.Helper()
	return engine.Lookup(name, qtype)
}

func TestZone_LookupBasic(t *testing.T) {
	engine := NewZoneEngine(ZoneConfig{
		Enabled: true,
		TTL:     300,
		Zones: []ZoneEntry{{
			ID:      "z1",
			Origin:  "lan",
			Enabled: true,
			Content: `$ORIGIN lan.
@   IN SOA ns.lan. admin.lan. (2024010101 7200 3600 1209600 300)
@   IN NS  ns.lan.
ns  IN A   10.0.0.1
www IN A   10.0.0.10
www IN A   10.0.0.11
v6  IN AAAA 2001:db8::1
`,
		}},
	})

	if !engine.IsEnabled() {
		t.Fatal("引擎应处于启用状态")
	}

	answers, _, matched := zoneQuery(t, engine, "www.lan.", dns.TypeA)
	if !matched {
		t.Fatal("www.lan 应命中权威区")
	}
	if len(answers) != 2 {
		t.Fatalf("期望 2 条 A 记录，实得 %d", len(answers))
	}

	answers, _, matched = zoneQuery(t, engine, "v6.lan.", dns.TypeAAAA)
	if !matched || len(answers) != 1 {
		t.Fatalf("AAAA 查询异常: matched=%v len=%d", matched, len(answers))
	}

	answers, _, matched = zoneQuery(t, engine, "ns.lan.", dns.TypeA)
	if !matched || len(answers) != 1 {
		t.Fatalf("NS 主机名查询异常: matched=%v len=%d", matched, len(answers))
	}
}

// 区内存在但类型不匹配时必须返回权威 NODATA 并附 SOA，
// 而不是放行到上游 —— 放行正是内网域名泄漏的路径
func TestZone_AuthoritativeNodata(t *testing.T) {
	engine := NewZoneEngine(ZoneConfig{
		Enabled: true,
		Zones: []ZoneEntry{{
			ID:      "z1",
			Origin:  "lan",
			Enabled: true,
			Content: `$ORIGIN lan.
@   IN SOA ns.lan. admin.lan. (1 7200 3600 1209600 300)
www IN A   10.0.0.10
`,
		}},
	})

	answers, soa, matched := zoneQuery(t, engine, "www.lan.", dns.TypeAAAA)
	if !matched {
		t.Fatal("区内存在的名字请求其它类型也应命中（NODATA）")
	}
	if len(answers) != 0 {
		t.Fatalf("NODATA 应答不应携带记录，实得 %d 条", len(answers))
	}
	if soa == nil {
		t.Fatal("NODATA 必须附 SOA 以便客户端负缓存")
	}

	// 区顶点下完全不存在的名字同样由本地负责
	_, _, matched = zoneQuery(t, engine, "nothing.lan.", dns.TypeA)
	if !matched {
		t.Fatal("区顶点以下不存在的名字也应返回权威结论")
	}

	// 区外名字不受影响
	_, _, matched = zoneQuery(t, engine, "example.com.", dns.TypeA)
	if matched {
		t.Fatal("区外名字不应被本地接管")
	}
}

// $INCLUDE 会把宿主机的任意文件读进区解析并可能经报错回显，
// 必须被禁用；这里同时确认它不会静默成功
func TestZone_IncludeDisabled(t *testing.T) {
	engine := NewZoneEngine(ZoneConfig{
		Enabled: true,
		Zones: []ZoneEntry{{
			ID:      "z1",
			Origin:  "lan",
			Enabled: true,
			Content: "$INCLUDE /etc/passwd\nwww IN A 10.0.0.1\n",
		}},
	})

	states := engine.States()
	if len(states) != 1 {
		t.Fatalf("期望 1 个区状态，实得 %d", len(states))
	}
	if states[0].Loaded {
		t.Fatal("含 $INCLUDE 的区不应被加载")
	}
	if !strings.Contains(states[0].Error, "INCLUDE") {
		t.Fatalf("错误信息应指出 $INCLUDE，实得 %q", states[0].Error)
	}

	// 未加载的区不得留下任何记录
	if _, _, matched := zoneQuery(t, engine, "www.lan.", dns.TypeA); matched {
		t.Fatal("解析失败的区不应生效")
	}
}

func TestZone_DisabledZoneIgnored(t *testing.T) {
	engine := NewZoneEngine(ZoneConfig{
		Enabled: true,
		Zones: []ZoneEntry{
			{ID: "on", Origin: "lan", Enabled: true, Content: "www IN A 10.0.0.1\n"},
			{ID: "off", Origin: "corp", Enabled: false, Content: "www IN A 10.0.0.2\n"},
		},
	})

	if _, _, matched := zoneQuery(t, engine, "www.lan.", dns.TypeA); !matched {
		t.Fatal("启用的区应生效")
	}
	if _, _, matched := zoneQuery(t, engine, "www.corp.", dns.TypeA); matched {
		t.Fatal("停用的区不应生效")
	}

	states := engine.States()
	if len(states) != 2 || states[1].Loaded {
		t.Fatalf("停用的区状态不符: %+v", states)
	}
}

func TestZone_GlobalDisabled(t *testing.T) {
	engine := NewZoneEngine(ZoneConfig{
		Enabled: false,
		Zones:   []ZoneEntry{{ID: "z1", Origin: "lan", Enabled: true, Content: "www IN A 10.0.0.1\n"}},
	})

	if _, _, matched := zoneQuery(t, engine, "www.lan.", dns.TypeA); matched {
		t.Fatal("全局关闭时不应接管任何查询")
	}
}

func TestZone_ContentSizeLimit(t *testing.T) {
	big := strings.Repeat("; pad\n", MaxZoneContentBytes/6+2)
	engine := NewZoneEngine(ZoneConfig{
		Enabled: true,
		Zones:   []ZoneEntry{{ID: "z1", Origin: "lan", Enabled: true, Content: big}},
	})

	states := engine.States()
	if len(states) != 1 || states[0].Loaded {
		t.Fatalf("超限区不应被加载: %+v", states)
	}
	if !strings.Contains(states[0].Error, "超出上限") {
		t.Fatalf("错误信息应说明超限，实得 %q", states[0].Error)
	}
}

// $GENERATE 用一行文本就能展开出任意多条记录，字节上限挡不住它，
// 因此记录总数上限必须在解析过程中实时生效
func TestZone_RecordBudgetTruncates(t *testing.T) {
	engine := NewZoneEngine(ZoneConfig{
		Enabled: true,
		Zones: []ZoneEntry{{
			ID:      "z1",
			Origin:  "lan",
			Enabled: true,
			Content: "$GENERATE 1-50000 host$ IN A 10.0.0.1\n",
		}},
	})

	states := engine.States()
	if len(states) != 1 || !states[0].Loaded {
		t.Fatalf("超量的区应被加载但截断: %+v", states)
	}
	if states[0].Records > MaxZoneRecords {
		t.Fatalf("记录数 %d 超出上限 %d", states[0].Records, MaxZoneRecords)
	}
	if !strings.Contains(states[0].Error, "截断") {
		t.Fatalf("应提示已截断，实得 %q", states[0].Error)
	}
}

func TestZone_ZoneCountLimit(t *testing.T) {
	zones := make([]ZoneEntry, 0, MaxZoneCount+2)
	for i := 0; i < MaxZoneCount+2; i++ {
		zones = append(zones, ZoneEntry{
			ID:      "z",
			Origin:  "internal" + string(rune('a'+i%26)) + ".lan",
			Enabled: true,
			Content: "www IN A 10.0.0.1\n",
		})
	}
	engine := NewZoneEngine(ZoneConfig{Enabled: true, Zones: zones})

	states := engine.States()
	if len(states) != MaxZoneCount+2 {
		t.Fatalf("状态数应覆盖全部区，实得 %d", len(states))
	}
	for i := MaxZoneCount; i < len(states); i++ {
		if states[i].Loaded {
			t.Fatalf("第 %d 个区超出数量上限却已加载", i+1)
		}
	}
}

// 区内 CNAME 链要一直追到请求类型，只回一条孤立 CNAME 等同于一次无解答案
func TestZone_CNAMEChain(t *testing.T) {
	engine := NewZoneEngine(ZoneConfig{
		Enabled: true,
		Zones: []ZoneEntry{{
			ID:      "z1",
			Origin:  "lan",
			Enabled: true,
			Content: `$ORIGIN lan.
alias IN CNAME real.lan.
real  IN A     10.0.0.9
`,
		}},
	})

	answers, _, matched := zoneQuery(t, engine, "alias.lan.", dns.TypeA)
	if !matched {
		t.Fatal("alias.lan 应命中权威区")
	}
	if len(answers) != 2 {
		t.Fatalf("期望 CNAME + A 共 2 条，实得 %d: %v", len(answers), answers)
	}
	if _, ok := answers[0].(*dns.CNAME); !ok {
		t.Fatalf("首条应为 CNAME，实得 %T", answers[0])
	}
	if _, ok := answers[1].(*dns.A); !ok {
		t.Fatalf("次条应为 A，实得 %T", answers[1])
	}
}

// 记录本身就是索引里的对象，直接交出指针会让缓存与响应改写把结果写回索引
func TestZone_LookupReturnsCopies(t *testing.T) {
	engine := NewZoneEngine(ZoneConfig{
		Enabled: true,
		Zones:   []ZoneEntry{{ID: "z1", Origin: "lan", Enabled: true, Content: "www IN A 10.0.0.1\n"}},
	})

	first, _, _ := zoneQuery(t, engine, "www.lan.", dns.TypeA)
	if len(first) != 1 {
		t.Fatalf("期望 1 条记录，实得 %d", len(first))
	}
	first[0].Header().Name = "tampered."

	second, _, _ := zoneQuery(t, engine, "www.lan.", dns.TypeA)
	if second[0].Header().Name != "www.lan." {
		t.Fatalf("索引被外部修改污染: %q", second[0].Header().Name)
	}
}

func TestZone_ConfigureRebuilds(t *testing.T) {
	engine := NewZoneEngine(ZoneConfig{
		Enabled: true,
		Zones:   []ZoneEntry{{ID: "z1", Origin: "lan", Enabled: true, Content: "www IN A 10.0.0.1\n"}},
	})
	if _, _, matched := zoneQuery(t, engine, "www.lan.", dns.TypeA); !matched {
		t.Fatal("首次构建应生效")
	}

	engine.Configure(ZoneConfig{Enabled: true, Zones: []ZoneEntry{}})
	if _, _, matched := zoneQuery(t, engine, "www.lan.", dns.TypeA); matched {
		t.Fatal("重建后旧记录应被清除")
	}
	if engine.RecordCount() != 0 {
		t.Fatalf("重建后记录数应为 0，实得 %d", engine.RecordCount())
	}
}

func TestZone_DefaultTTLApplied(t *testing.T) {
	engine := NewZoneEngine(ZoneConfig{
		Enabled: true,
		TTL:     77,
		Zones:   []ZoneEntry{{ID: "z1", Origin: "lan", Enabled: true, Content: "www IN A 10.0.0.1\n"}},
	})

	answers, _, _ := zoneQuery(t, engine, "www.lan.", dns.TypeA)
	if answers[0].Header().Ttl != 77 {
		t.Fatalf("未显式声明 TTL 时应采用默认值 77，实得 %d", answers[0].Header().Ttl)
	}
}

func TestZone_ExplicitTTLWins(t *testing.T) {
	engine := NewZoneEngine(ZoneConfig{
		Enabled: true,
		TTL:     77,
		Zones:   []ZoneEntry{{ID: "z1", Origin: "lan", Enabled: true, Content: "www 600 IN A 10.0.0.1\n"}},
	})

	answers, _, _ := zoneQuery(t, engine, "www.lan.", dns.TypeA)
	if answers[0].Header().Ttl != 600 {
		t.Fatalf("显式 TTL 应优先，实得 %d", answers[0].Header().Ttl)
	}
}

func TestParseZonePreview(t *testing.T) {
	records, err := ParseZonePreview("lan", "$ORIGIN lan.\nwww IN A 10.0.0.1\nwww IN A 10.0.0.2\n", 300)
	if err != nil {
		t.Fatalf("预览解析失败: %v", err)
	}
	if len(records) != 2 {
		t.Fatalf("期望 2 条预览记录，实得 %d: %v", len(records), records)
	}
	for _, rec := range records {
		if !strings.Contains(rec, "10.0.0.") {
			t.Fatalf("预览内容不符: %q", rec)
		}
	}

	if _, err := ParseZonePreview("lan", "not a zone file at all !!!", 300); err == nil {
		t.Fatal("非法区文本应返回错误")
	}
	if _, err := ParseZonePreview("", "www IN A 10.0.0.1\n", 300); err == nil {
		t.Fatal("空顶点应返回错误")
	}
	if _, err := ParseZonePreview("lan", "$INCLUDE /etc/hosts\n", 300); err == nil {
		t.Fatal("$INCLUDE 应被拒绝")
	}
}

func TestNormalizeZoneConfig(t *testing.T) {
	cfg := ZoneConfig{Zones: []ZoneEntry{{Origin: "  lan  "}, {Origin: "corp", ID: "keep"}}}
	NormalizeZoneConfig(&cfg)

	if cfg.TTL != DefaultZoneTTL {
		t.Fatalf("默认 TTL 应被补齐，实得 %d", cfg.TTL)
	}
	if cfg.Zones[0].Origin != "lan" {
		t.Fatalf("顶点应被去除空白，实得 %q", cfg.Zones[0].Origin)
	}
	if cfg.Zones[0].ID == "" {
		t.Fatal("缺失的区 ID 应被补齐")
	}
	if cfg.Zones[1].ID != "keep" {
		t.Fatalf("已有 ID 不应被覆盖，实得 %q", cfg.Zones[1].ID)
	}
}

// 归一化会持久化结果，因此不得静默丢弃超限的区
func TestNormalizeZoneConfigKeepsOversizedInput(t *testing.T) {
	zones := make([]ZoneEntry, MaxZoneCount+5)
	for i := range zones {
		zones[i] = ZoneEntry{Origin: "z.lan", Enabled: true}
	}
	cfg := ZoneConfig{Zones: zones}
	NormalizeZoneConfig(&cfg)

	if len(cfg.Zones) != len(zones) {
		t.Fatalf("归一化不应删除用户的区，实得 %d 个（原 %d）", len(cfg.Zones), len(zones))
	}
}
