import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:fluffychat/pages/sign_in/view_model/sign_in_view_model.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/sign_in_flows/check_homeserver.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/view_model_builder.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_form.dart';
import 'package:fluffychat/widgets_v2/v2_login_scaffold.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// V2 选择 homeserver 页面（登录 / 注册通用）。
///
/// 复用原有 [SignInViewModel] 业务逻辑，仅将 UI 重构为 V2 风格，
/// 优先复用 [V2AppBar] / [V2TextInput] / [V2PrimaryButton] 等公共组件。
class SignInV2 extends StatelessWidget {
  final bool signUp;
  const SignInV2({required this.signUp, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final v2 = V2Theme.of(context);
    return ViewModelBuilder(
      create: () => SignInViewModel(Matrix.of(context), signUp: signUp),
      builder: (context, viewModel, _) {
        final state = viewModel.value;
        final publicHomeservers = state.filteredPublicHomeservers;
        final selectedHomeserver = state.selectedHomeserver;
        final isLoading =
            state.loginLoading.connectionState == ConnectionState.waiting;
        final isFetching =
            state.publicHomeservers.connectionState == ConnectionState.waiting;
        return V2LoginScaffold(
          child: Scaffold(
            backgroundColor: v2.scaffoldBackground,
            body: SafeArea(
              child: Column(
                children: [
                  V2AppBar(
                    title: signUp ? l10n.createNewAccount : l10n.login,
                    onBack: isLoading
                        ? () => viewModel
                            .setLoginLoading(const AsyncSnapshot.nothing())
                        : () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          Center(
                            child: Hero(
                              tag: 'info-logo',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(120),
                                child: Image.asset(
                                  'assets/logo/mini/logo_mini.png',
                                  width: 80,
                                  height: 80,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: Text(
                              signUp
                                  ? l10n.signUpGreeting
                                  : l10n.signInGreeting,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: v2.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          V2FieldLabel(l10n.searchOrEnterHomeserverAddress),
                          const SizedBox(height: 8),
                          V2TextInput(
                            controller: viewModel.filterTextController,
                            hint: l10n.searchOrEnterHomeserverAddress,
                            readOnly: isFetching || isLoading,
                            keyboardType: TextInputType.url,
                          ),
                          if (state.publicHomeservers.error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                state.publicHomeservers.error!
                                    .toLocalizedString(context),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: isFetching
                                ? const Center(
                                    child: CircularProgressIndicator.adaptive(),
                                  )
                                : _HomeserverList(
                                    servers: publicHomeservers,
                                    selected: selectedHomeserver,
                                    onSelect: viewModel.selectHomeserver,
                                    enabled: !isLoading,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (selectedHomeserver != null &&
                      publicHomeservers.contains(selectedHomeserver))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: V2PrimaryButton(
                        label: l10n.continueText,
                        busy: isLoading,
                        onTap: isLoading
                            ? null
                            : () => connectToHomeserverFlow(
                                selectedHomeserver,
                                context,
                                viewModel.setLoginLoading,
                                signUp,
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// V2 风格的 homeserver 列表
class _HomeserverList extends StatelessWidget {
  final List<PublicHomeserverData> servers;
  final PublicHomeserverData? selected;
  final ValueChanged<PublicHomeserverData?> onSelect;
  final bool enabled;

  const _HomeserverList({
    required this.servers,
    required this.selected,
    required this.onSelect,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final v2 = V2Theme.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ListView.builder(
      itemCount: servers.length,
      itemBuilder: (context, i) {
        final server = servers[i];
        final isSelected = server == selected;
        final website = server.website;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: isSelected ? v2.accentLight : v2.cardBackground,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: enabled ? () => onSelect(server) : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RadioIndicator(selected: isSelected, enabled: enabled),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  server.name ?? 'Unknown',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: onSurface,
                                  ),
                                ),
                              ),
                              if (website != null)
                                SizedBox.square(
                                  dimension: 32,
                                  child: IconButton(
                                    tooltip: website,
                                    icon: const Icon(
                                      Icons.open_in_new_outlined,
                                      size: 16,
                                    ),
                                    onPressed: () => launchUrlString(website),
                                  ),
                                ),
                            ],
                          ),
                          if (server.features?.isNotEmpty == true ||
                              server.languages?.isNotEmpty == true) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ...?server.languages?.map(
                                  (language) => _FeatureChip(
                                    label: language,
                                    color: v2.accentLight,
                                    textColor: v2.accent,
                                  ),
                                ),
                                ...?server.features?.map(
                                  (feature) => _FeatureChip(
                                    label: feature,
                                    color: v2.accentLight,
                                    textColor: v2.accent,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (server.description != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              server.description!,
                              style: TextStyle(
                                fontSize: 12,
                                color: v2.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 圆形选中指示器
class _RadioIndicator extends StatelessWidget {
  final bool selected;
  final bool enabled;
  const _RadioIndicator({required this.selected, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final v2 = V2Theme.of(context);
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? v2.accent : v2.divider,
          width: 2,
        ),
        color: selected ? v2.accent : Colors.transparent,
      ),
      child: selected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}

/// 特性小标签
class _FeatureChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  const _FeatureChip({
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: textColor),
      ),
    );
  }
}
