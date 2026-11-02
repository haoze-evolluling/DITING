part of 'form_page.dart';

/// Right-aligned text field row (upstream `FormRowTextField`). No border: the row's focus ring is
/// the outline. The cursor gets a few extra pixels so the rounded end does not clip it.
class FormRowTextField extends StatelessWidget {
  static const double _cursorWidth = 2;
  static const double _caretMargin = 1 + _cursorWidth;

  const FormRowTextField({
    super.key,
    required this.title,
    this.value,
    this.controller,
    this.initialValue,
    this.focusNode,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.obscureText = false,
    this.autofocus = false,
    this.monospace = false,
    this.invalid = false,
    this.trailingAction,
    this.onChanged,
    this.onFieldSubmitted,
  });

  final String title;
  final String? value;
  final TextEditingController? controller;
  final String? initialValue;
  final FocusNode? focusNode;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final bool autofocus;

  /// Monospace for addresses, ports and paths so digits line up.
  final bool monospace;

  final bool invalid;

  final Widget? trailingAction;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final towardEnd = Directionality.of(context) == TextDirection.ltr
        ? 1.0
        : -1.0;
    final action = trailingAction;
    final field = InputDecorationTheme(
      data: InputDecorationTheme.of(context)
          .copyWith(floatingLabelBehavior: FloatingLabelBehavior.never),
      child: Transform.translate(
        offset: Offset(_caretMargin * towardEnd, 0),
        child: _buildField(context),
      ),
    );
    return FormRow(
      title: title,
      invalid: invalid,
      trailing: action == null
          ? field
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: field),
                action,
              ],
            ),
    );
  }

  Widget _buildField(BuildContext context) {
    final hintText = this.hintText;
    final colorScheme = context.colorScheme;
    final style = monospace
        ? context.listTitleStyle.copyWith(fontFamily: appMonospaceFontFamily)
        : null;
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? (initialValue ?? value) : null,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      autofocus: autofocus,
      autocorrect: !monospace,
      enableSuggestions: !monospace,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      textAlign: TextAlign.end,
      cursorWidth: _cursorWidth,
      style: style,
      decoration: InputDecoration.collapsed(
        hintText: null,
        border: const NoInputBorder(),
        hint: hintText == null
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.only(end: _caretMargin),
                child: Text(
                  hintText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: AppTextStyle.body
                      .of(context)
                      .copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: monospace ? appMonospaceFontFamily : null,
                      ),
                ),
              ),
      ),
    );
  }
}

/// Password row with a reveal button (upstream `FormRowSecretTextField`).
class FormRowSecretTextField extends StatefulWidget {
  const FormRowSecretTextField({
    super.key,
    required this.title,
    required this.controller,
    this.focusNode,
    this.hintText,
    this.textInputAction,
    this.inputFormatters,
    this.invalid = false,
    this.onChanged,
    this.onFieldSubmitted,
  });

  final String title;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hintText;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool invalid;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  State<FormRowSecretTextField> createState() => _FormRowSecretTextFieldState();
}

class _FormRowSecretTextFieldState extends State<FormRowSecretTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final localizations = UiLocalizations.of(context);
    return FormRowTextField(
      title: widget.title,
      controller: widget.controller,
      focusNode: widget.focusNode,
      hintText: widget.hintText,
      obscureText: _obscure,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      invalid: widget.invalid,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onFieldSubmitted,
      trailingAction: CommonMinIconButtonTheme(
        child: IconButton(
          tooltip: _obscure
              ? localizations.showPassword
              : localizations.hidePassword,
          icon: GlyphIcon(_obscure ? AppGlyphs.eye : AppGlyphs.eyeOff),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

/// Right-aligned read-only value, such as a version number.
class FormRowValue extends StatelessWidget {
  const FormRowValue({
    super.key,
    required this.title,
    required this.value,
    this.monospace = false,
    this.description,
    this.leading,
    this.onPressed,
  });

  final String title;
  final String value;
  final bool monospace;
  final String? description;
  final Widget? leading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return FormRow(
      title: title,
      description: description,
      leading: leading,
      onPressed: onPressed,
      trailing: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.listSubtitleStyle.copyWith(
          color: colorScheme.onSurface,
          fontFamily: monospace ? appMonospaceFontFamily : null,
        ),
      ),
    );
  }
}

class FormRowSwitch extends StatelessWidget {
  const FormRowSwitch({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.description,
    this.leading,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? description;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return FormRow(
      title: title,
      description: description,
      leading: leading,
      onPressed: onChanged == null ? null : () => onChanged!(!value),
      trailing: CommonSwitch(value: value, onChanged: onChanged),
    );
  }
}
