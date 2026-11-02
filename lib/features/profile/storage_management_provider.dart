import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/storage_management_service.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

final storageManagementServiceProvider = Provider<StorageManagementService>(
  (ref) => StorageManagementService(
    textbooks: ref.watch(textbookFileServiceProvider),
    tts: ref.watch(ttsServiceProvider),
  ),
);
