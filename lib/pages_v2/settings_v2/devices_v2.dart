import 'package:async/async.dart' show Result;
import 'package:collection/collection.dart' show IterableExtension;
import 'package:fluffychat/config/v2_theme.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/device_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets_v2/v2_app_bar.dart';
import 'package:fluffychat/widgets_v2/v2_confirm_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:url_launcher/url_launcher_string.dart';

/// V2 设备管理页
class DevicesV2 extends StatefulWidget {
  const DevicesV2({super.key});

  @override
  State<DevicesV2> createState() => _DevicesV2State();
}

class _DevicesV2State extends State<DevicesV2> {
  List<Device>? _devices;
  bool _editMode = false;
  bool _loading = true;
  Object? _error;

  Client get _client => Matrix.of(context).client;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await _client.getDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Device? get _thisDevice =>
      _devices?.firstWhereOrNull((d) => d.deviceId == _client.deviceID);

  List<Device> get _otherDevices {
    if (_devices == null) return const [];
    final list = List<Device>.from(_devices!)
      ..removeWhere((d) => d.deviceId == _client.deviceID)
      ..sort((a, b) => (b.lastSeenTs ?? 0).compareTo(a.lastSeenTs ?? 0));
    return list;
  }

  /// 登出所有其它设备
  Future<void> _logoutAllOtherDevices() async {
    final others = _otherDevices;
    if (others.isEmpty) return;
    final ok = await V2ConfirmDialog.show(
      context,
      title: L10n.of(context).deleteDevice,
      message: L10n.of(context).logoutAllOtherDevicesHint,
    );
    if (ok != true) return;
    if (!mounted) return;
    await _removeDevices(others);
  }

  /// 删除单个设备
  Future<void> _removeDevice(Device device) async {
    final ok = await V2ConfirmDialog.show(
      context,
      title: L10n.of(context).deleteDevice,
      message: L10n.of(context).confirmDeleteDevice(device.displayname),
    );
    if (ok != true) return;
    if (!mounted) return;
    await _removeDevices([device]);
  }

  Future<void> _removeDevices(List<Device> devices) async {
    final matrix = Matrix.of(context);
    // 优先使用服务器提供的账号管理地址（MSC2965）
    try {
      final wellKnown = await Result.capture(_client.getWellknown());
      final accountManageUrl = wellKnown.asValue?.value.additionalProperties
          .tryGetMap<String, Object?>('org.matrix.msc2965.authentication')
          ?.tryGet<String>('account');
      if (accountManageUrl != null) {
        await launchUrlString(
          accountManageUrl,
          mode: LaunchMode.inAppBrowserView,
        );
        return;
      }
    } catch (_) {}

    final deviceIds = devices.map((d) => d.deviceId).toList();
    try {
      await matrix.client.uiaRequestBackground(
        (auth) => matrix.client.deleteDevices(deviceIds, auth: auth),
      );
    } catch (_) {
      // UIA 失败由 SDK 内部提示，这里静默
    }
    if (mounted) _loadDevices();
  }

