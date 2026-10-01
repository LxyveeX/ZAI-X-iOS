/// 用户等级页的资料（account-api /v1/u_center/user_level/info）
class UserLevelInfo {
  UserLevelInfo({
    required this.level,
    required this.name,
    required this.privileges,
    required this.conditionGroups,
    required this.levels,
  });

  /// 目前等级
  final int level;

  /// 等级名称，例如 Lv4
  final String name;

  /// 目前等级的特权说明
  final List<String> privileges;

  /// 晋升条件：组与组之间完成任意一组即可升级，组内条件都要完成
  final List<List<UserLevelCondition>> conditionGroups;

  /// 全部等级（由低到高）
  final List<int> levels;

  /// 已经是最高等级
  bool get isMaxLevel => levels.isNotEmpty && level >= levels.last;

  /// 题库认证这一项（没有这个晋升条件时为 null）
  UserLevelCondition? get exam {
    for (final group in conditionGroups) {
      for (final item in group) {
        if (item.isExam) return item;
      }
    }
    return null;
  }

  factory UserLevelInfo.fromJson(Map<String, dynamic> data) {
    final detail = _map(data['currentUserLevelDetail']);
    final groups = <List<UserLevelCondition>>[];
    for (final group in _list(detail['or_conditions'])) {
      final items = [
        for (final item in _list(_map(group)['list']))
          UserLevelCondition.fromJson(_map(item)),
      ]..removeWhere((e) => e.content.isEmpty);
      if (items.isNotEmpty) groups.add(items);
    }
    final levels = [
      for (final item in _list(data['userLevelList']))
        _int(_map(item)['userLevel']),
    ]..sort();
    return UserLevelInfo(
      level: _int(detail['userLevel']),
      name: '${detail['name'] ?? ''}',
      privileges: [
        for (final item in _list(detail['privilege']))
          if ('$item'.trim().isNotEmpty) '$item'.trim(),
      ],
      conditionGroups: groups,
      levels: levels.toSet().toList(),
    );
  }
}

/// 一项晋升条件
class UserLevelCondition {
  UserLevelCondition({
    required this.content,
    required this.completed,
    required this.url,
  });

  final String content;
  final bool completed;

  /// 官方 H5 的链接（题库认证才有）
  final String url;

  /// 是不是「终极试炼之【题库认证】」
  bool get isExam => url.contains('user-auth.') || content.contains('题库');

  factory UserLevelCondition.fromJson(Map<String, dynamic> json) =>
      UserLevelCondition(
        content: '${json['con'] ?? ''}'.trim(),
        completed: json['is_completed'] == true || json['is_completed'] == 1,
        url: '${json['url'] ?? ''}'.trim(),
      );
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<dynamic> _list(dynamic value) => value is List ? value : const [];

int _int(dynamic value) => switch (value) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v) ?? 0,
      _ => 0,
    };
