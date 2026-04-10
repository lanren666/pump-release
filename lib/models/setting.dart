class Setting {
  final int? id;
  final String key; // 设置的key名
  final String desc; // 中文解释
  final String value; // 设置的值

  Setting({
    this.id,
    required this.key,
    required this.desc,
    required this.value,
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'key': key, 'desc': desc, 'value': value};
  }

  factory Setting.fromMap(Map<String, dynamic> map) {
    return Setting(
      id: map['id'],
      key: map['key'],
      desc: map['desc'],
      value: map['value'],
    );
  }

  Setting copyWith({int? id, String? key, String? desc, String? value}) {
    return Setting(
      id: id ?? this.id,
      key: key ?? this.key,
      desc: desc ?? this.desc,
      value: value ?? this.value,
    );
  }
}
