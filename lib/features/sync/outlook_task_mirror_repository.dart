import '../../core/database/app_database.dart';
import 'outlook_task_mirror_binding.dart';

class OutlookTaskMirrorRepository {
  OutlookTaskMirrorRepository(this._db);

  static const taskMirrorBindingsSettingKey =
      'outlook_task_mirror_bindings_v1';

  final AppDatabase _db;

  Future<Map<int, OutlookTaskMirrorBinding>> loadTaskMirrorBindings() async {
    final raw = await _db.getSetting(taskMirrorBindingsSettingKey);
    return OutlookTaskMirrorBinding.decodeMap(raw);
  }

  Future<OutlookTaskMirrorBinding?> getTaskMirrorBinding(int taskId) async {
    final bindings = await loadTaskMirrorBindings();
    return bindings[taskId];
  }

  Future<void> saveTaskMirrorBinding(OutlookTaskMirrorBinding binding) async {
    final bindings = await loadTaskMirrorBindings();
    bindings[binding.localTaskId] = binding;
    await _db.setSetting(
      taskMirrorBindingsSettingKey,
      OutlookTaskMirrorBinding.encodeMap(bindings),
    );
  }

  Future<void> removeTaskMirrorBinding(int taskId) async {
    final bindings = await loadTaskMirrorBindings();
    bindings.remove(taskId);
    await _db.setSetting(
      taskMirrorBindingsSettingKey,
      OutlookTaskMirrorBinding.encodeMap(bindings),
    );
  }

  Future<void> removeTaskMirrorBindings(Iterable<int> taskIds) async {
    final ids = taskIds.toSet();
    if (ids.isEmpty) {
      return;
    }

    final bindings = await loadTaskMirrorBindings();
    bindings.removeWhere((taskId, _) => ids.contains(taskId));
    await _db.setSetting(
      taskMirrorBindingsSettingKey,
      OutlookTaskMirrorBinding.encodeMap(bindings),
    );
  }

  Future<int> countTaskMirrorBindingsForTaskList(int taskListId) async {
    final bindings = await loadTaskMirrorBindings();
    return bindings.values
        .where((binding) => binding.localTaskListId == taskListId)
        .length;
  }
}
