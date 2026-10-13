import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/admin_user_model.dart';
import 'admin_user_provider.dart';

// ─────────────────────────────────────────────────────────────────
// 어드민 회원 관리 (/admin/users)
//
// 가입한 회원을 보고, 기기를 초기화하고, 필요하면 계정을 지운다.
// 기기 중복(DEVICE_ALREADY_REGISTERED)을 풀어주려고 SQL Editor 를
// 열던 일을 여기서 끝낸다.
// ─────────────────────────────────────────────────────────────────

class AdminUserScreen extends ConsumerStatefulWidget {
  const AdminUserScreen({super.key});

  @override
  ConsumerState<AdminUserScreen> createState() => _AdminUserScreenState();
}

class _AdminUserScreenState extends ConsumerState<AdminUserScreen> {
  static const _kBlue = Color(0xFF1E3A8A);
  static const _kRed  = Color(0xFFB71C1C);

  final _searchCtrl = TextEditingController();
  final Set<String> _busy = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── 동작 ─────────────────────────────────────────────────────

  Future<void> _run(
    AdminUserRecord user,
    Future<Map<String, dynamic>> Function() action,
    String successMessage,
  ) async {
    if (_busy.contains(user.id)) return;
    setState(() => _busy.add(user.id));
    try {
      final res = await action();
      if (!mounted) return;
      if (res['success'] == true) {
        ref.invalidate(adminUsersProvider);
        _snack(successMessage, _kBlue);
      } else {
        _snack(_errorText(res), _kRed);
      }
    } catch (e) {
      if (!mounted) return;
      _snack('오류: $e', _kRed);
    } finally {
      if (mounted) setState(() => _busy.remove(user.id));
    }
  }

  String _errorText(Map<String, dynamic> res) {
    final error = res['error'] as String? ?? 'UNKNOWN';
    return switch (error) {
      'HAS_CAMPAIGNS' =>
        '등록된 광고가 ${res['count']}건 있어 삭제할 수 없습니다. '
            '광고 승인 화면에서 광고를 먼저 삭제해 주세요.',
      'CANNOT_DELETE_ADMIN' => '관리자 계정은 삭제할 수 없습니다.',
      'CANNOT_DELETE_SELF'  => '본인 계정은 삭제할 수 없습니다.',
      'LAST_ADMIN'          => '마지막 관리자 계정의 권한은 내릴 수 없습니다.',
      'NOT_FOUND'           => '회원을 찾을 수 없습니다. 목록을 새로고침해 주세요.',
      'FORBIDDEN'           => '어드민 권한이 없습니다.',
      _                     => '오류: $error',
    };
  }

  void _snack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: bg,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _confirmDelete(AdminUserRecord user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('회원 삭제'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.email,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text(
                '미션 ${user.missionCount}건, 포인트 ${_comma(user.balance)}P 가 '
                '함께 삭제됩니다.',
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 10),
              const Text(
                '되돌릴 수 없습니다. 같은 이메일로 다시 가입하면 새 계정이 됩니다.',
                style: TextStyle(fontSize: 12, color: _kRed),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _run(
      user,
      () => ref.read(adminUserRepositoryProvider).deleteUser(userId: user.id),
      '${user.email} 삭제 완료',
    );
  }

  /// 임시 비밀번호 발급 — 헷갈리는 글자(0/O, 1/l)는 뺀다
  String _makePassword() {
    const chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(10, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _issueTempPassword(AdminUserRecord user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('임시 비밀번호 발급'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.email,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              const Text(
                '새 비밀번호를 만들어 화면에 한 번 보여드립니다.\n'
                '지금 쓰던 비밀번호는 이 시점부터 쓸 수 없습니다.',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 8),
              const Text(
                '※ 회원에게 전달한 뒤, 로그인해서 본인 비밀번호로 바꾸도록 안내해 주세요.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('발급'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final password = _makePassword();
    if (_busy.contains(user.id)) return;
    setState(() => _busy.add(user.id));
    try {
      final res = await ref
          .read(adminUserRepositoryProvider)
          .setTempPassword(userId: user.id, password: password);
      if (!mounted) return;

      if (res['success'] == true) {
        await _showPassword(user, password);
      } else {
        _snack(_errorText(res), _kRed);
      }
    } catch (e) {
      if (!mounted) return;
      _snack('오류: $e', _kRed);
    } finally {
      if (mounted) setState(() => _busy.remove(user.id));
    }
  }

  Future<void> _showPassword(AdminUserRecord user, String password) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('임시 비밀번호'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.email, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  password,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '이 화면을 닫으면 다시 볼 수 없습니다. 지금 복사해 두세요.',
                style: TextStyle(fontSize: 12, color: _kRed),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: password));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('복사했습니다')),
                );
              }
            },
            child: const Text('복사'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeRole(AdminUserRecord user) async {
    final role = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('역할 변경 — ${user.email}'),
        children: [
          for (final r in const ['USER', 'ADMIN'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r),
              child: Row(
                children: [
                  Icon(
                    user.role == r
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: user.role == r ? _kBlue : Colors.grey,
                  ),
                  const SizedBox(width: 10),
                  Text(r == 'ADMIN'
                      ? '관리자 — 어드민 화면 접근'
                      : '앱 유저 — 미션 참여'),
                ],
              ),
            ),
        ],
      ),
    );
    if (role == null || role == user.role) return;

    await _run(
      user,
      () => ref
          .read(adminUserRepositoryProvider)
          .updateUser(userId: user.id, role: role),
      '${user.email} 역할을 $role 로 변경했습니다',
    );
  }

