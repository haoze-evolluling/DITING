// ignore_for_file: sort_child_properties_last
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/state/hub_settings_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// AI parameters and prompt (upstream `AgentApiParamsScreen`), persisted to
/// `agent_api_system_prompt` and `agent_api_temperature`.
class AgentParamsPage extends ConsumerWidget {
  const AgentParamsPage({super.key});

  /// Built-in prompt bodies stay Chinese on purpose: the model is asked in the same language
  /// as the analysis prompts in `lib/data/agent`, so the reports read consistently.
  static const _templatePrompts = <String>[
    '你是一名网络安全与 DNS 威胁情报专家。擅长对域名安全性、防盗链、'
        'DGA 随机特征、恶意软件外联及追踪探针进行分析，并给出明确的处置建议。',
    '你是一名资深网络协议工程师。请对给定的域名和流量快速给出最精炼的'
        '技术分类、风险等级与规则处置建议，格式化输出，杜绝多余套话。',
    '你是一名数字隐私与数据保护合规审计师。重点分析该域名是否涉及未经授权的'
        '用户行为遥测、设备指纹追踪或广告归因统计。',
  ];

  static List<String> _templateLabels(AppL10n l10n) => [
    l10n.agentParamsTemplateSecurity,
    l10n.agentParamsTemplateTechnical,
    l10n.agentParamsTemplatePrivacy,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentApiProvider);
    final notifier = ref.read(agentApiProvider.notifier);
    final temperatureLabel = state.temperature <= 0.3
        ? context.l10n.agentParamsTemperatureStrict
        : state.temperature <= 0.8
        ? context.l10n.agentParamsTemperatureBalanced
        : context.l10n.agentParamsTemperatureWild;
    return CommonScaffold(
      title: context.l10n.agentParamsTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.agentParamsPromptSection,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.compose),
                title: Text(context.l10n.agentParamsPromptItem),
                subtitle: Text(
                  state.systemPrompt.isEmpty
                      ? context.l10n.agentParamsPromptUnset
                      : state.systemPrompt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _editPrompt(context, notifier, state.systemPrompt),
              ),
              ListItem(
                title: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (index, label)
                        in _templateLabels(context.l10n).indexed)
                      TonalChip(
                        label: label,
                        color: context.raisedSurfaceLevel.colorOf(
                          context.colorScheme,
                        ),
                        foregroundColor: context.colorScheme.onSurfaceVariant,
                        onPressed: () => notifier.setSystemPrompt(
                          _templatePrompts[index],
                        ),
                      ),
                  ],
                ),
                minVerticalPadding: 10,
              ),
            ],
            footer: context.l10n.agentParamsPromptFooter,
          ),
          generateSection(
            title: context.l10n.agentParamsTemperatureSection,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.motion),
                title: Text(context.l10n.agentParamsTemperatureItem),
                subtitle: Text(temperatureLabel),
                trailing: Text(
                  state.temperature.toStringAsFixed(1),
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: context.colorScheme.primary),
                ),
              ),
              ListItem(
                title: Slider(
                  value: state.temperature.clamp(0, 2),
                  min: 0,
                  max: 2,
                  divisions: 20,
                  onChanged: notifier.setTemperature,
                ),
                minVerticalPadding: 4,
              ),
            ],
            footer: context.l10n.agentParamsTemperatureFooter,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _editPrompt(
    BuildContext context,
    AgentApiNotifier notifier,
    String initial,
  ) async {
    final value = await showFloatingDialog<String>(
      context: context,
      child: _PromptFieldDialog(initial: initial),
    );
    if (value != null) notifier.setSystemPrompt(value);
  }
}

/// The controller must be owned by the dialog: disposing it right after `await` fires on
/// `pop` while the exit animation runs, and the `TextField` then trips
/// `'_dependents.isEmpty': is not true`.
class _PromptFieldDialog extends StatefulWidget {
  const _PromptFieldDialog({required this.initial});

  final String initial;

  @override
  State<_PromptFieldDialog> createState() => _PromptFieldDialogState();
}

class _PromptFieldDialogState extends State<_PromptFieldDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: context.l10n.agentParamsPromptSection,
      hasFields: true,
      child: TextField(
        controller: _controller,
        minLines: 4,
        maxLines: 8,
        decoration: InputDecoration(
          hintText: context.l10n.agentParamsPromptHint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.uiCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(context.l10n.commonSave),
        ),
      ],
    );
  }
}
