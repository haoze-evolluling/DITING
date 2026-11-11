//! Prompt text for the two analysis modes.
//!
//! The four-section structure and the badge words (【高危】/【建议加入白名单】…) are what the
//! Markdown viewer colours, so editing this text also changes the rendered report. Both prompts are
//! addressed to the model, not to the user, which is why they are not localised.

use crate::traffic::Summary;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AnalysisRequest {
    pub system_prompt: String,
    pub user_prompt: String,
}

pub const DEFAULT_DOMAIN_SYSTEM_PROMPT: &str =
    "你是一名资深网络安全与 DNS 分析专家。你的任务是对用户给定的域名进行客观、准确、深入的安全分析。";

pub const DEFAULT_TRAFFIC_SYSTEM_PROMPT: &str =
    "你是一名网络安全与 DNS 流量分析专家，精通 DNS 协议、网络威胁防御和隐私保护。";

fn resolved_system_prompt(system_prompt: &str, fallback: &str) -> String {
    let trimmed = system_prompt.trim();
    if trimmed.is_empty() {
        fallback.to_string()
    } else {
        trimmed.to_string()
    }
}

/// Domain analysis: the four sections users expect, with the caller's log context in between.
pub fn domain_request(domain: &str, system_prompt: &str, context: Option<&str>) -> AnalysisRequest {
    let mut out = String::with_capacity(1024);
    out.push_str("请对以下目标域名进行网络安全与解析特征分析：\n");
    out.push_str(&format!("目标域名：{domain}\n"));
    if let Some(context) = context {
        let trimmed = context.trim();
        if !trimmed.is_empty() {
            out.push('\n');
            out.push_str("【近期设备请求与命中上下文】：\n");
            out.push_str(trimmed);
            out.push('\n');
        }
    }
    out.push('\n');
    out.push_str("请按以下结构输出分析报告（使用 Markdown 标题与要点列表，保持清晰明确）：\n");
    out.push_str("### 1. 域名归属与服务画像\n");
    out.push_str(
        "说明该域名所属厂商、业务分类（例如：核心云服务/CDN节点/常规业务/广告追踪/数据遥测/异常外联等）。\n",
    );
    out.push_str("### 2. 安全与风险评估\n");
    out.push_str(
        "明确给出风险评级：【安全】、【低风险】、【中风险】或【高危】，并说明原因（是否存在恶意挖矿、C2控制、钓鱼欺诈、隐私追踪等特征）。\n",
    );
    out.push_str("### 3. 处置建议\n");
    out.push_str(
        "给出具体处置建议：【建议正常放行】、【建议加入白名单】、【建议加入屏蔽规则】或【建议旁路直连】，并说明理由。\n",
    );
    out.push_str("### 4. 简要总结\n");
    out.push_str("用 1~2 句话概括最终结论。\n");

    AnalysisRequest {
        system_prompt: resolved_system_prompt(system_prompt, DEFAULT_DOMAIN_SYSTEM_PROMPT),
        user_prompt: out.trim_end().to_string(),
    }
}

/// Traffic analysis: the rendered summary, then either the four sections or an explicit
/// "samples are missing, do not invent any".
pub fn traffic_request(summary: &Summary, system_prompt: &str) -> AnalysisRequest {
    let mut out = String::with_capacity(1536);
    out.push_str("以下是当前设备近期产生的网络请求与 DNS 解析监控统计数据：\n");
    out.push_str("---\n");
    out.push_str(&summary.render());
    out.push_str("\n---\n\n");
    if summary.is_empty() {
        out.push_str("注意：以上采样窗口内没有任何记录。请明确说明「样本不足，无法研判」，不要编造域名或请求特征。\n");
    } else {
        out.push_str("请根据以上流量数据，生成一份网络安全分析报告（使用 Markdown 格式）：\n");
        out.push_str("### 1. 总体网络安全状况\n");
        out.push_str(
            "评估当前网络健康度等级（【健康良好】/【存在一般隐患】/【高风险可疑】），总结当前网络请求的总体特征。\n",
        );
        out.push_str("### 2. 关键与异常请求分析\n");
        out.push_str(
            "指出数据中高频请求、被频繁拦截、具有潜在数据遥测或可疑外联行为的域名与协议。\n",
        );
        out.push_str("### 3. 防护效果评估\n");
        out.push_str("分析当前软件规则拦截率是否处于合理区间，是否存在策略过度或防护盲区。\n");
        out.push_str("### 4. 优化建议\n");
        out.push_str(
            "列举建议加入黑名单屏蔽的风险域名，以及可能误拦截建议加入白名单的业务域名。\n",
        );
    }

    AnalysisRequest {
        system_prompt: resolved_system_prompt(system_prompt, DEFAULT_TRAFFIC_SYSTEM_PROMPT),
        user_prompt: out.trim_end().to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::traffic::{summarize, DnsRow};

    #[test]
    fn domain_prompt_has_the_four_sections() {
        let request = domain_request("example.com", "  be brief  ", None);
        assert_eq!(request.system_prompt, "be brief");
        assert!(request.user_prompt.starts_with(
            "请对以下目标域名进行网络安全与解析特征分析：\n目标域名：example.com\n\n"
        ));
        for section in [
            "### 1. 域名归属与服务画像",
            "### 2. 安全与风险评估",
            "### 3. 处置建议",
            "### 4. 简要总结",
        ] {
            assert!(request.user_prompt.contains(section), "missing {section}");
        }
        assert!(request.user_prompt.ends_with("用 1~2 句话概括最终结论。"));
        assert!(!request.user_prompt.contains("上下文"));
    }

    #[test]
    fn empty_system_prompt_falls_back_to_the_default() {
        let request = domain_request("example.com", "   ", None);
        assert_eq!(request.system_prompt, DEFAULT_DOMAIN_SYSTEM_PROMPT);
        let traffic = traffic_request(&summarize(&[], &[], None), "");
        assert_eq!(traffic.system_prompt, DEFAULT_TRAFFIC_SYSTEM_PROMPT);
    }

    #[test]
    fn context_is_inserted_between_the_target_and_the_sections() {
        let request = domain_request("example.com", "", Some("  DNS: a.test -> BLOCKED \n"));
        assert!(request.user_prompt.contains(
            "目标域名：example.com\n\n【近期设备请求与命中上下文】：\nDNS: a.test -> BLOCKED\n\n请按以下结构"
        ));
        // A blank context must not leave an empty section header behind.
        let blank = domain_request("example.com", "", Some("   "));
        assert!(!blank.user_prompt.contains("上下文"));
    }

    #[test]
    fn traffic_prompt_wraps_the_rendered_summary() {
        let dns = vec![DnsRow {
            domain: "a.test".to_string(),
            result: "BLOCKED".to_string(),
            cached: false,
        }];
        let request = traffic_request(&summarize(&dns, &[], None), "sys");
        assert_eq!(request.system_prompt, "sys");
        assert!(request
            .user_prompt
            .starts_with("以下是当前设备近期产生的网络请求与 DNS 解析监控统计数据：\n---\n【近期 DNS 监控统计】\n"));
        assert!(request.user_prompt.contains("\n---\n\n请根据以上流量数据"));
        assert!(request.user_prompt.contains("### 4. 优化建议"));
    }

    #[test]
    fn empty_samples_tell_the_model_not_to_invent_anything() {
        let request = traffic_request(&summarize(&[], &[], None), "");
        assert!(request.user_prompt.contains("样本不足，无法研判"));
        assert!(!request.user_prompt.contains("### 1."));
    }
}