  /// 광고주 자격 켜고 끄기 — role 과 별개라 앱 유저 겸업이 가능하다
  Future<void> _toggleAdvertiser(AdminUserRecord user) async {
    final turnOn = !user.isAdvertiser;
    await _run(
      user,
      () => ref
          .read(adminUserRepositoryProvider)
          .updateUser(userId: user.id, isAdvertiser: turnOn),
      turnOn
          ? '${user.email} 광고주 자격을 부여했습니다'
          : '${user.email} 광고주 자격을 해제했습니다',
    );
  }

  Future<void> _clearDevice(AdminUserRecord user) async {
    await _run(
      user,
      () => ref
          .read(adminUserRepositoryProvider)
          .updateUser(userId: user.id, clearDevice: true),
      '${user.email} 기기 등록을 초기화했습니다',
    );
  }

  // ── 화면 ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(adminUsersProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text('어드민 — 회원 관리',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: _kBlue)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: _kBlue),
            onPressed: () => ref.invalidate(adminUsersProvider),
          ),
          TextButton.icon(
            onPressed: () => context.go('/admin/campaign'),
            icon: const Icon(Icons.campaign, size: 18),
            label: const Text('광고 승인'),
            style: TextButton.styleFrom(foregroundColor: _kBlue),
          ),
          TextButton.icon(
            onPressed: () => context.go('/admin/charge'),
            icon: const Icon(Icons.payments, size: 18),
            label: const Text('충전 승인'),
            style: TextButton.styleFrom(foregroundColor: _kBlue),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: '이메일 또는 기기 ID 검색',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              ref
                                  .read(adminUserSearchProvider.notifier)
                                  .state = '';
                              setState(() {});
                            },
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (v) =>
                      ref.read(adminUserSearchProvider.notifier).state = v,
                ),
              ),
              Expanded(
                child: usersAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('조회 오류: $e',
                          style: const TextStyle(color: _kRed)),
                    ),
                  ),
                  data: (users) => users.isEmpty
                      ? Center(
                          child: Text('회원이 없습니다.',
                              style: TextStyle(color: Colors.grey[500])),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                          itemCount: users.length + 1,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            if (i == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '전체 ${users.length}명',
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.grey[600]),
                                ),
                              );
                            }
                            final u = users[i - 1];
                            return _UserCard(
                              user:          u,
                              isBusy:        _busy.contains(u.id),
                              onChangeRole:  () => _changeRole(u),
                              onToggleAdvertiser: () => _toggleAdvertiser(u),
                              onClearDevice: () => _clearDevice(u),
                              onIssuePassword: () => _issueTempPassword(u),
                              onDelete:      () => _confirmDelete(u),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 회원 1명 카드
// ─────────────────────────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  final AdminUserRecord user;
  final bool            isBusy;
  final VoidCallback    onChangeRole;
  final VoidCallback    onToggleAdvertiser;
  final VoidCallback    onClearDevice;
  final VoidCallback    onIssuePassword;
  final VoidCallback    onDelete;

  const _UserCard({
    required this.user,
    required this.isBusy,
    required this.onChangeRole,
    required this.onToggleAdvertiser,
    required this.onClearDevice,
    required this.onIssuePassword,
    required this.onDelete,
  });

  static const _kRed = Color(0xFFB71C1C);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: user.roleColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(user.roleLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: user.roleColor)),
              ),
              if (user.isAdvertiser) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AdminUserRecord.advertiserColor
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('광고주',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AdminUserRecord.advertiserColor)),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: Text(user.email,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
              if (!user.emailConfirmed)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('이메일 미인증',
                      style: TextStyle(fontSize: 11, color: Color(0xFFE65100))),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 18,
            runSpacing: 4,
            children: [
              _Item('가입', _fmtDate(user.createdAt)),
              _Item('최근 로그인',
                  user.lastSignInAt == null ? '-' : _fmtDate(user.lastSignInAt!)),
              _Item('포인트', '${_comma(user.balance)}P'),
              _Item('미션', '성공 ${user.successCount} / 전체 ${user.missionCount}'),
              if (user.campaignCount > 0)
                _Item('광고', '${user.campaignCount}건'),
              _Item('기기', user.hasDevice ? '등록됨' : '없음'),
            ],
          ),
          if (user.hasDevice) ...[
            const SizedBox(height: 4),
            Text('기기 ID: ${user.deviceId}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
          const SizedBox(height: 10),
          if (isBusy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onChangeRole,
                  child: const Text('역할 변경', style: TextStyle(fontSize: 13)),
                ),
                if (user.hasDevice)
                  TextButton(
                    onPressed: onClearDevice,
                    child: const Text('기기 초기화',
                        style: TextStyle(fontSize: 13)),
                  ),
                TextButton(
                  onPressed: onToggleAdvertiser,
                  child: Text(
                    user.isAdvertiser ? '광고주 해제' : '광고주 지정',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: onIssuePassword,
                  child: const Text('임시 비밀번호',
                      style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 4),
                OutlinedButton(
                  onPressed: user.canDelete ? onDelete : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kRed,
                    side: BorderSide(
                        color: user.canDelete ? _kRed : Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: const Text('삭제'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}.${_p(d.month)}.${_p(d.day)} ${_p(d.hour)}:${_p(d.minute)}';
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

class _Item extends StatelessWidget {
  final String label;
  final String value;
  const _Item(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ',
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        Text(value,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

String _comma(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
