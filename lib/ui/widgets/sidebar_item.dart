import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme/app_theme.dart';

class SidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  State<SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<SidebarItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.isActive
        ? (widget.isDark
            ? Colors.white.withOpacity(0.1)
            : AppColors.lightPrimary.withOpacity(0.1))
        : (_isHovered
            ? (widget.isDark
                ? Colors.white.withOpacity(0.05)
                : AppColors.lightPrimary.withOpacity(0.05))
            : Colors.transparent);

    final textColor = widget.isActive
        ? (widget.isDark ? Colors.white : AppColors.lightPrimary)
        : (widget.isDark
            ? (_isHovered ? Colors.grey[200] : Colors.grey[400])
            : (_isHovered
                ? AppColors.lightPrimary
                : AppColors.lightPrimary.withOpacity(0.7)));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              FaIcon(
                widget.icon,
                size: 18,
                color: textColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        widget.isActive ? FontWeight.bold : FontWeight.normal,
                    color: textColor,
                  ),
                ),
              ),
              if (widget.isActive)
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color:
                        widget.isDark ? Colors.white : AppColors.lightPrimary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
