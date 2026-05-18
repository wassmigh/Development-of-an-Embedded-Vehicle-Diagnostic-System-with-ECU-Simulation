import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;

  const CustomAppBar({super.key, this.title = 'DIAG SMARTER', this.actions});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 80.0,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          const Icon(Icons.directions_car, color: AppColors.cyan, size: 28),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.cyan,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(80.0);
}
