import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../providers/group_provider.dart';
import '../widgets/group_card.dart';
import '../../domain/entities/group_entity.dart';

/// Gruplar Sayfası
class GroupsPage extends ConsumerStatefulWidget {
  const GroupsPage({super.key});

  @override
  ConsumerState<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends ConsumerState<GroupsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    
    // Verileri önceden yükle ve cache'le
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Her iki tab için de verileri önceden yükle
      ref.read(allGroupsProvider.future);
      ref.read(activeUsersProvider.future);
      if (ref.read(isAdminProvider)) {
        ref.read(pendingUsersProvider.future);
      }
    });
  }

  void _onTabChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gruplar ve Üyeler'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Gruplar'),
            Tab(text: 'Üyeler'),
          ],
        ),
        actions: [
          if (isAdminOrCoach && _tabController.index == 0)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Yeni Grup',
              onPressed: () => context.pushNamed(RouteNames.createGroup),
            ),
          if (isAdminOrCoach && _tabController.index == 1)
            IconButton(
              icon: const Icon(Icons.assessment),
              tooltip: 'Etkinlik Raporu',
              onPressed: () => context.pushNamed(RouteNames.eventReport),
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGroupsTab(),
          _buildUsersTab(isAdmin),
        ],
      ),
    );
  }

  Widget _buildGroupsTab() {
    final groupsAsync = ref.watch(allGroupsProvider);
    // Sadece loading state için watch et, her build'de yeniden hesaplama yapma
    final membershipState = ref.watch(groupMembershipProvider);
    final isLoadingMembership = membershipState is AsyncLoading;

    return groupsAsync.when(
      data: (groups) {
        if (groups.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.groups_outlined,
            title: 'Henüz grup yok',
            description: 'Antrenman grupları burada görünecek',
          );
        }

        // Filtreleme işlemini optimize et - sadece bir kez yap
        final userGroups = groups.where((g) => g.isUserMember).toList();
        final otherGroups = groups.where((g) => !g.isUserMember).toList();

        // Liste item'larını oluştur
        final items = <_GroupListItem>[];
        
        if (userGroups.isNotEmpty) {
          items.add(_GroupListItem.header(
            icon: Icons.check_circle,
            title: 'Gruplarım',
            iconColor: AppColors.success,
          ));
          items.addAll(userGroups.map((g) => _GroupListItem.group(g, true)));
          if (otherGroups.isNotEmpty) {
            items.add(_GroupListItem.spacer());
          }
        }
        
        if (otherGroups.isNotEmpty) {
          items.add(_GroupListItem.header(
            icon: Icons.groups_outlined,
            title: 'Diğer Gruplar',
            iconColor: AppColors.neutral500,
          ));
          items.addAll(otherGroups.map((g) => _GroupListItem.group(g, false)));
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(allGroupsProvider);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return item.build(
                context: context,
                ref: ref,
                isLoadingMembership: isLoadingMembership,
                onJoinLeave: (groupId, isMember) => 
                    _handleJoinLeave(context, ref, groupId, isMember),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: LoadingWidget()),
      error: (error, _) => Center(
        child: ErrorStateWidget(
          title: 'Gruplar yüklenemedi',
          message: error.toString(),
          onRetry: () => ref.invalidate(allGroupsProvider),
        ),
      ),
    );
  }

  Widget _buildUsersTab(bool isAdmin) {
    final activeUsersAsync = ref.watch(activeUsersProvider);
    final pendingUsersAsync = isAdmin ? ref.watch(pendingUsersProvider) : null;
    final searchQuery = _searchController.text.toLowerCase().trim();

    return Column(
      children: [
        // Arama alanı
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: AppSearchField(
            controller: _searchController,
            hint: 'Üye ara...',
            onChanged: (value) {
              setState(() {}); // Filtrelemeyi güncelle
            },
            onClear: () {
              setState(() {}); // Filtrelemeyi güncelle
            },
          ),
        ),
        // Liste
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(activeUsersProvider);
              if (isAdmin) {
                ref.invalidate(pendingUsersProvider);
              }
            },
            child: activeUsersAsync.when(
              data: (users) {
                // Arama sorgusuna göre filtrele - sadece bir kez
                final filteredUsers = searchQuery.isEmpty
                    ? users
                    : users.where((user) {
                        final fullName = user.fullName.toLowerCase();
                        final email = user.email.toLowerCase();
                        return fullName.contains(searchQuery) ||
                            email.contains(searchQuery);
                      }).toList();

                // Pending users'ı da filtrele
                List<UserEntity> filteredPendingUsers = [];
                if (isAdmin && pendingUsersAsync != null) {
                  final pendingData = pendingUsersAsync.value;
                  if (pendingData != null) {
                    filteredPendingUsers = searchQuery.isEmpty
                        ? pendingData
                        : pendingData.where((user) {
                            final fullName = user.fullName.toLowerCase();
                            final email = user.email.toLowerCase();
                            return fullName.contains(searchQuery) ||
                                email.contains(searchQuery);
                          }).toList();
                  }
                }

                // Tüm item'ları oluştur
                final items = <_UserListItem>[];
                
                if (filteredUsers.isEmpty && filteredPendingUsers.isEmpty) {
                  return EmptyStateWidget(
                    icon: Icons.search_off,
                    title: searchQuery.isEmpty
                        ? 'Henüz üye yok'
                        : 'Sonuç bulunamadı',
                    description: searchQuery.isEmpty
                        ? 'Aktif üyeler burada görünecek'
                        : '"$searchQuery" için sonuç bulunamadı',
                  );
                }

                if (filteredUsers.isNotEmpty) {
                  items.add(_UserListItem.header(
                    icon: Icons.people,
                    title: 'Aktif Üyeler',
                    count: filteredUsers.length,
                    totalCount: searchQuery.isNotEmpty ? users.length : null,
                    iconColor: AppColors.success,
                  ));
                  items.addAll(filteredUsers.map((u) => _UserListItem.user(u, false)));
                }

                if (filteredPendingUsers.isNotEmpty) {
                  if (filteredUsers.isNotEmpty) {
                    items.add(_UserListItem.spacer());
                  }
                  final pendingData = pendingUsersAsync?.value ?? [];
                  items.add(_UserListItem.header(
                    icon: Icons.pending_actions,
                    title: 'Onay Bekleyenler',
                    count: filteredPendingUsers.length,
                    totalCount: searchQuery.isNotEmpty ? pendingData.length : null,
                    iconColor: AppColors.warning,
                  ));
                  items.addAll(filteredPendingUsers.map((u) => _UserListItem.user(u, true)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return item.build(
                      context: context,
                      ref: ref,
                      onApproveUser: (userId) => _handleApproveUser(context, ref, userId),
                      onDeactivateUser: (userId) => _handleDeactivateUser(context, ref, userId),
                      onShowRoleChangeDialog: (user) => _showRoleChangeDialog(context, ref, user),
                    );
                  },
                );
              },
              loading: () => const Center(child: LoadingWidget()),
              error: (error, _) => Center(
                child: ErrorStateWidget(
                  title: 'Üyeler yüklenemedi',
                  message: error.toString(),
                  onRetry: () => ref.invalidate(activeUsersProvider),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }


  void _handleApproveUser(BuildContext context, WidgetRef ref, String userId) async {
    // Async işlemden sonra doğrudan context kullanmamak için messenger'ı başta al
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kullanıcıyı Onayla'),
        content: const Text(
          'Bu kullanıcıyı onaylamak istediğinizden emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Onayla',
              style: TextStyle(color: AppColors.success),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(userApprovalProvider.notifier).approveUser(userId);

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Kullanıcı onaylandı'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _handleDeactivateUser(BuildContext context, WidgetRef ref, String userId) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kullanıcıyı Pasifleştir'),
        content: const Text(
          'Bu kullanıcıyı pasifleştirmek istediğinizden emin misiniz? Kullanıcı giriş yapamayacak ve uygulamayı kullanamayacaktır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Pasifleştir',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(userApprovalProvider.notifier).deactivateUser(userId);

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Kullanıcı pasifleştirildi'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showRoleChangeDialog(BuildContext context, WidgetRef ref, UserEntity user) async {
    final messenger = ScaffoldMessenger.of(context);
    // Mevcut ana rolü belirle (öncelik: super_admin > coach > member)
    String currentRole = 'member';
    if (user.isAdmin) {
      currentRole = 'super_admin';
    } else if (user.isCoach) {
      currentRole = 'coach';
    }

    // Seçili rolü tutmak için state (referansı korumak için list kullanıyoruz)
    final selectedRole = <String>[currentRole];

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('${user.fullName} Rolünü Değiştir'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kullanıcının rolünü seçin:',
                  style: AppTypography.bodyMedium,
                ),
                const SizedBox(height: 16),
                _buildRoleRadio(
                  context,
                  setState,
                  selectedRole,
                  'super_admin',
                  'Süper Admin',
                  AppColors.superAdmin,
                  Icons.shield,
                ),
                _buildRoleRadio(
                  context,
                  setState,
                  selectedRole,
                  'coach',
                  'Coach',
                  AppColors.coach,
                  Icons.sports,
                ),
                _buildRoleRadio(
                  context,
                  setState,
                  selectedRole,
                  'member',
                  'Üye',
                  AppColors.neutral500,
                  Icons.person,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () {
                // Eğer hiç rol seçilmemişse, member yap
                if (selectedRole.isEmpty) {
                  selectedRole.add('member');
                }
                Navigator.pop(context, true);
              },
              child: Text(
                'Kaydet',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );

    if (result == true && selectedRole.isNotEmpty) {
      // Rolü güncelle
      try {
        await ref.read(userRoleUpdateProvider.notifier).updateUserRole(
              user.id,
              [selectedRole.first],
            );

        messenger.showSnackBar(
          SnackBar(
            content: Text('${user.fullName} kullanıcısının rolü güncellendi'),
            backgroundColor: AppColors.success,
          ),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Rol güncellenirken hata: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildRoleRadio(
    BuildContext context,
    StateSetter setState,
    List<String> selectedRole,
    String roleValue,
    String roleLabel,
    Color roleColor,
    IconData roleIcon,
  ) {
    return RadioListTile<String>(
      value: roleValue,
      groupValue: selectedRole.isNotEmpty ? selectedRole.first : null,
      onChanged: (value) {
        if (value != null) {
          setState(() {
            selectedRole.clear();
            selectedRole.add(value);
          });
        }
      },
      title: Row(
        children: [
          Icon(roleIcon, color: roleColor, size: 20),
          const SizedBox(width: 8),
          Text(
            roleLabel,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      activeColor: roleColor,
      contentPadding: EdgeInsets.zero,
    );
  }

  void _handleJoinLeave(BuildContext context, WidgetRef ref, String groupId, bool isMember) async {
    final notifier = ref.read(groupMembershipProvider.notifier);

    if (isMember) {
      // Gruptan ayrıl
      final confirmed = await _showLeaveConfirmation(context);
      if (confirmed) {
        await notifier.leaveGroup(groupId);
      }
    } else {
      // Gruba katıl
      try {
        await notifier.joinGroup(groupId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gruba katıldınız'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } on UserAlreadyInGroupException catch (e) {
        if (context.mounted) {
          _showAlreadyInGroupDialog(context, ref, e, targetGroupId: groupId);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gruba katılırken hata: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  void _showAlreadyInGroupDialog(
    BuildContext context,
    WidgetRef ref,
    UserAlreadyInGroupException e, {
    required String targetGroupId,
  }) {
    final groupName = e.currentGroupName ?? 'mevcut grup';
    final currentGroupId = e.currentGroupId;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zaten bir gruba üyesiniz'),
        content: Text(
          'Şu an "$groupName" grubuna üyesiniz. Başka bir gruba geçmek için önce bu gruptan ayrılmalısınız.',
        ),
        actions: [
          if (currentGroupId != null)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final notifier = ref.read(groupMembershipProvider.notifier);
                try {
                  await notifier.leaveGroup(currentGroupId);
                  await notifier.joinGroup(targetGroupId);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Grup değiştirildi, yeni gruba katıldınız'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                } catch (err) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('İşlem sırasında hata: $err'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: const Text('Çıkıp bu gruba katıl'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showLeaveConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Gruptan Ayrıl'),
            content: const Text(
              'Bu gruptan ayrılmak istediğinizden emin misiniz?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('İptal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Ayrıl',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }
}

/// Liste item'ı için helper class (performans optimizasyonu)
class _GroupListItem {
  final _ItemType type;
  final TrainingGroupEntity? group;
  final bool? isUserMember;
  final IconData? icon;
  final String? title;
  final Color? iconColor;

  _GroupListItem._({
    required this.type,
    this.group,
    this.isUserMember,
    this.icon,
    this.title,
    this.iconColor,
  });

  factory _GroupListItem.group(TrainingGroupEntity group, bool isUserMember) {
    return _GroupListItem._(
      type: _ItemType.group,
      group: group,
      isUserMember: isUserMember,
    );
  }

  factory _GroupListItem.header({
    required IconData icon,
    required String title,
    required Color iconColor,
  }) {
    return _GroupListItem._(
      type: _ItemType.header,
      icon: icon,
      title: title,
      iconColor: iconColor,
    );
  }

  factory _GroupListItem.spacer() {
    return _GroupListItem._(type: _ItemType.spacer);
  }

  Widget build({
    required BuildContext context,
    required WidgetRef ref,
    required bool isLoadingMembership,
    required void Function(String groupId, bool isMember) onJoinLeave,
  }) {
    switch (type) {
      case _ItemType.group:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GroupCard(
            key: ValueKey('group_${group!.id}'),
            group: group!,
            onTap: () => context.pushNamed(
              RouteNames.groupDetail,
              pathParameters: {'groupId': group!.id},
            ),
            onJoinLeave: () => onJoinLeave(group!.id, isUserMember!),
            isLoading: isLoadingMembership,
          ),
        );
      case _ItemType.header:
        return _SectionHeader(
          icon: icon!,
          title: title!,
          iconColor: iconColor!,
        );
      case _ItemType.spacer:
        return const SizedBox(height: 12);
    }
  }
}

enum _ItemType {
  group,
  header,
  spacer,
}

/// User liste item'ı için helper class (performans optimizasyonu)
class _UserListItem {
  final _UserItemType type;
  final UserEntity? user;
  final bool? isPending;
  final IconData? icon;
  final String? title;
  final Color? iconColor;
  final int? count;
  final int? totalCount;

  _UserListItem._({
    required this.type,
    this.user,
    this.isPending,
    this.icon,
    this.title,
    this.iconColor,
    this.count,
    this.totalCount,
  });

  factory _UserListItem.user(UserEntity user, bool isPending) {
    return _UserListItem._(
      type: _UserItemType.user,
      user: user,
      isPending: isPending,
    );
  }

  factory _UserListItem.header({
    required IconData icon,
    required String title,
    required Color iconColor,
    required int count,
    int? totalCount,
  }) {
    return _UserListItem._(
      type: _UserItemType.header,
      icon: icon,
      title: title,
      iconColor: iconColor,
      count: count,
      totalCount: totalCount,
    );
  }

  factory _UserListItem.spacer() {
    return _UserListItem._(type: _UserItemType.spacer);
  }

  Widget build({
    required BuildContext context,
    required WidgetRef ref,
    required void Function(String userId) onApproveUser,
    required void Function(String userId) onDeactivateUser,
    required void Function(UserEntity user) onShowRoleChangeDialog,
  }) {
    switch (type) {
      case _UserItemType.user:
        if (isPending!) {
          return _buildPendingUserCard(context, ref, user!, onApproveUser);
        } else {
          return _buildUserCard(
            context,
            ref,
            user!,
            onDeactivateUser,
            onShowRoleChangeDialog,
          );
        }
      case _UserItemType.header:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon!,
                  size: 20,
                  color: iconColor!,
                ),
                const SizedBox(width: 8),
                Text(
                  '$title (${count!}${totalCount != null ? ' / $totalCount' : ''})',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        );
      case _UserItemType.spacer:
        return const SizedBox(height: 32);
    }
  }

  Widget _buildUserCard(
    BuildContext context,
    WidgetRef ref,
    UserEntity user,
    void Function(String userId) onDeactivateUser,
    void Function(UserEntity user) onShowRoleChangeDialog,
  ) {
    final isAdmin = ref.watch(isAdminProvider);
    final approvalState = ref.watch(userApprovalProvider);
    final roleUpdateState = ref.watch(userRoleUpdateProvider);
    final currentUser = ref.watch(currentUserProfileProvider);
    final canManage = isAdmin && currentUser?.id != user.id;
    final isLoading = approvalState.isLoading || roleUpdateState.isLoading;

    // Kullanıcının ana rolünü belirle (super_admin > coach > member)
    final primaryRole = user.isAdmin
        ? 'super_admin'
        : user.isCoach
            ? 'coach'
            : 'member';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.pushNamed(
          RouteNames.userProfile,
          pathParameters: {'userId': user.id},
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: AppColors.neutral200,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Avatar
              RoleAvatarBadge(
                size: 44,
                name: user.fullName,
                imageUrl: user.avatarUrl,
                role: primaryRole,
              ),
              const SizedBox(width: 12),
              // Kullanıcı bilgileri
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.fullName,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Action butonları
              if (canManage) ...[
                const SizedBox(width: 8),
                isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildActionButton(
                            context: context,
                            ref: ref,
                            user: user,
                            icon: Icons.admin_panel_settings,
                            color: AppColors.primary,
                            tooltip: 'Rolü Değiştir',
                            onPressed: () => onShowRoleChangeDialog(user),
                          ),
                          const SizedBox(width: 4),
                          _buildActionButton(
                            context: context,
                            ref: ref,
                            user: user,
                            icon: Icons.block,
                            color: AppColors.error,
                            tooltip: 'Kullanıcıyı Pasifleştir',
                            onPressed: () => onDeactivateUser(user.id),
                          ),
                        ],
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingUserCard(
    BuildContext context,
    WidgetRef ref,
    UserEntity user,
    void Function(String userId) onApproveUser,
  ) {
    final approvalState = ref.watch(userApprovalProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.warningContainer,
      child: ListTile(
        leading: UserAvatar(
          size: 44,
          name: user.fullName,
          imageUrl: user.avatarUrl,
        ),
        title: Text(
          user.fullName,
          style: AppTypography.titleSmall,
        ),
        trailing: approvalState.isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : ElevatedButton.icon(
                onPressed: () => onApproveUser(user.id),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Onayla'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required WidgetRef ref,
    required UserEntity user,
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

enum _UserItemType {
  user,
  header,
  spacer,
}

/// Section header widget (const için optimize edilmiş)
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color iconColor;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: iconColor,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
