package core

import (
	"sort"
	"strconv"
	"strings"
)

// 极小 XML plist 序列化器。
//
// 只为生成 Apple 配置描述文件而存在：引入 howett.net/plist 这类完整
// 实现要连带支持 base64、日期、UID 等本项目用不到的类型，为了不到
// 百行的输出多一个依赖并不划算。这里只覆盖描述文件真正用到的
// 字典、数组、字符串与整数四种类型。
//
// 有意不提供反序列化：这份 XML 只出不进，写一个解析器意味着要为
// 各种畸形输入做防御，而本项目从不回读自己生成的文件。

// plistEntry 是字典里的一项，保持插入顺序以便输出稳定可读。
//
// Value 必须是 plist* 函数产出的**已序列化片段**（含元素标签），
// 而不是裸文本——直接传字面量会生成语法上解析不了的 plist。
type plistEntry struct {
	Key   string
	Value string
}

// plistDict 生成一个 <dict>
func plistDict(entries []plistEntry) string {
	var sb strings.Builder
	sb.WriteString("<dict>\n")
	for _, e := range entries {
		sb.WriteString("<key>")
		sb.WriteString(escapeXMLText(e.Key))
		sb.WriteString("</key>\n")
		sb.WriteString(e.Value)
		if !strings.HasSuffix(e.Value, "\n") {
			sb.WriteString("\n")
		}
	}
	sb.WriteString("</dict>")
	return sb.String()
}

// plistArray 把若干已序列化的值组成一个 <array>
func plistArray(values ...string) string {
	var sb strings.Builder
	sb.WriteString("<array>\n")
	for _, v := range values {
		sb.WriteString(v)
		if !strings.HasSuffix(v, "\n") {
			sb.WriteString("\n")
		}
	}
	sb.WriteString("</array>")
	return sb.String()
}

// plistString 生成一个 <string>；空串也要输出成空元素，
// 设备对「缺失的键」与「空值」处理并不一致
func plistString(s string) string {
	return "<string>" + escapeXMLText(s) + "</string>"
}

// plistInteger 生成一个 <integer>
func plistInteger(n int) string {
	return "<integer>" + strconv.Itoa(n) + "</integer>"
}

// escapeXMLText 转义 XML 文本节点里的保留字符。
//
// 顺序很重要：& 必须最先替换，否则后面替换产生的 & 会被二次转义成
// &amp;lt; 这样的字面量，属性值随之走样。
func escapeXMLText(s string) string {
	var sb strings.Builder
	sb.Grow(len(s))
	for _, r := range s {
		switch r {
		case '&':
			sb.WriteString("&amp;")
		case '<':
			sb.WriteString("&lt;")
		case '>':
			sb.WriteString("&gt;")
		case '"':
			sb.WriteString("&quot;")
		case '\'':
			sb.WriteString("&apos;")
		default:
			// XML 1.0 不允许出现除制表、换行、回车之外的 C0 控制字符，
			// 直接丢弃：把它们原样写出去会让整个描述文件无法解析
			if r < 0x20 && r != '\t' && r != '\n' && r != '\r' {
				continue
			}
			sb.WriteRune(r)
		}
	}
	return sb.String()
}

// sortedEntries 按 key 排序后返回，便于需要稳定顺序的场景
func sortedEntries(m map[string]string) []plistEntry {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	out := make([]plistEntry, 0, len(keys))
	for _, k := range keys {
		out = append(out, plistEntry{Key: k, Value: plistString(m[k])})
	}
	return out
}
