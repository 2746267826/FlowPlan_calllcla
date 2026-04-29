import '../../core/database/app_database.dart';
import 'outlook_task_list_binding.dart';

class OutlookSyncBindingsRepository {
  OutlookSyncBindingsRepository(this._db);

  static const taskListBindingsSettingKey = 'outlook_task_list_bindings_v1';

  final AppDatabase _db;

  Future<Map<int, OutlookTaskListBinding>> loadTaskListBindings() async {
    final raw = await _db.getSetting(taskListBindingsSettingKey);
    return OutlookTaskListBinding.decodeMap(raw);
  }

  Future<OutlookTaskListBinding?> getTaskListBinding(int taskListId) async {
    final bindings = await loadTaskListBindings();
    return bindings[taskListId];
  }

  Future<void> saveTaskListBinding(OutlookTaskListBinding binding) async {
    final bindings = await loadTaskListBindings();
    bindings[binding.localTaskListId] = binding;
    await _db.setSetting(
      taskListBindingsSettingKey,
      OutlookTaskListBinding.encodeMap(bindings),
    );
  }

  Future<void> removeTaskListBinding(int taskListId) async {
    final bindings = await loadTaskListBindings();
    bindings.remove(taskListId);
    await _db.setSetting(
      taskListBindingsSettingKey,
      OutlookTaskListBinding.encodeMap(bindings),
    );
  }

  Future<void> removeTaskListBindings(Iterable<int> taskListIds) async {
    final ids = taskListIds.toSet();
    if (ids.isEmpty) {
      return;
    }

    final bindings = await loadTaskListBindings();
    bindings.removeWhere((taskListId, _) => ids.contains(taskListId));
    await _db.setSetting(
      taskListBindingsSettingKey,
      OutlookTaskListBinding.encodeMap(bindings),
    );
  }
}
