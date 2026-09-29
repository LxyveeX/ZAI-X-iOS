import 'dart:convert';

T? asT<T>(dynamic value) {
  if (value is T) {
    return value;
  }
  return null;
}

class VersionModel {
  VersionModel({
    required this.version,
    required this.versionNum,
    required this.versionDesc,
    required this.downloadUrl,
    this.sha256 = '',
    this.size = 0,
  });

  factory VersionModel.fromJson(Map<String, dynamic> json) => VersionModel(
        version: asT<String>(json['version'])!,
        versionNum: asT<int>(json['version_num'])!,
        versionDesc: asT<String>(json['version_desc'])!,
        downloadUrl: asT<String>(json['download_url'])!,
      );

  String version;
  int versionNum;
  String versionDesc;
  String downloadUrl;

  /// 安装档的 SHA-256（GitHub Release 资产的 digest），没有则为空字串
  String sha256;

  /// 安装档大小（bytes），不知道则为 0
  int size;

  @override
  String toString() {
    return jsonEncode(this);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'version_num': versionNum,
        'version_desc': versionDesc,
        'download_url': downloadUrl,
        'sha256': sha256,
        'size': size,
      };
}
