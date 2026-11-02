/// Prompt text for the two analysis modes. Kept verbatim from the 1.4.x Kotlin implementation: the
/// four-section structure and the badge words (【高危】/【建议加入白名单】…) are what the Markdown
/// viewer colours, so editing this text also changes the rendered report.
library;

import 'package:diting_android/data/agent/agent_traffic_summary.dart';

class AgentAnalysisRequest {
  const AgentAnalysisRequest({
    required this.systemPrompt,
    required this.userPrompt,
  });

  final String systemPrompt;
  final String userPrompt;
}

const defaultAgentSystemPrompt =
    '你是一名资深网络安全与 DNS 分析专家。你的任务是对用户给定的域名进行客观、'
    '准确、深入的安全分析。';

/// Builds a domain analysis request with the four prompt sections users expect.
AgentAnalysisRequest buildDomainAnalysisRequest({
  required String domain,
  required String systemPrompt,
  String? context,
}) {
  final buffer = StringBuffer()
    ..writeln('请对以下目标域名进行网络安全与解析特征分析：')
    ..writeln('目标域名：$domain');
  if (context != null && context.trim().isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('【近期设备请求与命中上下文】：')
      ..writeln(context.trim());
  }
  buffer
    ..writeln()
    ..writeln('请按以下结构输出分析报告（使用 Markdown 标题与要点列表，保持清晰明确）：')
    ..writeln('### 1. 域名归属与服务画像')
    ..writeln(
      '说明该域名所属厂商、业务分类（例如：核心云服务/CDN节点/常规业务/'
      '广告追踪/数据遥测/异常外联等）。',
    )
    ..writeln('### 2. 安全与风险评估')
    ..writeln(
      '明确给出风险评级：【安全】、【低风险】、【中风险】或【高危】，'
      '并说明原因（是否存在恶意挖矿、C2控制、钓鱼欺诈、隐私追踪等特征）。',
    )
    ..writeln('### 3. 处置建议')
    ..writeln(
      '给出具体处置建议：【建议正常放行】、【建议加入白名单】、'
      '【建议加入屏蔽规则】或【建议旁路直连】，并说明理由。',
    )
    ..writeln('### 4. 简要总结')
    ..writeln('用 1~2 句话概括最终结论。');
  return AgentAnalysisRequest(
    systemPrompt: systemPrompt.trim().isEmpty
        ? defaultAgentSystemPrompt
        : systemPrompt.trim(),
    userPrompt: buffer.toString().trimRight(),
  );
}

AgentAnalysisRequest buildTrafficAnalysisRequest({
  required RecentTrafficSummary summary,
  required String systemPrompt,
}) {
  final buffer = StringBuffer()
    ..writeln('以下是当前设备近期产生的网络请求与 DNS 解析监控统计数据：')
    ..writeln('---')
    ..writeln(summary.render())
    ..writeln('---')
    ..writeln();
  if (summary.isEmpty) {
    // Empty samples must explicitly tell the model not to invent anything.
    buffer.writeln(
      '注意：以上采样窗口内没有任何记录。请明确说明「样本不足，无法研判」，'
      '不要编造域名或请求特征。',
    );
  } else {
    buffer
      ..writeln('请根据以上流量数据，生成一份网络安全分析报告（使用 Markdown 格式）：')
      ..writeln('### 1. 总体网络安全状况')
      ..writeln(
        '评估当前网络健康度等级（【健康良好】/【存在一般隐患】/【高风险可疑】），'
        '总结当前网络请求的总体特征。',
      )
      ..writeln('### 2. 关键与异常请求分析')
      ..writeln('指出数据中高频请求、被频繁拦截、具有潜在数据遥测或可疑外联行为的域名与协议。')
      ..writeln('### 3. 防护效果评估')
      ..writeln('分析当前软件规则拦截率是否处于合理区间，是否存在策略过度或防护盲区。')
      ..writeln('### 4. 优化建议')
      ..writeln('列举建议加入黑名单屏蔽的风险域名，以及可能误拦截建议加入白名单的业务域名。');
  }
  return AgentAnalysisRequest(
    systemPrompt: systemPrompt.trim().isEmpty
        ? '你是一名网络安全与 DNS 流量分析专家，精通 DNS 协议、网络威胁防御和隐私保护。'
        : systemPrompt.trim(),
    userPrompt: buffer.toString().trimRight(),
  );
}
