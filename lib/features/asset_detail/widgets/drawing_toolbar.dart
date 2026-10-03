import 'package:flutter/material.dart';

import '../../charts/chart_types.dart';

/// Alt/ust arac cubugu: grafik tipi, cizim araclari, gosterge.
class DrawingToolbar extends StatelessWidget {
  const DrawingToolbar({
    super.key,
    required this.activeTool,
    required this.onToolSelected,
    required this.onIndicators,
    required this.onChartType,
    required this.onToggleFullscreen,
    this.hasDrawings = false,
    required this.onClearDrawings,
    this.fullscreen = false,
  });

  final DrawingTool activeTool;
  final ValueChanged<DrawingTool> onToolSelected;
  final VoidCallback onIndicators;
  final VoidCallback onChartType;
  final VoidCallback onToggleFullscreen;
  final bool hasDrawings;
  final VoidCallback onClearDrawings;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerTheme.color ?? Colors.grey),
          bottom: BorderSide(color: theme.dividerTheme.color ?? Colors.grey),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tool in DrawingTool.values)
              _ToolButton(
                icon: _icon(tool),
                rotate: tool == DrawingTool.vLine,
                label: tool.label,
                selected: activeTool == tool,
                onTap: () => onToolSelected(tool),
              ),
            const SizedBox(width: 4),
            _divider(theme),
            _ToolButton(
              icon: Icons.show_chart_rounded,
              label: 'Gösterge',
              onTap: onIndicators,
            ),
            _ToolButton(
              icon: Icons.candlestick_chart_rounded,
              label: 'Grafik',
              onTap: onChartType,
            ),
            if (hasDrawings) ...[
              _divider(theme),
              _ToolButton(
                icon: Icons.delete_sweep_rounded,
                label: 'Temizle',
                onTap: onClearDrawings,
              ),
            ],
            _divider(theme),
            _ToolButton(
              icon: fullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              label: fullscreen ? 'Çık' : 'Tam Ekran',
              onTap: onToggleFullscreen,
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(ThemeData theme) => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: theme.dividerTheme.color ?? Colors.grey,
      );

  IconData _icon(DrawingTool t) => switch (t) {
        DrawingTool.none => Icons.touch_app_rounded,
        DrawingTool.hLine => Icons.horizontal_rule_rounded,
        DrawingTool.vLine => Icons.horizontal_rule_rounded,
        DrawingTool.trendLine => Icons.show_chart_rounded,
        DrawingTool.channel => Icons.gradient_rounded,
        DrawingTool.supportResistance => Icons.architecture_rounded,
        DrawingTool.fibRetracement => Icons.stacked_line_chart_rounded,
        DrawingTool.fibExtension => Icons.linear_scale_rounded,
        DrawingTool.measure => Icons.straighten_rounded,
      };
}

/// Tek bir arac dugmesi.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.rotate = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool rotate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.16)
                : Colors.transparent,
          ),
          child: rotate
              ? RotatedBox(
                  quarterTurns: 1,
                  child: Icon(icon, size: 18, color: color),
                )
              : Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