  /// 打开设备详情底部弹层
  void _showDeviceDetail(Device device) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DeviceDetailSheet(
        device: device,
        isOwn: device.deviceId == _client.deviceID,
        onRemove: () {
          Navigator.of(context).pop();
          _removeDevice(device);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: V2Theme.of(context).scaffoldBackground,
      body: Column(
        children: [
          V2AppBar(
            title: l10n.devices,
            action: _EditButton(
              label: _editMode ? l10n.done : l10n.edit,
              onTap: _editMode
                  ? () => setState(() => _editMode = false)
                  : (_otherDevices.isEmpty
                      ? null
                      : () => setState(() => _editMode = true)),
            ),
          ),
          Expanded(
            child: _buildBody(l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(L10n l10n) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2,color: V2Theme.of(context).accent,),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(_error.toString()),
          ],
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.only(top: 12, bottom: 40),
      children: [
        // 此设备
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            l10n.thisDeviceSection,
            style: TextStyle(
              fontSize: 13,
              color: V2Theme.of(context).textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (_thisDevice != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _DeviceCard(device: _thisDevice!),
          ),
        SizedBox(height: 16),
        // 注销所有其它设备
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _LogoutAllButton(onTap: _logoutAllOtherDevices),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Text(
            l10n.logoutAllOtherDevicesHint,
            style: TextStyle(
              fontSize: 12,
              color: V2Theme.of(context).textSecondary,
            ),
          ),
        ),
        // 活跃会话
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            l10n.activeSessions,
            style: TextStyle(
              fontSize: 13,
              color: V2Theme.of(context).textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (_otherDevices.isEmpty)
          Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: Text(
                l10n.noOtherDevicesFound,
                style: TextStyle(color: V2Theme.of(context).textSecondary),
              ),
            ),
          )
        else
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (var i = 0; i < _otherDevices.length; i++) ...[
                  _DeviceCard(
                    device: _otherDevices[i],
                    editMode: _editMode,
                    onTap: _editMode ? null : () => _showDeviceDetail(_otherDevices[i]),
                    onRemove: () => _removeDevice(_otherDevices[i]),
                  ),
                  if (i != _otherDevices.length - 1) SizedBox(height: 10),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// 右上角「编辑」按钮
class _EditButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _EditButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: V2Theme.of(context).cardBackground,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: enabled ? Theme.of(context).colorScheme.onSurface : V2Theme.of(context).textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 设备卡片
class _DeviceCard extends StatelessWidget {
  final Device device;
  final bool editMode;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _DeviceCard({
    required this.device,
    this.editMode = false,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2Theme.of(context).cardBackground,
      borderRadius: BorderRadius.circular(V2Theme.cardRadius),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              if (editMode) ...[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRemove,
                  child: Container(
                    width: 24,
                    height: 24,
                    margin: EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: Color(0xFFFF3B30),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.remove,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
              // 设备图标
              Icon(device.iconData, size: 30, color: Theme.of(context).colorScheme.onSurface),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.displayname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      _buildSubtitle(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: V2Theme.of(context).textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildSubtitle(BuildContext context) {
    final l10n = L10n.of(context);
    final ts = device.lastSeenTs;
    final timeStr = ts != null
        ? DateFormat('yyyy-MM-dd HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(ts),
          )
        : '-';
    return '${l10n.deviceIdLabel}:${device.deviceId}  ·  $timeStr';
  }
}

/// 注销所有其它设备按钮
class _LogoutAllButton extends StatelessWidget {
  final VoidCallback onTap;
  const _LogoutAllButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2Theme.of(context).cardBackground,
      borderRadius: BorderRadius.circular(V2Theme.cardRadius),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.logout, size: 26, color: Color(0xFFFF3B30)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  L10n.of(context).logoutAllOtherSessions,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFFF3B30),
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

/// 设备详情底部弹层
class _DeviceDetailSheet extends StatelessWidget {
  final Device device;
  final bool isOwn;
  final VoidCallback onRemove;

  const _DeviceDetailSheet({
    required this.device,
    required this.isOwn,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: V2Theme.of(context).scaffoldBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部关闭 + 设备信息
            Stack(
              children: [
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.only(top: 24, bottom: 20),
                  child: Column(
                    children: [
                      Icon(device.iconData, size: 40, color: V2Theme.of(context).accent),
                      SizedBox(height: 12),
                      Text(
                        device.displayname,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        _statusText(context),
                        style: TextStyle(
                          fontSize: 13,
                          color: V2Theme.of(context).textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: V2CircleIconButton(icon: Icons.close, onTap: () => Navigator.of(context).pop(),)
                ),
              ],
            ),
            // 设备详情
            _SectionCard(
              children: [
                _InfoRow(label: l10n.deviceIdLabel, value: device.deviceId),
                _Divider(),
                _InfoRow(label: l10n.lastLogin, value: _lastLoginText(context)),
                _Divider(),
                _InfoRow(
                  label: l10n.ipAddressLabel,
                  value: device.lastSeenIp ?? '-',
                ),
              ],
            ),
            SizedBox(height: 12),
            // 客户端
            _SectionCard(
              children: [
                _InfoRow(label: l10n.deviceNameLabel, value: device.displayname),
                _Divider(),
                _InfoRow(label: l10n.clientIdLabel, value: device.deviceId),
              ],
            ),
            SizedBox(height: 20),
            // 移除设备按钮（当前设备不可移除）
            if (!isOwn)
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: onRemove,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFFF3B30),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text(
                      l10n.removeDevice,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
            else
              SizedBox(height: bottomInset + 16),
          ],
        ),
      ),
    );
  }

  String _statusText(BuildContext context) {
    final l10n = L10n.of(context);
    final ts = device.lastSeenTs;
    if (ts == null) return '-';
    final diff = DateTime.now().millisecondsSinceEpoch - ts;
    if (diff < 5 * 60 * 1000) return l10n.online;
    return l10n.timeAgo(_relativeTime(context, diff));
  }

  String _relativeTime(BuildContext context, int diffMs) {
    final l10n = L10n.of(context);
    final minutes = diffMs ~/ 60000;
    if (minutes < 60) {
      return '$minutes ${l10n.minutesUnit}';
    }
    final hours = minutes ~/ 60;
    if (hours < 24) {
      return '$hours ${l10n.hoursUnit}';
    }
    final days = hours ~/ 24;
    return '$days ${l10n.daysUnit}';
  }

  String _lastLoginText(BuildContext context) {
    final ts = device.lastSeenTs;
    if (ts == null) return '-';
    return DateFormat('yyyy-MM-dd HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(ts),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: V2Theme.of(context).cardBackground,
        borderRadius: BorderRadius.circular(V2Theme.cardRadius),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: V2Theme.of(context).textSecondary),
          ),
          Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, thickness: 0.5, color: V2Theme.of(context).divider),
    );
  }
}
