import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../features/auth/cubit/auth_cubit.dart';
import '../routing/nav_items.dart';
// Adjust if app_theme.dart lives somewhere else.
import '../theme/app_theme.dart';

const double _wideBreakpoint = 900;
const double _sidebarWidth = 270;

Future<void> _confirmLogout(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Container(
        height: 56,
        width: 56,
        decoration: const BoxDecoration(
          color: AppColors.softGreen,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.logout_rounded, color: AppColors.green),
      ),
      title: const Text('Log out?', textAlign: TextAlign.center),
      content: Text(
        'You will need to sign in again to manage the store.',
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(fontSize: 13, color: AppColors.mutedText),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(110, 42),
            backgroundColor: AppColors.green,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    context.read<AuthCubit>().signOut();
  }
}

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.child});

  final Widget child;

  int _selectedIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    final i = adminNavItems.indexWhere(
          (n) => loc == n.path || loc.startsWith('${n.path}/'),
    );
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex(context);
    final title = adminNavItems[selected].label;
    final email = context.select((AuthCubit c) => c.state.email);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;

        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: _sidebarWidth,
                  child: _SidebarContent(selectedIndex: selected),
                ),
                Expanded(
                  child: Column(
                    children: [
                      _TopBar(title: title, email: email),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            flexibleSpace: Container(
              decoration:
              const BoxDecoration(gradient: AppColors.brandGradient),
            ),
          ),
          drawer: Drawer(
            width: 290,
            backgroundColor: AppColors.deepGreen,
            surfaceTintColor: Colors.transparent,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Builder(
              builder: (drawerContext) => _SidebarContent(
                selectedIndex: selected,
                email: email,
                onNavigate: () => Navigator.of(drawerContext).pop(),
              ),
            ),
          ),
          body: child,
        );
      },
    );
  }
}

// ───────────────────────── Top bar (wide screens) ─────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.email});

  final String title;
  final String? email;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          if (email != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_circle_outlined,
                      size: 20, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    email!,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────── Sidebar / drawer content ─────────────────────────

class _SidebarContent extends StatelessWidget {
  const _SidebarContent({
    required this.selectedIndex,
    this.onNavigate,
    this.email,
  });

  final int selectedIndex;
  final VoidCallback? onNavigate;

  /// Shown in the footer (drawer only; wide layout shows it in the top bar).
  final String? email;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.deepGreen, Color(0xFF1B6B46)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Brand header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Row(
                children: [
                  Container(
                    height: 48,
                    width: 48,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: AppColors.green,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Handa Grocery',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Admin Panel',
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.white.withValues(alpha: 0.18), height: 1),

            // Navigation
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                itemCount: adminNavItems.length,
                itemBuilder: (context, i) {
                  final item = adminNavItems[i];
                  return _NavTile(
                    icon: item.icon,
                    label: item.label,
                    selected: i == selectedIndex,
                    onTap: () {
                      onNavigate?.call();
                      context.go(item.path);
                    },
                  );
                },
              ),
            ),

            Divider(color: Colors.white.withValues(alpha: 0.18), height: 1),

            // Footer: user + logout
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                children: [
                  if (email != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          const SizedBox(width: 6),
                          const Icon(Icons.account_circle_outlined,
                              size: 18, color: Colors.white70),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              email!,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Material(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        onNavigate?.call();
                        _confirmLogout(context);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 13),
                        child: Row(
                          children: [
                            const Icon(Icons.logout_rounded,
                                size: 20, color: Color(0xFFFFB4AB)),
                            const SizedBox(width: 14),
                            Text(
                              'Logout',
                              style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFFFB4AB),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.deepGreen : Colors.white70;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          splashColor: Colors.white.withValues(alpha: 0.12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    height: 8,
                    width: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.orange,
                      shape: BoxShape.circle,
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