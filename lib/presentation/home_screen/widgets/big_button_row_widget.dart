import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/custom_icon_widget.dart';

class BigButtonRowWidget extends StatefulWidget {
  final VoidCallback onAddReminder;
  final VoidCallback onSpeakCommand;
  final bool isListening;
  final bool isTablet;

  const BigButtonRowWidget({
    super.key,
    required this.onAddReminder,
    required this.onSpeakCommand,
    this.isListening = false,
    this.isTablet = false,
  });

  @override
  State<BigButtonRowWidget> createState() => _BigButtonRowWidgetState();
}

class _BigButtonRowWidgetState extends State<BigButtonRowWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _micPulseController;
  late Animation<double> _micPulse;

  @override
  void initState() {
    super.initState();
    _micPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _micPulse = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _micPulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(BigButtonRowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !oldWidget.isListening) {
      _micPulseController.repeat(reverse: true);
    } else if (!widget.isListening && oldWidget.isListening) {
      _micPulseController.stop();
      _micPulseController.reset();
    }
  }

  @override
  void dispose() {
    _micPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isTablet) {
      return Row(
        children: [
          Expanded(child: _buildAddButton(context)),
          const SizedBox(width: 12),
          Expanded(child: _buildSpeakButton(context)),
        ],
      );
    }
    return Column(
      children: [
        _buildAddButton(context),
        const SizedBox(height: 12),
        _buildSpeakButton(context),
      ],
    );
  }

  Widget _buildAddButton(BuildContext context) {
    return _BigButton(
      text: 'Add Reminder',
      iconName: 'add_circle',
      backgroundColor: AppTheme.primaryBlue,
      textColor: Colors.white,
      onPressed: () {
        HapticFeedback.heavyImpact();
        widget.onAddReminder();
      },
    );
  }

  Widget _buildSpeakButton(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _micPulse,
      builder: (ctx, child) => Transform.scale(
        scale: widget.isListening ? _micPulse.value : 1.0,
        child: child,
      ),
      child: _BigButton(
        text: widget.isListening ? 'Listening...' : 'Speak Command',
        iconName: widget.isListening ? 'mic' : 'mic',
        backgroundColor: widget.isListening
            ? AppTheme.secondaryTeal
            : theme.colorScheme.surface,
        textColor: widget.isListening ? Colors.white : AppTheme.primaryBlue,
        borderColor: widget.isListening ? null : AppTheme.primaryBlue,
        onPressed: () {
          HapticFeedback.heavyImpact();
          widget.onSpeakCommand();
        },
      ),
    );
  }
}

class _BigButton extends StatefulWidget {
  final String text;
  final String iconName;
  final Color backgroundColor;
  final Color textColor;
  final Color? borderColor;
  final VoidCallback onPressed;

  const _BigButton({
    required this.text,
    required this.iconName,
    required this.backgroundColor,
    required this.textColor,
    this.borderColor,
    required this.onPressed,
  });

  @override
  State<_BigButton> createState() => _BigButtonState();
}

class _BigButtonState extends State<_BigButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _pressScale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) {
        _pressController.reverse();
        widget.onPressed();
      },
      onTapCancel: () => _pressController.reverse(),
      child: AnimatedBuilder(
        animation: _pressScale,
        builder: (ctx, child) =>
            Transform.scale(scale: _pressScale.value, child: child),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 80),
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(18),
            border: widget.borderColor != null
                ? Border.all(color: widget.borderColor!, width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: widget.backgroundColor == Colors.white
                    ? Colors.black.withAlpha(20)
                    : widget.backgroundColor.withAlpha(89),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CustomIconWidget(
                  iconName: widget.iconName,
                  color: widget.textColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  widget.text,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: widget.textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
