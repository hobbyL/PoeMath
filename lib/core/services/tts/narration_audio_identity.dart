enum NarrationBackend { cloud, system }

/// 只公开不可逆身份，不公开服务地址、音色配置或凭据。
class NarrationAudioIdentity {
  const NarrationAudioIdentity({
    required this.cacheKey,
    required this.backend,
    required this.audioSha256,
  });

  final String cacheKey;
  final NarrationBackend backend;
  final String audioSha256;

  String get signature => '${backend.name}:$cacheKey:$audioSha256';

  Map<String, dynamic> toJson() => {
        'cacheKey': cacheKey,
        'backend': backend.name,
        'audioSha256': audioSha256,
      };

  factory NarrationAudioIdentity.fromJson(Map<String, dynamic> json) {
    final key = json['cacheKey'];
    final digest = json['audioSha256'];
    final backend = NarrationBackend.values
        .where((value) => value.name == json['backend'])
        .firstOrNull;
    final hex = RegExp(r'^[a-f0-9]{64}$');
    if (key is! String ||
        digest is! String ||
        !hex.hasMatch(key) ||
        !hex.hasMatch(digest) ||
        backend == null) {
      throw const FormatException('示范音频身份无效');
    }
    return NarrationAudioIdentity(
      cacheKey: key,
      backend: backend,
      audioSha256: digest,
    );
  }
}
