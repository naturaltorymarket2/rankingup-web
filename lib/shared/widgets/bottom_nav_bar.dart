import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────
// 앱 하단 네비게이션 바 (홈 / 참여 내역 / 마이페이지)
// ─────────────────────────────────────────────────────────────────

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      selectedItemColor:   Colors.indigo,
      unselectedItemColor: Colors.grey.shade500,
      backgroundColor:     Colors.white,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 11,
      ),
      unselectedLabelStyle: const TextStyle(fontSize: 11),
      items: const [
        BottomNavigationBarItem(
          icon:            Icon(Icons.home_outlined),
          activeIcon:      Icon(Icons.home_rounded),
          label:           '홈',
        ),
        BottomNavigationBarItem(
          icon:            Icon(Icons.history_outlined),
          activeIcon:      Icon(Icons.history_rounded),
          label:           '참여 내역',
        ),
        BottomNavigationBarItem(
          icon:            Icon(Icons.person_outline_rounded),
          activeIcon:      Icon(Icons.person_rounded),
          label:           '마이페이지',
        ),
      ],
    );
  }
}
