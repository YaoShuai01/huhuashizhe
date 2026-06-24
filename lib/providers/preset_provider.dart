import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/local_database.dart';

final localDatabaseProvider = Provider<LocalDatabase>((ref) => LocalDatabase());
final presetsProvider =
    StateNotifierProvider<PresetsNotifier, List<Map<String, dynamic>>>((ref) {
  final db = ref.read(localDatabaseProvider);
  return PresetsNotifier(db);
});

class PresetsNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  final LocalDatabase _db;

  PresetsNotifier(this._db) : super(_db.getPresets());

  void addPreset(Map<String, dynamic> preset) {
    _db.addPreset(preset);
    state = _db.getPresets();
  }

  void updatePreset(String id, Map<String, dynamic> preset) {
    _db.updatePreset(id, preset);
    state = _db.getPresets();
  }

  void deletePreset(String id) {
    _db.deletePreset(id);
    state = _db.getPresets();
  }
}