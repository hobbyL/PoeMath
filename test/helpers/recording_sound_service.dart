import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

/// 验证学习结算触发，不访问平台播放器。
class RecordingSoundService extends SoundService {
  RecordingSoundService() : super(SettingsRepository());

  int completions = 0;
  final effects = <SoundEffect>[];

  @override
  Future<void> playCompletion() async => completions++;

  @override
  Future<void> play(SoundEffect effect) async => effects.add(effect);
}
