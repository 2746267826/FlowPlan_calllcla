// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $TaskItemsTable extends TaskItems
    with TableInfo<$TaskItemsTable, TaskItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _uidMeta = const VerificationMeta('uid');
  @override
  late final GeneratedColumn<String> uid = GeneratedColumn<String>(
      'uid', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dtstampMeta =
      const VerificationMeta('dtstamp');
  @override
  late final GeneratedColumn<DateTime> dtstamp = GeneratedColumn<DateTime>(
      'dtstamp', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _summaryMeta =
      const VerificationMeta('summary');
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
      'summary', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _locationMeta =
      const VerificationMeta('location');
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
      'location', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _dtstartMeta =
      const VerificationMeta('dtstart');
  @override
  late final GeneratedColumn<DateTime> dtstart = GeneratedColumn<DateTime>(
      'dtstart', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _dueMeta = const VerificationMeta('due');
  @override
  late final GeneratedColumn<DateTime> due = GeneratedColumn<DateTime>(
      'due', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _completedMeta =
      const VerificationMeta('completed');
  @override
  late final GeneratedColumn<DateTime> completed = GeneratedColumn<DateTime>(
      'completed', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _priorityMeta =
      const VerificationMeta('priority');
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
      'priority', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('NEEDS-ACTION'));
  static const VerificationMeta _percentCompleteMeta =
      const VerificationMeta('percentComplete');
  @override
  late final GeneratedColumn<int> percentComplete = GeneratedColumn<int>(
      'percent_complete', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _categoriesMeta =
      const VerificationMeta('categories');
  @override
  late final GeneratedColumn<String> categories = GeneratedColumn<String>(
      'categories', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _rruleMeta = const VerificationMeta('rrule');
  @override
  late final GeneratedColumn<String> rrule = GeneratedColumn<String>(
      'rrule', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _durationMinutesMeta =
      const VerificationMeta('durationMinutes');
  @override
  late final GeneratedColumn<int> durationMinutes = GeneratedColumn<int>(
      'duration_minutes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(60));
  static const VerificationMeta _isSplittableMeta =
      const VerificationMeta('isSplittable');
  @override
  late final GeneratedColumn<bool> isSplittable = GeneratedColumn<bool>(
      'is_splittable', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_splittable" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _priorityLocalMeta =
      const VerificationMeta('priorityLocal');
  @override
  late final GeneratedColumn<int> priorityLocal = GeneratedColumn<int>(
      'priority_local', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(2));
  static const VerificationMeta _isAutoScheduledMeta =
      const VerificationMeta('isAutoScheduled');
  @override
  late final GeneratedColumn<bool> isAutoScheduled = GeneratedColumn<bool>(
      'is_auto_scheduled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_auto_scheduled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _taskListIdMeta =
      const VerificationMeta('taskListId');
  @override
  late final GeneratedColumn<int> taskListId = GeneratedColumn<int>(
      'task_list_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
      'tag_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isLockedMeta =
      const VerificationMeta('isLocked');
  @override
  late final GeneratedColumn<bool> isLocked = GeneratedColumn<bool>(
      'is_locked', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_locked" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _reminderMinutesBeforeMeta =
      const VerificationMeta('reminderMinutesBefore');
  @override
  late final GeneratedColumn<int> reminderMinutesBefore = GeneratedColumn<int>(
      'reminder_minutes_before', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(15));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        uid,
        dtstamp,
        summary,
        description,
        location,
        dtstart,
        due,
        completed,
        priority,
        status,
        percentComplete,
        categories,
        rrule,
        durationMinutes,
        isSplittable,
        priorityLocal,
        isAutoScheduled,
        taskListId,
        tagId,
        isLocked,
        reminderMinutesBefore
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_items';
  @override
  VerificationContext validateIntegrity(Insertable<TaskItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uid')) {
      context.handle(
          _uidMeta, uid.isAcceptableOrUnknown(data['uid']!, _uidMeta));
    } else if (isInserting) {
      context.missing(_uidMeta);
    }
    if (data.containsKey('dtstamp')) {
      context.handle(_dtstampMeta,
          dtstamp.isAcceptableOrUnknown(data['dtstamp']!, _dtstampMeta));
    } else if (isInserting) {
      context.missing(_dtstampMeta);
    }
    if (data.containsKey('summary')) {
      context.handle(_summaryMeta,
          summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta));
    } else if (isInserting) {
      context.missing(_summaryMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('location')) {
      context.handle(_locationMeta,
          location.isAcceptableOrUnknown(data['location']!, _locationMeta));
    }
    if (data.containsKey('dtstart')) {
      context.handle(_dtstartMeta,
          dtstart.isAcceptableOrUnknown(data['dtstart']!, _dtstartMeta));
    }
    if (data.containsKey('due')) {
      context.handle(
          _dueMeta, due.isAcceptableOrUnknown(data['due']!, _dueMeta));
    }
    if (data.containsKey('completed')) {
      context.handle(_completedMeta,
          completed.isAcceptableOrUnknown(data['completed']!, _completedMeta));
    }
    if (data.containsKey('priority')) {
      context.handle(_priorityMeta,
          priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('percent_complete')) {
      context.handle(
          _percentCompleteMeta,
          percentComplete.isAcceptableOrUnknown(
              data['percent_complete']!, _percentCompleteMeta));
    }
    if (data.containsKey('categories')) {
      context.handle(
          _categoriesMeta,
          categories.isAcceptableOrUnknown(
              data['categories']!, _categoriesMeta));
    }
    if (data.containsKey('rrule')) {
      context.handle(
          _rruleMeta, rrule.isAcceptableOrUnknown(data['rrule']!, _rruleMeta));
    }
    if (data.containsKey('duration_minutes')) {
      context.handle(
          _durationMinutesMeta,
          durationMinutes.isAcceptableOrUnknown(
              data['duration_minutes']!, _durationMinutesMeta));
    }
    if (data.containsKey('is_splittable')) {
      context.handle(
          _isSplittableMeta,
          isSplittable.isAcceptableOrUnknown(
              data['is_splittable']!, _isSplittableMeta));
    }
    if (data.containsKey('priority_local')) {
      context.handle(
          _priorityLocalMeta,
          priorityLocal.isAcceptableOrUnknown(
              data['priority_local']!, _priorityLocalMeta));
    }
    if (data.containsKey('is_auto_scheduled')) {
      context.handle(
          _isAutoScheduledMeta,
          isAutoScheduled.isAcceptableOrUnknown(
              data['is_auto_scheduled']!, _isAutoScheduledMeta));
    }
    if (data.containsKey('task_list_id')) {
      context.handle(
          _taskListIdMeta,
          taskListId.isAcceptableOrUnknown(
              data['task_list_id']!, _taskListIdMeta));
    }
    if (data.containsKey('tag_id')) {
      context.handle(
          _tagIdMeta, tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta));
    }
    if (data.containsKey('is_locked')) {
      context.handle(_isLockedMeta,
          isLocked.isAcceptableOrUnknown(data['is_locked']!, _isLockedMeta));
    }
    if (data.containsKey('reminder_minutes_before')) {
      context.handle(
          _reminderMinutesBeforeMeta,
          reminderMinutesBefore.isAcceptableOrUnknown(
              data['reminder_minutes_before']!, _reminderMinutesBeforeMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      uid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}uid'])!,
      dtstamp: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}dtstamp'])!,
      summary: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}summary'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      location: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}location']),
      dtstart: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}dtstart']),
      due: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}due']),
      completed: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}completed']),
      priority: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}priority'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      percentComplete: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}percent_complete'])!,
      categories: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}categories'])!,
      rrule: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rrule']),
      durationMinutes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_minutes'])!,
      isSplittable: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_splittable'])!,
      priorityLocal: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}priority_local'])!,
      isAutoScheduled: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}is_auto_scheduled'])!,
      taskListId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}task_list_id']),
      tagId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tag_id']),
      isLocked: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_locked'])!,
      reminderMinutesBefore: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}reminder_minutes_before'])!,
    );
  }

  @override
  $TaskItemsTable createAlias(String alias) {
    return $TaskItemsTable(attachedDatabase, alias);
  }
}

class TaskItem extends DataClass implements Insertable<TaskItem> {
  final int id;
  final String uid;
  final DateTime dtstamp;
  final String summary;
  final String? description;
  final String? location;
  final DateTime? dtstart;
  final DateTime? due;
  final DateTime? completed;
  final int priority;
  final String status;
  final int percentComplete;
  final String categories;
  final String? rrule;
  final int durationMinutes;
  final bool isSplittable;
  final int priorityLocal;
  final bool isAutoScheduled;
  final int? taskListId;
  final String? tagId;
  final bool isLocked;
  final int reminderMinutesBefore;
  const TaskItem(
      {required this.id,
      required this.uid,
      required this.dtstamp,
      required this.summary,
      this.description,
      this.location,
      this.dtstart,
      this.due,
      this.completed,
      required this.priority,
      required this.status,
      required this.percentComplete,
      required this.categories,
      this.rrule,
      required this.durationMinutes,
      required this.isSplittable,
      required this.priorityLocal,
      required this.isAutoScheduled,
      this.taskListId,
      this.tagId,
      required this.isLocked,
      required this.reminderMinutesBefore});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['uid'] = Variable<String>(uid);
    map['dtstamp'] = Variable<DateTime>(dtstamp);
    map['summary'] = Variable<String>(summary);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    if (!nullToAbsent || dtstart != null) {
      map['dtstart'] = Variable<DateTime>(dtstart);
    }
    if (!nullToAbsent || due != null) {
      map['due'] = Variable<DateTime>(due);
    }
    if (!nullToAbsent || completed != null) {
      map['completed'] = Variable<DateTime>(completed);
    }
    map['priority'] = Variable<int>(priority);
    map['status'] = Variable<String>(status);
    map['percent_complete'] = Variable<int>(percentComplete);
    map['categories'] = Variable<String>(categories);
    if (!nullToAbsent || rrule != null) {
      map['rrule'] = Variable<String>(rrule);
    }
    map['duration_minutes'] = Variable<int>(durationMinutes);
    map['is_splittable'] = Variable<bool>(isSplittable);
    map['priority_local'] = Variable<int>(priorityLocal);
    map['is_auto_scheduled'] = Variable<bool>(isAutoScheduled);
    if (!nullToAbsent || taskListId != null) {
      map['task_list_id'] = Variable<int>(taskListId);
    }
    if (!nullToAbsent || tagId != null) {
      map['tag_id'] = Variable<String>(tagId);
    }
    map['is_locked'] = Variable<bool>(isLocked);
    map['reminder_minutes_before'] = Variable<int>(reminderMinutesBefore);
    return map;
  }

  TaskItemsCompanion toCompanion(bool nullToAbsent) {
    return TaskItemsCompanion(
      id: Value(id),
      uid: Value(uid),
      dtstamp: Value(dtstamp),
      summary: Value(summary),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      dtstart: dtstart == null && nullToAbsent
          ? const Value.absent()
          : Value(dtstart),
      due: due == null && nullToAbsent ? const Value.absent() : Value(due),
      completed: completed == null && nullToAbsent
          ? const Value.absent()
          : Value(completed),
      priority: Value(priority),
      status: Value(status),
      percentComplete: Value(percentComplete),
      categories: Value(categories),
      rrule:
          rrule == null && nullToAbsent ? const Value.absent() : Value(rrule),
      durationMinutes: Value(durationMinutes),
      isSplittable: Value(isSplittable),
      priorityLocal: Value(priorityLocal),
      isAutoScheduled: Value(isAutoScheduled),
      taskListId: taskListId == null && nullToAbsent
          ? const Value.absent()
          : Value(taskListId),
      tagId:
          tagId == null && nullToAbsent ? const Value.absent() : Value(tagId),
      isLocked: Value(isLocked),
      reminderMinutesBefore: Value(reminderMinutesBefore),
    );
  }

  factory TaskItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskItem(
      id: serializer.fromJson<int>(json['id']),
      uid: serializer.fromJson<String>(json['uid']),
      dtstamp: serializer.fromJson<DateTime>(json['dtstamp']),
      summary: serializer.fromJson<String>(json['summary']),
      description: serializer.fromJson<String?>(json['description']),
      location: serializer.fromJson<String?>(json['location']),
      dtstart: serializer.fromJson<DateTime?>(json['dtstart']),
      due: serializer.fromJson<DateTime?>(json['due']),
      completed: serializer.fromJson<DateTime?>(json['completed']),
      priority: serializer.fromJson<int>(json['priority']),
      status: serializer.fromJson<String>(json['status']),
      percentComplete: serializer.fromJson<int>(json['percentComplete']),
      categories: serializer.fromJson<String>(json['categories']),
      rrule: serializer.fromJson<String?>(json['rrule']),
      durationMinutes: serializer.fromJson<int>(json['durationMinutes']),
      isSplittable: serializer.fromJson<bool>(json['isSplittable']),
      priorityLocal: serializer.fromJson<int>(json['priorityLocal']),
      isAutoScheduled: serializer.fromJson<bool>(json['isAutoScheduled']),
      taskListId: serializer.fromJson<int?>(json['taskListId']),
      tagId: serializer.fromJson<String?>(json['tagId']),
      isLocked: serializer.fromJson<bool>(json['isLocked']),
      reminderMinutesBefore:
          serializer.fromJson<int>(json['reminderMinutesBefore']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uid': serializer.toJson<String>(uid),
      'dtstamp': serializer.toJson<DateTime>(dtstamp),
      'summary': serializer.toJson<String>(summary),
      'description': serializer.toJson<String?>(description),
      'location': serializer.toJson<String?>(location),
      'dtstart': serializer.toJson<DateTime?>(dtstart),
      'due': serializer.toJson<DateTime?>(due),
      'completed': serializer.toJson<DateTime?>(completed),
      'priority': serializer.toJson<int>(priority),
      'status': serializer.toJson<String>(status),
      'percentComplete': serializer.toJson<int>(percentComplete),
      'categories': serializer.toJson<String>(categories),
      'rrule': serializer.toJson<String?>(rrule),
      'durationMinutes': serializer.toJson<int>(durationMinutes),
      'isSplittable': serializer.toJson<bool>(isSplittable),
      'priorityLocal': serializer.toJson<int>(priorityLocal),
      'isAutoScheduled': serializer.toJson<bool>(isAutoScheduled),
      'taskListId': serializer.toJson<int?>(taskListId),
      'tagId': serializer.toJson<String?>(tagId),
      'isLocked': serializer.toJson<bool>(isLocked),
      'reminderMinutesBefore': serializer.toJson<int>(reminderMinutesBefore),
    };
  }

  TaskItem copyWith(
          {int? id,
          String? uid,
          DateTime? dtstamp,
          String? summary,
          Value<String?> description = const Value.absent(),
          Value<String?> location = const Value.absent(),
          Value<DateTime?> dtstart = const Value.absent(),
          Value<DateTime?> due = const Value.absent(),
          Value<DateTime?> completed = const Value.absent(),
          int? priority,
          String? status,
          int? percentComplete,
          String? categories,
          Value<String?> rrule = const Value.absent(),
          int? durationMinutes,
          bool? isSplittable,
          int? priorityLocal,
          bool? isAutoScheduled,
          Value<int?> taskListId = const Value.absent(),
          Value<String?> tagId = const Value.absent(),
          bool? isLocked,
          int? reminderMinutesBefore}) =>
      TaskItem(
        id: id ?? this.id,
        uid: uid ?? this.uid,
        dtstamp: dtstamp ?? this.dtstamp,
        summary: summary ?? this.summary,
        description: description.present ? description.value : this.description,
        location: location.present ? location.value : this.location,
        dtstart: dtstart.present ? dtstart.value : this.dtstart,
        due: due.present ? due.value : this.due,
        completed: completed.present ? completed.value : this.completed,
        priority: priority ?? this.priority,
        status: status ?? this.status,
        percentComplete: percentComplete ?? this.percentComplete,
        categories: categories ?? this.categories,
        rrule: rrule.present ? rrule.value : this.rrule,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        isSplittable: isSplittable ?? this.isSplittable,
        priorityLocal: priorityLocal ?? this.priorityLocal,
        isAutoScheduled: isAutoScheduled ?? this.isAutoScheduled,
        taskListId: taskListId.present ? taskListId.value : this.taskListId,
        tagId: tagId.present ? tagId.value : this.tagId,
        isLocked: isLocked ?? this.isLocked,
        reminderMinutesBefore:
            reminderMinutesBefore ?? this.reminderMinutesBefore,
      );
  TaskItem copyWithCompanion(TaskItemsCompanion data) {
    return TaskItem(
      id: data.id.present ? data.id.value : this.id,
      uid: data.uid.present ? data.uid.value : this.uid,
      dtstamp: data.dtstamp.present ? data.dtstamp.value : this.dtstamp,
      summary: data.summary.present ? data.summary.value : this.summary,
      description:
          data.description.present ? data.description.value : this.description,
      location: data.location.present ? data.location.value : this.location,
      dtstart: data.dtstart.present ? data.dtstart.value : this.dtstart,
      due: data.due.present ? data.due.value : this.due,
      completed: data.completed.present ? data.completed.value : this.completed,
      priority: data.priority.present ? data.priority.value : this.priority,
      status: data.status.present ? data.status.value : this.status,
      percentComplete: data.percentComplete.present
          ? data.percentComplete.value
          : this.percentComplete,
      categories:
          data.categories.present ? data.categories.value : this.categories,
      rrule: data.rrule.present ? data.rrule.value : this.rrule,
      durationMinutes: data.durationMinutes.present
          ? data.durationMinutes.value
          : this.durationMinutes,
      isSplittable: data.isSplittable.present
          ? data.isSplittable.value
          : this.isSplittable,
      priorityLocal: data.priorityLocal.present
          ? data.priorityLocal.value
          : this.priorityLocal,
      isAutoScheduled: data.isAutoScheduled.present
          ? data.isAutoScheduled.value
          : this.isAutoScheduled,
      taskListId:
          data.taskListId.present ? data.taskListId.value : this.taskListId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      isLocked: data.isLocked.present ? data.isLocked.value : this.isLocked,
      reminderMinutesBefore: data.reminderMinutesBefore.present
          ? data.reminderMinutesBefore.value
          : this.reminderMinutesBefore,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskItem(')
          ..write('id: $id, ')
          ..write('uid: $uid, ')
          ..write('dtstamp: $dtstamp, ')
          ..write('summary: $summary, ')
          ..write('description: $description, ')
          ..write('location: $location, ')
          ..write('dtstart: $dtstart, ')
          ..write('due: $due, ')
          ..write('completed: $completed, ')
          ..write('priority: $priority, ')
          ..write('status: $status, ')
          ..write('percentComplete: $percentComplete, ')
          ..write('categories: $categories, ')
          ..write('rrule: $rrule, ')
          ..write('durationMinutes: $durationMinutes, ')
          ..write('isSplittable: $isSplittable, ')
          ..write('priorityLocal: $priorityLocal, ')
          ..write('isAutoScheduled: $isAutoScheduled, ')
          ..write('taskListId: $taskListId, ')
          ..write('tagId: $tagId, ')
          ..write('isLocked: $isLocked, ')
          ..write('reminderMinutesBefore: $reminderMinutesBefore')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        uid,
        dtstamp,
        summary,
        description,
        location,
        dtstart,
        due,
        completed,
        priority,
        status,
        percentComplete,
        categories,
        rrule,
        durationMinutes,
        isSplittable,
        priorityLocal,
        isAutoScheduled,
        taskListId,
        tagId,
        isLocked,
        reminderMinutesBefore
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskItem &&
          other.id == this.id &&
          other.uid == this.uid &&
          other.dtstamp == this.dtstamp &&
          other.summary == this.summary &&
          other.description == this.description &&
          other.location == this.location &&
          other.dtstart == this.dtstart &&
          other.due == this.due &&
          other.completed == this.completed &&
          other.priority == this.priority &&
          other.status == this.status &&
          other.percentComplete == this.percentComplete &&
          other.categories == this.categories &&
          other.rrule == this.rrule &&
          other.durationMinutes == this.durationMinutes &&
          other.isSplittable == this.isSplittable &&
          other.priorityLocal == this.priorityLocal &&
          other.isAutoScheduled == this.isAutoScheduled &&
          other.taskListId == this.taskListId &&
          other.tagId == this.tagId &&
          other.isLocked == this.isLocked &&
          other.reminderMinutesBefore == this.reminderMinutesBefore);
}

class TaskItemsCompanion extends UpdateCompanion<TaskItem> {
  final Value<int> id;
  final Value<String> uid;
  final Value<DateTime> dtstamp;
  final Value<String> summary;
  final Value<String?> description;
  final Value<String?> location;
  final Value<DateTime?> dtstart;
  final Value<DateTime?> due;
  final Value<DateTime?> completed;
  final Value<int> priority;
  final Value<String> status;
  final Value<int> percentComplete;
  final Value<String> categories;
  final Value<String?> rrule;
  final Value<int> durationMinutes;
  final Value<bool> isSplittable;
  final Value<int> priorityLocal;
  final Value<bool> isAutoScheduled;
  final Value<int?> taskListId;
  final Value<String?> tagId;
  final Value<bool> isLocked;
  final Value<int> reminderMinutesBefore;
  const TaskItemsCompanion({
    this.id = const Value.absent(),
    this.uid = const Value.absent(),
    this.dtstamp = const Value.absent(),
    this.summary = const Value.absent(),
    this.description = const Value.absent(),
    this.location = const Value.absent(),
    this.dtstart = const Value.absent(),
    this.due = const Value.absent(),
    this.completed = const Value.absent(),
    this.priority = const Value.absent(),
    this.status = const Value.absent(),
    this.percentComplete = const Value.absent(),
    this.categories = const Value.absent(),
    this.rrule = const Value.absent(),
    this.durationMinutes = const Value.absent(),
    this.isSplittable = const Value.absent(),
    this.priorityLocal = const Value.absent(),
    this.isAutoScheduled = const Value.absent(),
    this.taskListId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.isLocked = const Value.absent(),
    this.reminderMinutesBefore = const Value.absent(),
  });
  TaskItemsCompanion.insert({
    this.id = const Value.absent(),
    required String uid,
    required DateTime dtstamp,
    required String summary,
    this.description = const Value.absent(),
    this.location = const Value.absent(),
    this.dtstart = const Value.absent(),
    this.due = const Value.absent(),
    this.completed = const Value.absent(),
    this.priority = const Value.absent(),
    this.status = const Value.absent(),
    this.percentComplete = const Value.absent(),
    this.categories = const Value.absent(),
    this.rrule = const Value.absent(),
    this.durationMinutes = const Value.absent(),
    this.isSplittable = const Value.absent(),
    this.priorityLocal = const Value.absent(),
    this.isAutoScheduled = const Value.absent(),
    this.taskListId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.isLocked = const Value.absent(),
    this.reminderMinutesBefore = const Value.absent(),
  })  : uid = Value(uid),
        dtstamp = Value(dtstamp),
        summary = Value(summary);
  static Insertable<TaskItem> custom({
    Expression<int>? id,
    Expression<String>? uid,
    Expression<DateTime>? dtstamp,
    Expression<String>? summary,
    Expression<String>? description,
    Expression<String>? location,
    Expression<DateTime>? dtstart,
    Expression<DateTime>? due,
    Expression<DateTime>? completed,
    Expression<int>? priority,
    Expression<String>? status,
    Expression<int>? percentComplete,
    Expression<String>? categories,
    Expression<String>? rrule,
    Expression<int>? durationMinutes,
    Expression<bool>? isSplittable,
    Expression<int>? priorityLocal,
    Expression<bool>? isAutoScheduled,
    Expression<int>? taskListId,
    Expression<String>? tagId,
    Expression<bool>? isLocked,
    Expression<int>? reminderMinutesBefore,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uid != null) 'uid': uid,
      if (dtstamp != null) 'dtstamp': dtstamp,
      if (summary != null) 'summary': summary,
      if (description != null) 'description': description,
      if (location != null) 'location': location,
      if (dtstart != null) 'dtstart': dtstart,
      if (due != null) 'due': due,
      if (completed != null) 'completed': completed,
      if (priority != null) 'priority': priority,
      if (status != null) 'status': status,
      if (percentComplete != null) 'percent_complete': percentComplete,
      if (categories != null) 'categories': categories,
      if (rrule != null) 'rrule': rrule,
      if (durationMinutes != null) 'duration_minutes': durationMinutes,
      if (isSplittable != null) 'is_splittable': isSplittable,
      if (priorityLocal != null) 'priority_local': priorityLocal,
      if (isAutoScheduled != null) 'is_auto_scheduled': isAutoScheduled,
      if (taskListId != null) 'task_list_id': taskListId,
      if (tagId != null) 'tag_id': tagId,
      if (isLocked != null) 'is_locked': isLocked,
      if (reminderMinutesBefore != null)
        'reminder_minutes_before': reminderMinutesBefore,
    });
  }

  TaskItemsCompanion copyWith(
      {Value<int>? id,
      Value<String>? uid,
      Value<DateTime>? dtstamp,
      Value<String>? summary,
      Value<String?>? description,
      Value<String?>? location,
      Value<DateTime?>? dtstart,
      Value<DateTime?>? due,
      Value<DateTime?>? completed,
      Value<int>? priority,
      Value<String>? status,
      Value<int>? percentComplete,
      Value<String>? categories,
      Value<String?>? rrule,
      Value<int>? durationMinutes,
      Value<bool>? isSplittable,
      Value<int>? priorityLocal,
      Value<bool>? isAutoScheduled,
      Value<int?>? taskListId,
      Value<String?>? tagId,
      Value<bool>? isLocked,
      Value<int>? reminderMinutesBefore}) {
    return TaskItemsCompanion(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      dtstamp: dtstamp ?? this.dtstamp,
      summary: summary ?? this.summary,
      description: description ?? this.description,
      location: location ?? this.location,
      dtstart: dtstart ?? this.dtstart,
      due: due ?? this.due,
      completed: completed ?? this.completed,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      percentComplete: percentComplete ?? this.percentComplete,
      categories: categories ?? this.categories,
      rrule: rrule ?? this.rrule,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      isSplittable: isSplittable ?? this.isSplittable,
      priorityLocal: priorityLocal ?? this.priorityLocal,
      isAutoScheduled: isAutoScheduled ?? this.isAutoScheduled,
      taskListId: taskListId ?? this.taskListId,
      tagId: tagId ?? this.tagId,
      isLocked: isLocked ?? this.isLocked,
      reminderMinutesBefore:
          reminderMinutesBefore ?? this.reminderMinutesBefore,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uid.present) {
      map['uid'] = Variable<String>(uid.value);
    }
    if (dtstamp.present) {
      map['dtstamp'] = Variable<DateTime>(dtstamp.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (dtstart.present) {
      map['dtstart'] = Variable<DateTime>(dtstart.value);
    }
    if (due.present) {
      map['due'] = Variable<DateTime>(due.value);
    }
    if (completed.present) {
      map['completed'] = Variable<DateTime>(completed.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (percentComplete.present) {
      map['percent_complete'] = Variable<int>(percentComplete.value);
    }
    if (categories.present) {
      map['categories'] = Variable<String>(categories.value);
    }
    if (rrule.present) {
      map['rrule'] = Variable<String>(rrule.value);
    }
    if (durationMinutes.present) {
      map['duration_minutes'] = Variable<int>(durationMinutes.value);
    }
    if (isSplittable.present) {
      map['is_splittable'] = Variable<bool>(isSplittable.value);
    }
    if (priorityLocal.present) {
      map['priority_local'] = Variable<int>(priorityLocal.value);
    }
    if (isAutoScheduled.present) {
      map['is_auto_scheduled'] = Variable<bool>(isAutoScheduled.value);
    }
    if (taskListId.present) {
      map['task_list_id'] = Variable<int>(taskListId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (isLocked.present) {
      map['is_locked'] = Variable<bool>(isLocked.value);
    }
    if (reminderMinutesBefore.present) {
      map['reminder_minutes_before'] =
          Variable<int>(reminderMinutesBefore.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskItemsCompanion(')
          ..write('id: $id, ')
          ..write('uid: $uid, ')
          ..write('dtstamp: $dtstamp, ')
          ..write('summary: $summary, ')
          ..write('description: $description, ')
          ..write('location: $location, ')
          ..write('dtstart: $dtstart, ')
          ..write('due: $due, ')
          ..write('completed: $completed, ')
          ..write('priority: $priority, ')
          ..write('status: $status, ')
          ..write('percentComplete: $percentComplete, ')
          ..write('categories: $categories, ')
          ..write('rrule: $rrule, ')
          ..write('durationMinutes: $durationMinutes, ')
          ..write('isSplittable: $isSplittable, ')
          ..write('priorityLocal: $priorityLocal, ')
          ..write('isAutoScheduled: $isAutoScheduled, ')
          ..write('taskListId: $taskListId, ')
          ..write('tagId: $tagId, ')
          ..write('isLocked: $isLocked, ')
          ..write('reminderMinutesBefore: $reminderMinutesBefore')
          ..write(')'))
        .toString();
  }
}

class $CalendarEventsTable extends CalendarEvents
    with TableInfo<$CalendarEventsTable, CalendarEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CalendarEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _uidMeta = const VerificationMeta('uid');
  @override
  late final GeneratedColumn<String> uid = GeneratedColumn<String>(
      'uid', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dtstampMeta =
      const VerificationMeta('dtstamp');
  @override
  late final GeneratedColumn<DateTime> dtstamp = GeneratedColumn<DateTime>(
      'dtstamp', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _summaryMeta =
      const VerificationMeta('summary');
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
      'summary', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _locationMeta =
      const VerificationMeta('location');
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
      'location', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _dtstartMeta =
      const VerificationMeta('dtstart');
  @override
  late final GeneratedColumn<DateTime> dtstart = GeneratedColumn<DateTime>(
      'dtstart', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _dtendMeta = const VerificationMeta('dtend');
  @override
  late final GeneratedColumn<DateTime> dtend = GeneratedColumn<DateTime>(
      'dtend', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _rruleMeta = const VerificationMeta('rrule');
  @override
  late final GeneratedColumn<String> rrule = GeneratedColumn<String>(
      'rrule', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('CONFIRMED'));
  static const VerificationMeta _transpMeta = const VerificationMeta('transp');
  @override
  late final GeneratedColumn<String> transp = GeneratedColumn<String>(
      'transp', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('OPAQUE'));
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
      'source', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('local'));
  static const VerificationMeta _eventCalendarIdMeta =
      const VerificationMeta('eventCalendarId');
  @override
  late final GeneratedColumn<int> eventCalendarId = GeneratedColumn<int>(
      'event_calendar_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _colorHexMeta =
      const VerificationMeta('colorHex');
  @override
  late final GeneratedColumn<String> colorHex = GeneratedColumn<String>(
      'color_hex', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('#6B5EE4'));
  static const VerificationMeta _isBlockMeta =
      const VerificationMeta('isBlock');
  @override
  late final GeneratedColumn<bool> isBlock = GeneratedColumn<bool>(
      'is_block', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_block" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        uid,
        dtstamp,
        summary,
        description,
        location,
        dtstart,
        dtend,
        rrule,
        status,
        transp,
        source,
        eventCalendarId,
        colorHex,
        isBlock
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'calendar_events';
  @override
  VerificationContext validateIntegrity(Insertable<CalendarEvent> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uid')) {
      context.handle(
          _uidMeta, uid.isAcceptableOrUnknown(data['uid']!, _uidMeta));
    } else if (isInserting) {
      context.missing(_uidMeta);
    }
    if (data.containsKey('dtstamp')) {
      context.handle(_dtstampMeta,
          dtstamp.isAcceptableOrUnknown(data['dtstamp']!, _dtstampMeta));
    } else if (isInserting) {
      context.missing(_dtstampMeta);
    }
    if (data.containsKey('summary')) {
      context.handle(_summaryMeta,
          summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta));
    } else if (isInserting) {
      context.missing(_summaryMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('location')) {
      context.handle(_locationMeta,
          location.isAcceptableOrUnknown(data['location']!, _locationMeta));
    }
    if (data.containsKey('dtstart')) {
      context.handle(_dtstartMeta,
          dtstart.isAcceptableOrUnknown(data['dtstart']!, _dtstartMeta));
    } else if (isInserting) {
      context.missing(_dtstartMeta);
    }
    if (data.containsKey('dtend')) {
      context.handle(
          _dtendMeta, dtend.isAcceptableOrUnknown(data['dtend']!, _dtendMeta));
    }
    if (data.containsKey('rrule')) {
      context.handle(
          _rruleMeta, rrule.isAcceptableOrUnknown(data['rrule']!, _rruleMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('transp')) {
      context.handle(_transpMeta,
          transp.isAcceptableOrUnknown(data['transp']!, _transpMeta));
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    }
    if (data.containsKey('event_calendar_id')) {
      context.handle(
          _eventCalendarIdMeta,
          eventCalendarId.isAcceptableOrUnknown(
              data['event_calendar_id']!, _eventCalendarIdMeta));
    }
    if (data.containsKey('color_hex')) {
      context.handle(_colorHexMeta,
          colorHex.isAcceptableOrUnknown(data['color_hex']!, _colorHexMeta));
    }
    if (data.containsKey('is_block')) {
      context.handle(_isBlockMeta,
          isBlock.isAcceptableOrUnknown(data['is_block']!, _isBlockMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CalendarEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CalendarEvent(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      uid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}uid'])!,
      dtstamp: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}dtstamp'])!,
      summary: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}summary'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      location: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}location']),
      dtstart: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}dtstart'])!,
      dtend: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}dtend']),
      rrule: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rrule']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      transp: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}transp'])!,
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source'])!,
      eventCalendarId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}event_calendar_id']),
      colorHex: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}color_hex'])!,
      isBlock: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_block'])!,
    );
  }

  @override
  $CalendarEventsTable createAlias(String alias) {
    return $CalendarEventsTable(attachedDatabase, alias);
  }
}

class CalendarEvent extends DataClass implements Insertable<CalendarEvent> {
  final int id;
  final String uid;
  final DateTime dtstamp;
  final String summary;
  final String? description;
  final String? location;
  final DateTime dtstart;
  final DateTime? dtend;
  final String? rrule;
  final String status;
  final String transp;
  final String source;
  final int? eventCalendarId;
  final String colorHex;
  final bool isBlock;
  const CalendarEvent(
      {required this.id,
      required this.uid,
      required this.dtstamp,
      required this.summary,
      this.description,
      this.location,
      required this.dtstart,
      this.dtend,
      this.rrule,
      required this.status,
      required this.transp,
      required this.source,
      this.eventCalendarId,
      required this.colorHex,
      required this.isBlock});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['uid'] = Variable<String>(uid);
    map['dtstamp'] = Variable<DateTime>(dtstamp);
    map['summary'] = Variable<String>(summary);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    map['dtstart'] = Variable<DateTime>(dtstart);
    if (!nullToAbsent || dtend != null) {
      map['dtend'] = Variable<DateTime>(dtend);
    }
    if (!nullToAbsent || rrule != null) {
      map['rrule'] = Variable<String>(rrule);
    }
    map['status'] = Variable<String>(status);
    map['transp'] = Variable<String>(transp);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || eventCalendarId != null) {
      map['event_calendar_id'] = Variable<int>(eventCalendarId);
    }
    map['color_hex'] = Variable<String>(colorHex);
    map['is_block'] = Variable<bool>(isBlock);
    return map;
  }

  CalendarEventsCompanion toCompanion(bool nullToAbsent) {
    return CalendarEventsCompanion(
      id: Value(id),
      uid: Value(uid),
      dtstamp: Value(dtstamp),
      summary: Value(summary),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      dtstart: Value(dtstart),
      dtend:
          dtend == null && nullToAbsent ? const Value.absent() : Value(dtend),
      rrule:
          rrule == null && nullToAbsent ? const Value.absent() : Value(rrule),
      status: Value(status),
      transp: Value(transp),
      source: Value(source),
      eventCalendarId: eventCalendarId == null && nullToAbsent
          ? const Value.absent()
          : Value(eventCalendarId),
      colorHex: Value(colorHex),
      isBlock: Value(isBlock),
    );
  }

  factory CalendarEvent.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CalendarEvent(
      id: serializer.fromJson<int>(json['id']),
      uid: serializer.fromJson<String>(json['uid']),
      dtstamp: serializer.fromJson<DateTime>(json['dtstamp']),
      summary: serializer.fromJson<String>(json['summary']),
      description: serializer.fromJson<String?>(json['description']),
      location: serializer.fromJson<String?>(json['location']),
      dtstart: serializer.fromJson<DateTime>(json['dtstart']),
      dtend: serializer.fromJson<DateTime?>(json['dtend']),
      rrule: serializer.fromJson<String?>(json['rrule']),
      status: serializer.fromJson<String>(json['status']),
      transp: serializer.fromJson<String>(json['transp']),
      source: serializer.fromJson<String>(json['source']),
      eventCalendarId: serializer.fromJson<int?>(json['eventCalendarId']),
      colorHex: serializer.fromJson<String>(json['colorHex']),
      isBlock: serializer.fromJson<bool>(json['isBlock']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uid': serializer.toJson<String>(uid),
      'dtstamp': serializer.toJson<DateTime>(dtstamp),
      'summary': serializer.toJson<String>(summary),
      'description': serializer.toJson<String?>(description),
      'location': serializer.toJson<String?>(location),
      'dtstart': serializer.toJson<DateTime>(dtstart),
      'dtend': serializer.toJson<DateTime?>(dtend),
      'rrule': serializer.toJson<String?>(rrule),
      'status': serializer.toJson<String>(status),
      'transp': serializer.toJson<String>(transp),
      'source': serializer.toJson<String>(source),
      'eventCalendarId': serializer.toJson<int?>(eventCalendarId),
      'colorHex': serializer.toJson<String>(colorHex),
      'isBlock': serializer.toJson<bool>(isBlock),
    };
  }

  CalendarEvent copyWith(
          {int? id,
          String? uid,
          DateTime? dtstamp,
          String? summary,
          Value<String?> description = const Value.absent(),
          Value<String?> location = const Value.absent(),
          DateTime? dtstart,
          Value<DateTime?> dtend = const Value.absent(),
          Value<String?> rrule = const Value.absent(),
          String? status,
          String? transp,
          String? source,
          Value<int?> eventCalendarId = const Value.absent(),
          String? colorHex,
          bool? isBlock}) =>
      CalendarEvent(
        id: id ?? this.id,
        uid: uid ?? this.uid,
        dtstamp: dtstamp ?? this.dtstamp,
        summary: summary ?? this.summary,
        description: description.present ? description.value : this.description,
        location: location.present ? location.value : this.location,
        dtstart: dtstart ?? this.dtstart,
        dtend: dtend.present ? dtend.value : this.dtend,
        rrule: rrule.present ? rrule.value : this.rrule,
        status: status ?? this.status,
        transp: transp ?? this.transp,
        source: source ?? this.source,
        eventCalendarId: eventCalendarId.present
            ? eventCalendarId.value
            : this.eventCalendarId,
        colorHex: colorHex ?? this.colorHex,
        isBlock: isBlock ?? this.isBlock,
      );
  CalendarEvent copyWithCompanion(CalendarEventsCompanion data) {
    return CalendarEvent(
      id: data.id.present ? data.id.value : this.id,
      uid: data.uid.present ? data.uid.value : this.uid,
      dtstamp: data.dtstamp.present ? data.dtstamp.value : this.dtstamp,
      summary: data.summary.present ? data.summary.value : this.summary,
      description:
          data.description.present ? data.description.value : this.description,
      location: data.location.present ? data.location.value : this.location,
      dtstart: data.dtstart.present ? data.dtstart.value : this.dtstart,
      dtend: data.dtend.present ? data.dtend.value : this.dtend,
      rrule: data.rrule.present ? data.rrule.value : this.rrule,
      status: data.status.present ? data.status.value : this.status,
      transp: data.transp.present ? data.transp.value : this.transp,
      source: data.source.present ? data.source.value : this.source,
      eventCalendarId: data.eventCalendarId.present
          ? data.eventCalendarId.value
          : this.eventCalendarId,
      colorHex: data.colorHex.present ? data.colorHex.value : this.colorHex,
      isBlock: data.isBlock.present ? data.isBlock.value : this.isBlock,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CalendarEvent(')
          ..write('id: $id, ')
          ..write('uid: $uid, ')
          ..write('dtstamp: $dtstamp, ')
          ..write('summary: $summary, ')
          ..write('description: $description, ')
          ..write('location: $location, ')
          ..write('dtstart: $dtstart, ')
          ..write('dtend: $dtend, ')
          ..write('rrule: $rrule, ')
          ..write('status: $status, ')
          ..write('transp: $transp, ')
          ..write('source: $source, ')
          ..write('eventCalendarId: $eventCalendarId, ')
          ..write('colorHex: $colorHex, ')
          ..write('isBlock: $isBlock')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      uid,
      dtstamp,
      summary,
      description,
      location,
      dtstart,
      dtend,
      rrule,
      status,
      transp,
      source,
      eventCalendarId,
      colorHex,
      isBlock);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CalendarEvent &&
          other.id == this.id &&
          other.uid == this.uid &&
          other.dtstamp == this.dtstamp &&
          other.summary == this.summary &&
          other.description == this.description &&
          other.location == this.location &&
          other.dtstart == this.dtstart &&
          other.dtend == this.dtend &&
          other.rrule == this.rrule &&
          other.status == this.status &&
          other.transp == this.transp &&
          other.source == this.source &&
          other.eventCalendarId == this.eventCalendarId &&
          other.colorHex == this.colorHex &&
          other.isBlock == this.isBlock);
}

class CalendarEventsCompanion extends UpdateCompanion<CalendarEvent> {
  final Value<int> id;
  final Value<String> uid;
  final Value<DateTime> dtstamp;
  final Value<String> summary;
  final Value<String?> description;
  final Value<String?> location;
  final Value<DateTime> dtstart;
  final Value<DateTime?> dtend;
  final Value<String?> rrule;
  final Value<String> status;
  final Value<String> transp;
  final Value<String> source;
  final Value<int?> eventCalendarId;
  final Value<String> colorHex;
  final Value<bool> isBlock;
  const CalendarEventsCompanion({
    this.id = const Value.absent(),
    this.uid = const Value.absent(),
    this.dtstamp = const Value.absent(),
    this.summary = const Value.absent(),
    this.description = const Value.absent(),
    this.location = const Value.absent(),
    this.dtstart = const Value.absent(),
    this.dtend = const Value.absent(),
    this.rrule = const Value.absent(),
    this.status = const Value.absent(),
    this.transp = const Value.absent(),
    this.source = const Value.absent(),
    this.eventCalendarId = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.isBlock = const Value.absent(),
  });
  CalendarEventsCompanion.insert({
    this.id = const Value.absent(),
    required String uid,
    required DateTime dtstamp,
    required String summary,
    this.description = const Value.absent(),
    this.location = const Value.absent(),
    required DateTime dtstart,
    this.dtend = const Value.absent(),
    this.rrule = const Value.absent(),
    this.status = const Value.absent(),
    this.transp = const Value.absent(),
    this.source = const Value.absent(),
    this.eventCalendarId = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.isBlock = const Value.absent(),
  })  : uid = Value(uid),
        dtstamp = Value(dtstamp),
        summary = Value(summary),
        dtstart = Value(dtstart);
  static Insertable<CalendarEvent> custom({
    Expression<int>? id,
    Expression<String>? uid,
    Expression<DateTime>? dtstamp,
    Expression<String>? summary,
    Expression<String>? description,
    Expression<String>? location,
    Expression<DateTime>? dtstart,
    Expression<DateTime>? dtend,
    Expression<String>? rrule,
    Expression<String>? status,
    Expression<String>? transp,
    Expression<String>? source,
    Expression<int>? eventCalendarId,
    Expression<String>? colorHex,
    Expression<bool>? isBlock,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uid != null) 'uid': uid,
      if (dtstamp != null) 'dtstamp': dtstamp,
      if (summary != null) 'summary': summary,
      if (description != null) 'description': description,
      if (location != null) 'location': location,
      if (dtstart != null) 'dtstart': dtstart,
      if (dtend != null) 'dtend': dtend,
      if (rrule != null) 'rrule': rrule,
      if (status != null) 'status': status,
      if (transp != null) 'transp': transp,
      if (source != null) 'source': source,
      if (eventCalendarId != null) 'event_calendar_id': eventCalendarId,
      if (colorHex != null) 'color_hex': colorHex,
      if (isBlock != null) 'is_block': isBlock,
    });
  }

  CalendarEventsCompanion copyWith(
      {Value<int>? id,
      Value<String>? uid,
      Value<DateTime>? dtstamp,
      Value<String>? summary,
      Value<String?>? description,
      Value<String?>? location,
      Value<DateTime>? dtstart,
      Value<DateTime?>? dtend,
      Value<String?>? rrule,
      Value<String>? status,
      Value<String>? transp,
      Value<String>? source,
      Value<int?>? eventCalendarId,
      Value<String>? colorHex,
      Value<bool>? isBlock}) {
    return CalendarEventsCompanion(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      dtstamp: dtstamp ?? this.dtstamp,
      summary: summary ?? this.summary,
      description: description ?? this.description,
      location: location ?? this.location,
      dtstart: dtstart ?? this.dtstart,
      dtend: dtend ?? this.dtend,
      rrule: rrule ?? this.rrule,
      status: status ?? this.status,
      transp: transp ?? this.transp,
      source: source ?? this.source,
      eventCalendarId: eventCalendarId ?? this.eventCalendarId,
      colorHex: colorHex ?? this.colorHex,
      isBlock: isBlock ?? this.isBlock,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uid.present) {
      map['uid'] = Variable<String>(uid.value);
    }
    if (dtstamp.present) {
      map['dtstamp'] = Variable<DateTime>(dtstamp.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (dtstart.present) {
      map['dtstart'] = Variable<DateTime>(dtstart.value);
    }
    if (dtend.present) {
      map['dtend'] = Variable<DateTime>(dtend.value);
    }
    if (rrule.present) {
      map['rrule'] = Variable<String>(rrule.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (transp.present) {
      map['transp'] = Variable<String>(transp.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (eventCalendarId.present) {
      map['event_calendar_id'] = Variable<int>(eventCalendarId.value);
    }
    if (colorHex.present) {
      map['color_hex'] = Variable<String>(colorHex.value);
    }
    if (isBlock.present) {
      map['is_block'] = Variable<bool>(isBlock.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CalendarEventsCompanion(')
          ..write('id: $id, ')
          ..write('uid: $uid, ')
          ..write('dtstamp: $dtstamp, ')
          ..write('summary: $summary, ')
          ..write('description: $description, ')
          ..write('location: $location, ')
          ..write('dtstart: $dtstart, ')
          ..write('dtend: $dtend, ')
          ..write('rrule: $rrule, ')
          ..write('status: $status, ')
          ..write('transp: $transp, ')
          ..write('source: $source, ')
          ..write('eventCalendarId: $eventCalendarId, ')
          ..write('colorHex: $colorHex, ')
          ..write('isBlock: $isBlock')
          ..write(')'))
        .toString();
  }
}

class $TimeBlocksTable extends TimeBlocks
    with TableInfo<$TimeBlocksTable, TimeBlock> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TimeBlocksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _startHourMeta =
      const VerificationMeta('startHour');
  @override
  late final GeneratedColumn<int> startHour = GeneratedColumn<int>(
      'start_hour', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _startMinuteMeta =
      const VerificationMeta('startMinute');
  @override
  late final GeneratedColumn<int> startMinute = GeneratedColumn<int>(
      'start_minute', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _endHourMeta =
      const VerificationMeta('endHour');
  @override
  late final GeneratedColumn<int> endHour = GeneratedColumn<int>(
      'end_hour', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _endMinuteMeta =
      const VerificationMeta('endMinute');
  @override
  late final GeneratedColumn<int> endMinute = GeneratedColumn<int>(
      'end_minute', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _weekdaysMeta =
      const VerificationMeta('weekdays');
  @override
  late final GeneratedColumn<String> weekdays = GeneratedColumn<String>(
      'weekdays', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[1,2,3,4,5,6,7]'));
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _colorHexMeta =
      const VerificationMeta('colorHex');
  @override
  late final GeneratedColumn<String> colorHex = GeneratedColumn<String>(
      'color_hex', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('#E0E0E0'));
  static const VerificationMeta _emojiMeta = const VerificationMeta('emoji');
  @override
  late final GeneratedColumn<String> emoji = GeneratedColumn<String>(
      'emoji', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('🔒'));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        startHour,
        startMinute,
        endHour,
        endMinute,
        weekdays,
        isActive,
        colorHex,
        emoji
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'time_blocks';
  @override
  VerificationContext validateIntegrity(Insertable<TimeBlock> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('start_hour')) {
      context.handle(_startHourMeta,
          startHour.isAcceptableOrUnknown(data['start_hour']!, _startHourMeta));
    } else if (isInserting) {
      context.missing(_startHourMeta);
    }
    if (data.containsKey('start_minute')) {
      context.handle(
          _startMinuteMeta,
          startMinute.isAcceptableOrUnknown(
              data['start_minute']!, _startMinuteMeta));
    }
    if (data.containsKey('end_hour')) {
      context.handle(_endHourMeta,
          endHour.isAcceptableOrUnknown(data['end_hour']!, _endHourMeta));
    } else if (isInserting) {
      context.missing(_endHourMeta);
    }
    if (data.containsKey('end_minute')) {
      context.handle(_endMinuteMeta,
          endMinute.isAcceptableOrUnknown(data['end_minute']!, _endMinuteMeta));
    }
    if (data.containsKey('weekdays')) {
      context.handle(_weekdaysMeta,
          weekdays.isAcceptableOrUnknown(data['weekdays']!, _weekdaysMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('color_hex')) {
      context.handle(_colorHexMeta,
          colorHex.isAcceptableOrUnknown(data['color_hex']!, _colorHexMeta));
    }
    if (data.containsKey('emoji')) {
      context.handle(
          _emojiMeta, emoji.isAcceptableOrUnknown(data['emoji']!, _emojiMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TimeBlock map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TimeBlock(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      startHour: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}start_hour'])!,
      startMinute: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}start_minute'])!,
      endHour: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}end_hour'])!,
      endMinute: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}end_minute'])!,
      weekdays: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}weekdays'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      colorHex: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}color_hex'])!,
      emoji: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}emoji'])!,
    );
  }

  @override
  $TimeBlocksTable createAlias(String alias) {
    return $TimeBlocksTable(attachedDatabase, alias);
  }
}

class TimeBlock extends DataClass implements Insertable<TimeBlock> {
  final int id;
  final String name;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final String weekdays;
  final bool isActive;
  final String colorHex;
  final String emoji;
  const TimeBlock(
      {required this.id,
      required this.name,
      required this.startHour,
      required this.startMinute,
      required this.endHour,
      required this.endMinute,
      required this.weekdays,
      required this.isActive,
      required this.colorHex,
      required this.emoji});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['start_hour'] = Variable<int>(startHour);
    map['start_minute'] = Variable<int>(startMinute);
    map['end_hour'] = Variable<int>(endHour);
    map['end_minute'] = Variable<int>(endMinute);
    map['weekdays'] = Variable<String>(weekdays);
    map['is_active'] = Variable<bool>(isActive);
    map['color_hex'] = Variable<String>(colorHex);
    map['emoji'] = Variable<String>(emoji);
    return map;
  }

  TimeBlocksCompanion toCompanion(bool nullToAbsent) {
    return TimeBlocksCompanion(
      id: Value(id),
      name: Value(name),
      startHour: Value(startHour),
      startMinute: Value(startMinute),
      endHour: Value(endHour),
      endMinute: Value(endMinute),
      weekdays: Value(weekdays),
      isActive: Value(isActive),
      colorHex: Value(colorHex),
      emoji: Value(emoji),
    );
  }

  factory TimeBlock.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TimeBlock(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      startHour: serializer.fromJson<int>(json['startHour']),
      startMinute: serializer.fromJson<int>(json['startMinute']),
      endHour: serializer.fromJson<int>(json['endHour']),
      endMinute: serializer.fromJson<int>(json['endMinute']),
      weekdays: serializer.fromJson<String>(json['weekdays']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      colorHex: serializer.fromJson<String>(json['colorHex']),
      emoji: serializer.fromJson<String>(json['emoji']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'startHour': serializer.toJson<int>(startHour),
      'startMinute': serializer.toJson<int>(startMinute),
      'endHour': serializer.toJson<int>(endHour),
      'endMinute': serializer.toJson<int>(endMinute),
      'weekdays': serializer.toJson<String>(weekdays),
      'isActive': serializer.toJson<bool>(isActive),
      'colorHex': serializer.toJson<String>(colorHex),
      'emoji': serializer.toJson<String>(emoji),
    };
  }

  TimeBlock copyWith(
          {int? id,
          String? name,
          int? startHour,
          int? startMinute,
          int? endHour,
          int? endMinute,
          String? weekdays,
          bool? isActive,
          String? colorHex,
          String? emoji}) =>
      TimeBlock(
        id: id ?? this.id,
        name: name ?? this.name,
        startHour: startHour ?? this.startHour,
        startMinute: startMinute ?? this.startMinute,
        endHour: endHour ?? this.endHour,
        endMinute: endMinute ?? this.endMinute,
        weekdays: weekdays ?? this.weekdays,
        isActive: isActive ?? this.isActive,
        colorHex: colorHex ?? this.colorHex,
        emoji: emoji ?? this.emoji,
      );
  TimeBlock copyWithCompanion(TimeBlocksCompanion data) {
    return TimeBlock(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      startHour: data.startHour.present ? data.startHour.value : this.startHour,
      startMinute:
          data.startMinute.present ? data.startMinute.value : this.startMinute,
      endHour: data.endHour.present ? data.endHour.value : this.endHour,
      endMinute: data.endMinute.present ? data.endMinute.value : this.endMinute,
      weekdays: data.weekdays.present ? data.weekdays.value : this.weekdays,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      colorHex: data.colorHex.present ? data.colorHex.value : this.colorHex,
      emoji: data.emoji.present ? data.emoji.value : this.emoji,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TimeBlock(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('startHour: $startHour, ')
          ..write('startMinute: $startMinute, ')
          ..write('endHour: $endHour, ')
          ..write('endMinute: $endMinute, ')
          ..write('weekdays: $weekdays, ')
          ..write('isActive: $isActive, ')
          ..write('colorHex: $colorHex, ')
          ..write('emoji: $emoji')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, startHour, startMinute, endHour,
      endMinute, weekdays, isActive, colorHex, emoji);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimeBlock &&
          other.id == this.id &&
          other.name == this.name &&
          other.startHour == this.startHour &&
          other.startMinute == this.startMinute &&
          other.endHour == this.endHour &&
          other.endMinute == this.endMinute &&
          other.weekdays == this.weekdays &&
          other.isActive == this.isActive &&
          other.colorHex == this.colorHex &&
          other.emoji == this.emoji);
}

class TimeBlocksCompanion extends UpdateCompanion<TimeBlock> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> startHour;
  final Value<int> startMinute;
  final Value<int> endHour;
  final Value<int> endMinute;
  final Value<String> weekdays;
  final Value<bool> isActive;
  final Value<String> colorHex;
  final Value<String> emoji;
  const TimeBlocksCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.startHour = const Value.absent(),
    this.startMinute = const Value.absent(),
    this.endHour = const Value.absent(),
    this.endMinute = const Value.absent(),
    this.weekdays = const Value.absent(),
    this.isActive = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.emoji = const Value.absent(),
  });
  TimeBlocksCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required int startHour,
    this.startMinute = const Value.absent(),
    required int endHour,
    this.endMinute = const Value.absent(),
    this.weekdays = const Value.absent(),
    this.isActive = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.emoji = const Value.absent(),
  })  : name = Value(name),
        startHour = Value(startHour),
        endHour = Value(endHour);
  static Insertable<TimeBlock> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? startHour,
    Expression<int>? startMinute,
    Expression<int>? endHour,
    Expression<int>? endMinute,
    Expression<String>? weekdays,
    Expression<bool>? isActive,
    Expression<String>? colorHex,
    Expression<String>? emoji,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (startHour != null) 'start_hour': startHour,
      if (startMinute != null) 'start_minute': startMinute,
      if (endHour != null) 'end_hour': endHour,
      if (endMinute != null) 'end_minute': endMinute,
      if (weekdays != null) 'weekdays': weekdays,
      if (isActive != null) 'is_active': isActive,
      if (colorHex != null) 'color_hex': colorHex,
      if (emoji != null) 'emoji': emoji,
    });
  }

  TimeBlocksCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<int>? startHour,
      Value<int>? startMinute,
      Value<int>? endHour,
      Value<int>? endMinute,
      Value<String>? weekdays,
      Value<bool>? isActive,
      Value<String>? colorHex,
      Value<String>? emoji}) {
    return TimeBlocksCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      startHour: startHour ?? this.startHour,
      startMinute: startMinute ?? this.startMinute,
      endHour: endHour ?? this.endHour,
      endMinute: endMinute ?? this.endMinute,
      weekdays: weekdays ?? this.weekdays,
      isActive: isActive ?? this.isActive,
      colorHex: colorHex ?? this.colorHex,
      emoji: emoji ?? this.emoji,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (startHour.present) {
      map['start_hour'] = Variable<int>(startHour.value);
    }
    if (startMinute.present) {
      map['start_minute'] = Variable<int>(startMinute.value);
    }
    if (endHour.present) {
      map['end_hour'] = Variable<int>(endHour.value);
    }
    if (endMinute.present) {
      map['end_minute'] = Variable<int>(endMinute.value);
    }
    if (weekdays.present) {
      map['weekdays'] = Variable<String>(weekdays.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (colorHex.present) {
      map['color_hex'] = Variable<String>(colorHex.value);
    }
    if (emoji.present) {
      map['emoji'] = Variable<String>(emoji.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TimeBlocksCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('startHour: $startHour, ')
          ..write('startMinute: $startMinute, ')
          ..write('endHour: $endHour, ')
          ..write('endMinute: $endMinute, ')
          ..write('weekdays: $weekdays, ')
          ..write('isActive: $isActive, ')
          ..write('colorHex: $colorHex, ')
          ..write('emoji: $emoji')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, Tag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _colorHexMeta =
      const VerificationMeta('colorHex');
  @override
  late final GeneratedColumn<String> colorHex = GeneratedColumn<String>(
      'color_hex', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _iconNameMeta =
      const VerificationMeta('iconName');
  @override
  late final GeneratedColumn<String> iconName = GeneratedColumn<String>(
      'icon_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [id, name, colorHex, iconName];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(Insertable<Tag> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_hex')) {
      context.handle(_colorHexMeta,
          colorHex.isAcceptableOrUnknown(data['color_hex']!, _colorHexMeta));
    } else if (isInserting) {
      context.missing(_colorHexMeta);
    }
    if (data.containsKey('icon_name')) {
      context.handle(_iconNameMeta,
          iconName.isAcceptableOrUnknown(data['icon_name']!, _iconNameMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Tag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tag(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      colorHex: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}color_hex'])!,
      iconName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}icon_name']),
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class Tag extends DataClass implements Insertable<Tag> {
  final int id;
  final String name;
  final String colorHex;
  final String? iconName;
  const Tag(
      {required this.id,
      required this.name,
      required this.colorHex,
      this.iconName});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['color_hex'] = Variable<String>(colorHex);
    if (!nullToAbsent || iconName != null) {
      map['icon_name'] = Variable<String>(iconName);
    }
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      name: Value(name),
      colorHex: Value(colorHex),
      iconName: iconName == null && nullToAbsent
          ? const Value.absent()
          : Value(iconName),
    );
  }

  factory Tag.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tag(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      colorHex: serializer.fromJson<String>(json['colorHex']),
      iconName: serializer.fromJson<String?>(json['iconName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'colorHex': serializer.toJson<String>(colorHex),
      'iconName': serializer.toJson<String?>(iconName),
    };
  }

  Tag copyWith(
          {int? id,
          String? name,
          String? colorHex,
          Value<String?> iconName = const Value.absent()}) =>
      Tag(
        id: id ?? this.id,
        name: name ?? this.name,
        colorHex: colorHex ?? this.colorHex,
        iconName: iconName.present ? iconName.value : this.iconName,
      );
  Tag copyWithCompanion(TagsCompanion data) {
    return Tag(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      colorHex: data.colorHex.present ? data.colorHex.value : this.colorHex,
      iconName: data.iconName.present ? data.iconName.value : this.iconName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Tag(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorHex: $colorHex, ')
          ..write('iconName: $iconName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, colorHex, iconName);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tag &&
          other.id == this.id &&
          other.name == this.name &&
          other.colorHex == this.colorHex &&
          other.iconName == this.iconName);
}

class TagsCompanion extends UpdateCompanion<Tag> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> colorHex;
  final Value<String?> iconName;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.iconName = const Value.absent(),
  });
  TagsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String colorHex,
    this.iconName = const Value.absent(),
  })  : name = Value(name),
        colorHex = Value(colorHex);
  static Insertable<Tag> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? colorHex,
    Expression<String>? iconName,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (colorHex != null) 'color_hex': colorHex,
      if (iconName != null) 'icon_name': iconName,
    });
  }

  TagsCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<String>? colorHex,
      Value<String?>? iconName}) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      iconName: iconName ?? this.iconName,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorHex.present) {
      map['color_hex'] = Variable<String>(colorHex.value);
    }
    if (iconName.present) {
      map['icon_name'] = Variable<String>(iconName.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorHex: $colorHex, ')
          ..write('iconName: $iconName')
          ..write(')'))
        .toString();
  }
}

class $ProjectsTable extends Projects with TableInfo<$ProjectsTable, Project> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _colorHexMeta =
      const VerificationMeta('colorHex');
  @override
  late final GeneratedColumn<String> colorHex = GeneratedColumn<String>(
      'color_hex', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _deadlineMeta =
      const VerificationMeta('deadline');
  @override
  late final GeneratedColumn<DateTime> deadline = GeneratedColumn<DateTime>(
      'deadline', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _isArchivedMeta =
      const VerificationMeta('isArchived');
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
      'is_archived', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_archived" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, colorHex, description, deadline, isArchived, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'projects';
  @override
  VerificationContext validateIntegrity(Insertable<Project> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_hex')) {
      context.handle(_colorHexMeta,
          colorHex.isAcceptableOrUnknown(data['color_hex']!, _colorHexMeta));
    } else if (isInserting) {
      context.missing(_colorHexMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('deadline')) {
      context.handle(_deadlineMeta,
          deadline.isAcceptableOrUnknown(data['deadline']!, _deadlineMeta));
    }
    if (data.containsKey('is_archived')) {
      context.handle(
          _isArchivedMeta,
          isArchived.isAcceptableOrUnknown(
              data['is_archived']!, _isArchivedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Project map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Project(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      colorHex: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}color_hex'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      deadline: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deadline']),
      isArchived: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_archived'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ProjectsTable createAlias(String alias) {
    return $ProjectsTable(attachedDatabase, alias);
  }
}

class Project extends DataClass implements Insertable<Project> {
  final int id;
  final String name;
  final String colorHex;
  final String? description;
  final DateTime? deadline;
  final bool isArchived;
  final DateTime createdAt;
  const Project(
      {required this.id,
      required this.name,
      required this.colorHex,
      this.description,
      this.deadline,
      required this.isArchived,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['color_hex'] = Variable<String>(colorHex);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || deadline != null) {
      map['deadline'] = Variable<DateTime>(deadline);
    }
    map['is_archived'] = Variable<bool>(isArchived);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ProjectsCompanion toCompanion(bool nullToAbsent) {
    return ProjectsCompanion(
      id: Value(id),
      name: Value(name),
      colorHex: Value(colorHex),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      deadline: deadline == null && nullToAbsent
          ? const Value.absent()
          : Value(deadline),
      isArchived: Value(isArchived),
      createdAt: Value(createdAt),
    );
  }

  factory Project.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Project(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      colorHex: serializer.fromJson<String>(json['colorHex']),
      description: serializer.fromJson<String?>(json['description']),
      deadline: serializer.fromJson<DateTime?>(json['deadline']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'colorHex': serializer.toJson<String>(colorHex),
      'description': serializer.toJson<String?>(description),
      'deadline': serializer.toJson<DateTime?>(deadline),
      'isArchived': serializer.toJson<bool>(isArchived),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Project copyWith(
          {int? id,
          String? name,
          String? colorHex,
          Value<String?> description = const Value.absent(),
          Value<DateTime?> deadline = const Value.absent(),
          bool? isArchived,
          DateTime? createdAt}) =>
      Project(
        id: id ?? this.id,
        name: name ?? this.name,
        colorHex: colorHex ?? this.colorHex,
        description: description.present ? description.value : this.description,
        deadline: deadline.present ? deadline.value : this.deadline,
        isArchived: isArchived ?? this.isArchived,
        createdAt: createdAt ?? this.createdAt,
      );
  Project copyWithCompanion(ProjectsCompanion data) {
    return Project(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      colorHex: data.colorHex.present ? data.colorHex.value : this.colorHex,
      description:
          data.description.present ? data.description.value : this.description,
      deadline: data.deadline.present ? data.deadline.value : this.deadline,
      isArchived:
          data.isArchived.present ? data.isArchived.value : this.isArchived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Project(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorHex: $colorHex, ')
          ..write('description: $description, ')
          ..write('deadline: $deadline, ')
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, name, colorHex, description, deadline, isArchived, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Project &&
          other.id == this.id &&
          other.name == this.name &&
          other.colorHex == this.colorHex &&
          other.description == this.description &&
          other.deadline == this.deadline &&
          other.isArchived == this.isArchived &&
          other.createdAt == this.createdAt);
}

class ProjectsCompanion extends UpdateCompanion<Project> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> colorHex;
  final Value<String?> description;
  final Value<DateTime?> deadline;
  final Value<bool> isArchived;
  final Value<DateTime> createdAt;
  const ProjectsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.description = const Value.absent(),
    this.deadline = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ProjectsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String colorHex,
    this.description = const Value.absent(),
    this.deadline = const Value.absent(),
    this.isArchived = const Value.absent(),
    required DateTime createdAt,
  })  : name = Value(name),
        colorHex = Value(colorHex),
        createdAt = Value(createdAt);
  static Insertable<Project> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? colorHex,
    Expression<String>? description,
    Expression<DateTime>? deadline,
    Expression<bool>? isArchived,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (colorHex != null) 'color_hex': colorHex,
      if (description != null) 'description': description,
      if (deadline != null) 'deadline': deadline,
      if (isArchived != null) 'is_archived': isArchived,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ProjectsCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<String>? colorHex,
      Value<String?>? description,
      Value<DateTime?>? deadline,
      Value<bool>? isArchived,
      Value<DateTime>? createdAt}) {
    return ProjectsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      description: description ?? this.description,
      deadline: deadline ?? this.deadline,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorHex.present) {
      map['color_hex'] = Variable<String>(colorHex.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (deadline.present) {
      map['deadline'] = Variable<DateTime>(deadline.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorHex: $colorHex, ')
          ..write('description: $description, ')
          ..write('deadline: $deadline, ')
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ActivityRecordsTable extends ActivityRecords
    with TableInfo<$ActivityRecordsTable, ActivityRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivityRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _startTimeMeta =
      const VerificationMeta('startTime');
  @override
  late final GeneratedColumn<DateTime> startTime = GeneratedColumn<DateTime>(
      'start_time', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _endTimeMeta =
      const VerificationMeta('endTime');
  @override
  late final GeneratedColumn<DateTime> endTime = GeneratedColumn<DateTime>(
      'end_time', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _durationMinutesMeta =
      const VerificationMeta('durationMinutes');
  @override
  late final GeneratedColumn<int> durationMinutes = GeneratedColumn<int>(
      'duration_minutes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _manualLabelMeta =
      const VerificationMeta('manualLabel');
  @override
  late final GeneratedColumn<String> manualLabel = GeneratedColumn<String>(
      'manual_label', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _processNameMeta =
      const VerificationMeta('processName');
  @override
  late final GeneratedColumn<String> processName = GeneratedColumn<String>(
      'process_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _windowTitleMeta =
      const VerificationMeta('windowTitle');
  @override
  late final GeneratedColumn<String> windowTitle = GeneratedColumn<String>(
      'window_title', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _packageNameMeta =
      const VerificationMeta('packageName');
  @override
  late final GeneratedColumn<String> packageName = GeneratedColumn<String>(
      'package_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _appUsageRuleIdMeta =
      const VerificationMeta('appUsageRuleId');
  @override
  late final GeneratedColumn<String> appUsageRuleId = GeneratedColumn<String>(
      'app_usage_rule_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _linkedTaskIdMeta =
      const VerificationMeta('linkedTaskId');
  @override
  late final GeneratedColumn<int> linkedTaskId = GeneratedColumn<int>(
      'linked_task_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _keyCountMeta =
      const VerificationMeta('keyCount');
  @override
  late final GeneratedColumn<int> keyCount = GeneratedColumn<int>(
      'key_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _mouseClicksMeta =
      const VerificationMeta('mouseClicks');
  @override
  late final GeneratedColumn<int> mouseClicks = GeneratedColumn<int>(
      'mouse_clicks', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _mouseMovePxMeta =
      const VerificationMeta('mouseMovePx');
  @override
  late final GeneratedColumn<int> mouseMovePx = GeneratedColumn<int>(
      'mouse_move_px', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _scrollPxMeta =
      const VerificationMeta('scrollPx');
  @override
  late final GeneratedColumn<int> scrollPx = GeneratedColumn<int>(
      'scroll_px', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _keySequenceMeta =
      const VerificationMeta('keySequence');
  @override
  late final GeneratedColumn<String> keySequence = GeneratedColumn<String>(
      'key_sequence', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isAutoMeta = const VerificationMeta('isAuto');
  @override
  late final GeneratedColumn<bool> isAuto = GeneratedColumn<bool>(
      'is_auto', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_auto" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
      'source', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('manual'));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        startTime,
        endTime,
        durationMinutes,
        manualLabel,
        processName,
        windowTitle,
        packageName,
        category,
        appUsageRuleId,
        linkedTaskId,
        keyCount,
        mouseClicks,
        mouseMovePx,
        scrollPx,
        keySequence,
        isAuto,
        source
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activity_records';
  @override
  VerificationContext validateIntegrity(Insertable<ActivityRecord> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('start_time')) {
      context.handle(_startTimeMeta,
          startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta));
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(_endTimeMeta,
          endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta));
    }
    if (data.containsKey('duration_minutes')) {
      context.handle(
          _durationMinutesMeta,
          durationMinutes.isAcceptableOrUnknown(
              data['duration_minutes']!, _durationMinutesMeta));
    }
    if (data.containsKey('manual_label')) {
      context.handle(
          _manualLabelMeta,
          manualLabel.isAcceptableOrUnknown(
              data['manual_label']!, _manualLabelMeta));
    }
    if (data.containsKey('process_name')) {
      context.handle(
          _processNameMeta,
          processName.isAcceptableOrUnknown(
              data['process_name']!, _processNameMeta));
    }
    if (data.containsKey('window_title')) {
      context.handle(
          _windowTitleMeta,
          windowTitle.isAcceptableOrUnknown(
              data['window_title']!, _windowTitleMeta));
    }
    if (data.containsKey('package_name')) {
      context.handle(
          _packageNameMeta,
          packageName.isAcceptableOrUnknown(
              data['package_name']!, _packageNameMeta));
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    }
    if (data.containsKey('app_usage_rule_id')) {
      context.handle(
          _appUsageRuleIdMeta,
          appUsageRuleId.isAcceptableOrUnknown(
              data['app_usage_rule_id']!, _appUsageRuleIdMeta));
    }
    if (data.containsKey('linked_task_id')) {
      context.handle(
          _linkedTaskIdMeta,
          linkedTaskId.isAcceptableOrUnknown(
              data['linked_task_id']!, _linkedTaskIdMeta));
    }
    if (data.containsKey('key_count')) {
      context.handle(_keyCountMeta,
          keyCount.isAcceptableOrUnknown(data['key_count']!, _keyCountMeta));
    }
    if (data.containsKey('mouse_clicks')) {
      context.handle(
          _mouseClicksMeta,
          mouseClicks.isAcceptableOrUnknown(
              data['mouse_clicks']!, _mouseClicksMeta));
    }
    if (data.containsKey('mouse_move_px')) {
      context.handle(
          _mouseMovePxMeta,
          mouseMovePx.isAcceptableOrUnknown(
              data['mouse_move_px']!, _mouseMovePxMeta));
    }
    if (data.containsKey('scroll_px')) {
      context.handle(_scrollPxMeta,
          scrollPx.isAcceptableOrUnknown(data['scroll_px']!, _scrollPxMeta));
    }
    if (data.containsKey('key_sequence')) {
      context.handle(
          _keySequenceMeta,
          keySequence.isAcceptableOrUnknown(
              data['key_sequence']!, _keySequenceMeta));
    }
    if (data.containsKey('is_auto')) {
      context.handle(_isAutoMeta,
          isAuto.isAcceptableOrUnknown(data['is_auto']!, _isAutoMeta));
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ActivityRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActivityRecord(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      startTime: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}start_time'])!,
      endTime: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}end_time']),
      durationMinutes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_minutes'])!,
      manualLabel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}manual_label']),
      processName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}process_name']),
      windowTitle: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}window_title']),
      packageName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}package_name']),
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category']),
      appUsageRuleId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}app_usage_rule_id']),
      linkedTaskId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}linked_task_id']),
      keyCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}key_count'])!,
      mouseClicks: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}mouse_clicks'])!,
      mouseMovePx: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}mouse_move_px'])!,
      scrollPx: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}scroll_px'])!,
      keySequence: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key_sequence']),
      isAuto: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_auto'])!,
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source'])!,
    );
  }

  @override
  $ActivityRecordsTable createAlias(String alias) {
    return $ActivityRecordsTable(attachedDatabase, alias);
  }
}

class ActivityRecord extends DataClass implements Insertable<ActivityRecord> {
  final int id;
  final DateTime startTime;
  final DateTime? endTime;
  final int durationMinutes;
  final String? manualLabel;
  final String? processName;
  final String? windowTitle;
  final String? packageName;
  final String? category;
  final String? appUsageRuleId;
  final int? linkedTaskId;
  final int keyCount;
  final int mouseClicks;
  final int mouseMovePx;
  final int scrollPx;
  final String? keySequence;
  final bool isAuto;
  final String source;
  const ActivityRecord(
      {required this.id,
      required this.startTime,
      this.endTime,
      required this.durationMinutes,
      this.manualLabel,
      this.processName,
      this.windowTitle,
      this.packageName,
      this.category,
      this.appUsageRuleId,
      this.linkedTaskId,
      required this.keyCount,
      required this.mouseClicks,
      required this.mouseMovePx,
      required this.scrollPx,
      this.keySequence,
      required this.isAuto,
      required this.source});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['start_time'] = Variable<DateTime>(startTime);
    if (!nullToAbsent || endTime != null) {
      map['end_time'] = Variable<DateTime>(endTime);
    }
    map['duration_minutes'] = Variable<int>(durationMinutes);
    if (!nullToAbsent || manualLabel != null) {
      map['manual_label'] = Variable<String>(manualLabel);
    }
    if (!nullToAbsent || processName != null) {
      map['process_name'] = Variable<String>(processName);
    }
    if (!nullToAbsent || windowTitle != null) {
      map['window_title'] = Variable<String>(windowTitle);
    }
    if (!nullToAbsent || packageName != null) {
      map['package_name'] = Variable<String>(packageName);
    }
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    if (!nullToAbsent || appUsageRuleId != null) {
      map['app_usage_rule_id'] = Variable<String>(appUsageRuleId);
    }
    if (!nullToAbsent || linkedTaskId != null) {
      map['linked_task_id'] = Variable<int>(linkedTaskId);
    }
    map['key_count'] = Variable<int>(keyCount);
    map['mouse_clicks'] = Variable<int>(mouseClicks);
    map['mouse_move_px'] = Variable<int>(mouseMovePx);
    map['scroll_px'] = Variable<int>(scrollPx);
    if (!nullToAbsent || keySequence != null) {
      map['key_sequence'] = Variable<String>(keySequence);
    }
    map['is_auto'] = Variable<bool>(isAuto);
    map['source'] = Variable<String>(source);
    return map;
  }

  ActivityRecordsCompanion toCompanion(bool nullToAbsent) {
    return ActivityRecordsCompanion(
      id: Value(id),
      startTime: Value(startTime),
      endTime: endTime == null && nullToAbsent
          ? const Value.absent()
          : Value(endTime),
      durationMinutes: Value(durationMinutes),
      manualLabel: manualLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(manualLabel),
      processName: processName == null && nullToAbsent
          ? const Value.absent()
          : Value(processName),
      windowTitle: windowTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(windowTitle),
      packageName: packageName == null && nullToAbsent
          ? const Value.absent()
          : Value(packageName),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      appUsageRuleId: appUsageRuleId == null && nullToAbsent
          ? const Value.absent()
          : Value(appUsageRuleId),
      linkedTaskId: linkedTaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedTaskId),
      keyCount: Value(keyCount),
      mouseClicks: Value(mouseClicks),
      mouseMovePx: Value(mouseMovePx),
      scrollPx: Value(scrollPx),
      keySequence: keySequence == null && nullToAbsent
          ? const Value.absent()
          : Value(keySequence),
      isAuto: Value(isAuto),
      source: Value(source),
    );
  }

  factory ActivityRecord.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActivityRecord(
      id: serializer.fromJson<int>(json['id']),
      startTime: serializer.fromJson<DateTime>(json['startTime']),
      endTime: serializer.fromJson<DateTime?>(json['endTime']),
      durationMinutes: serializer.fromJson<int>(json['durationMinutes']),
      manualLabel: serializer.fromJson<String?>(json['manualLabel']),
      processName: serializer.fromJson<String?>(json['processName']),
      windowTitle: serializer.fromJson<String?>(json['windowTitle']),
      packageName: serializer.fromJson<String?>(json['packageName']),
      category: serializer.fromJson<String?>(json['category']),
      appUsageRuleId: serializer.fromJson<String?>(json['appUsageRuleId']),
      linkedTaskId: serializer.fromJson<int?>(json['linkedTaskId']),
      keyCount: serializer.fromJson<int>(json['keyCount']),
      mouseClicks: serializer.fromJson<int>(json['mouseClicks']),
      mouseMovePx: serializer.fromJson<int>(json['mouseMovePx']),
      scrollPx: serializer.fromJson<int>(json['scrollPx']),
      keySequence: serializer.fromJson<String?>(json['keySequence']),
      isAuto: serializer.fromJson<bool>(json['isAuto']),
      source: serializer.fromJson<String>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'startTime': serializer.toJson<DateTime>(startTime),
      'endTime': serializer.toJson<DateTime?>(endTime),
      'durationMinutes': serializer.toJson<int>(durationMinutes),
      'manualLabel': serializer.toJson<String?>(manualLabel),
      'processName': serializer.toJson<String?>(processName),
      'windowTitle': serializer.toJson<String?>(windowTitle),
      'packageName': serializer.toJson<String?>(packageName),
      'category': serializer.toJson<String?>(category),
      'appUsageRuleId': serializer.toJson<String?>(appUsageRuleId),
      'linkedTaskId': serializer.toJson<int?>(linkedTaskId),
      'keyCount': serializer.toJson<int>(keyCount),
      'mouseClicks': serializer.toJson<int>(mouseClicks),
      'mouseMovePx': serializer.toJson<int>(mouseMovePx),
      'scrollPx': serializer.toJson<int>(scrollPx),
      'keySequence': serializer.toJson<String?>(keySequence),
      'isAuto': serializer.toJson<bool>(isAuto),
      'source': serializer.toJson<String>(source),
    };
  }

  ActivityRecord copyWith(
          {int? id,
          DateTime? startTime,
          Value<DateTime?> endTime = const Value.absent(),
          int? durationMinutes,
          Value<String?> manualLabel = const Value.absent(),
          Value<String?> processName = const Value.absent(),
          Value<String?> windowTitle = const Value.absent(),
          Value<String?> packageName = const Value.absent(),
          Value<String?> category = const Value.absent(),
          Value<String?> appUsageRuleId = const Value.absent(),
          Value<int?> linkedTaskId = const Value.absent(),
          int? keyCount,
          int? mouseClicks,
          int? mouseMovePx,
          int? scrollPx,
          Value<String?> keySequence = const Value.absent(),
          bool? isAuto,
          String? source}) =>
      ActivityRecord(
        id: id ?? this.id,
        startTime: startTime ?? this.startTime,
        endTime: endTime.present ? endTime.value : this.endTime,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        manualLabel: manualLabel.present ? manualLabel.value : this.manualLabel,
        processName: processName.present ? processName.value : this.processName,
        windowTitle: windowTitle.present ? windowTitle.value : this.windowTitle,
        packageName: packageName.present ? packageName.value : this.packageName,
        category: category.present ? category.value : this.category,
        appUsageRuleId:
            appUsageRuleId.present ? appUsageRuleId.value : this.appUsageRuleId,
        linkedTaskId:
            linkedTaskId.present ? linkedTaskId.value : this.linkedTaskId,
        keyCount: keyCount ?? this.keyCount,
        mouseClicks: mouseClicks ?? this.mouseClicks,
        mouseMovePx: mouseMovePx ?? this.mouseMovePx,
        scrollPx: scrollPx ?? this.scrollPx,
        keySequence: keySequence.present ? keySequence.value : this.keySequence,
        isAuto: isAuto ?? this.isAuto,
        source: source ?? this.source,
      );
  ActivityRecord copyWithCompanion(ActivityRecordsCompanion data) {
    return ActivityRecord(
      id: data.id.present ? data.id.value : this.id,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      durationMinutes: data.durationMinutes.present
          ? data.durationMinutes.value
          : this.durationMinutes,
      manualLabel:
          data.manualLabel.present ? data.manualLabel.value : this.manualLabel,
      processName:
          data.processName.present ? data.processName.value : this.processName,
      windowTitle:
          data.windowTitle.present ? data.windowTitle.value : this.windowTitle,
      packageName:
          data.packageName.present ? data.packageName.value : this.packageName,
      category: data.category.present ? data.category.value : this.category,
      appUsageRuleId: data.appUsageRuleId.present
          ? data.appUsageRuleId.value
          : this.appUsageRuleId,
      linkedTaskId: data.linkedTaskId.present
          ? data.linkedTaskId.value
          : this.linkedTaskId,
      keyCount: data.keyCount.present ? data.keyCount.value : this.keyCount,
      mouseClicks:
          data.mouseClicks.present ? data.mouseClicks.value : this.mouseClicks,
      mouseMovePx: data.mouseMovePx.present
          ? data.mouseMovePx.value
          : this.mouseMovePx,
      scrollPx: data.scrollPx.present ? data.scrollPx.value : this.scrollPx,
      keySequence:
          data.keySequence.present ? data.keySequence.value : this.keySequence,
      isAuto: data.isAuto.present ? data.isAuto.value : this.isAuto,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActivityRecord(')
          ..write('id: $id, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('durationMinutes: $durationMinutes, ')
          ..write('manualLabel: $manualLabel, ')
          ..write('processName: $processName, ')
          ..write('windowTitle: $windowTitle, ')
          ..write('packageName: $packageName, ')
          ..write('category: $category, ')
          ..write('appUsageRuleId: $appUsageRuleId, ')
          ..write('linkedTaskId: $linkedTaskId, ')
          ..write('keyCount: $keyCount, ')
          ..write('mouseClicks: $mouseClicks, ')
          ..write('mouseMovePx: $mouseMovePx, ')
          ..write('scrollPx: $scrollPx, ')
          ..write('keySequence: $keySequence, ')
          ..write('isAuto: $isAuto, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      startTime,
      endTime,
      durationMinutes,
      manualLabel,
      processName,
      windowTitle,
      packageName,
      category,
      appUsageRuleId,
      linkedTaskId,
      keyCount,
      mouseClicks,
      mouseMovePx,
      scrollPx,
      keySequence,
      isAuto,
      source);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActivityRecord &&
          other.id == this.id &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.durationMinutes == this.durationMinutes &&
          other.manualLabel == this.manualLabel &&
          other.processName == this.processName &&
          other.windowTitle == this.windowTitle &&
          other.packageName == this.packageName &&
          other.category == this.category &&
          other.appUsageRuleId == this.appUsageRuleId &&
          other.linkedTaskId == this.linkedTaskId &&
          other.keyCount == this.keyCount &&
          other.mouseClicks == this.mouseClicks &&
          other.mouseMovePx == this.mouseMovePx &&
          other.scrollPx == this.scrollPx &&
          other.keySequence == this.keySequence &&
          other.isAuto == this.isAuto &&
          other.source == this.source);
}

class ActivityRecordsCompanion extends UpdateCompanion<ActivityRecord> {
  final Value<int> id;
  final Value<DateTime> startTime;
  final Value<DateTime?> endTime;
  final Value<int> durationMinutes;
  final Value<String?> manualLabel;
  final Value<String?> processName;
  final Value<String?> windowTitle;
  final Value<String?> packageName;
  final Value<String?> category;
  final Value<String?> appUsageRuleId;
  final Value<int?> linkedTaskId;
  final Value<int> keyCount;
  final Value<int> mouseClicks;
  final Value<int> mouseMovePx;
  final Value<int> scrollPx;
  final Value<String?> keySequence;
  final Value<bool> isAuto;
  final Value<String> source;
  const ActivityRecordsCompanion({
    this.id = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.durationMinutes = const Value.absent(),
    this.manualLabel = const Value.absent(),
    this.processName = const Value.absent(),
    this.windowTitle = const Value.absent(),
    this.packageName = const Value.absent(),
    this.category = const Value.absent(),
    this.appUsageRuleId = const Value.absent(),
    this.linkedTaskId = const Value.absent(),
    this.keyCount = const Value.absent(),
    this.mouseClicks = const Value.absent(),
    this.mouseMovePx = const Value.absent(),
    this.scrollPx = const Value.absent(),
    this.keySequence = const Value.absent(),
    this.isAuto = const Value.absent(),
    this.source = const Value.absent(),
  });
  ActivityRecordsCompanion.insert({
    this.id = const Value.absent(),
    required DateTime startTime,
    this.endTime = const Value.absent(),
    this.durationMinutes = const Value.absent(),
    this.manualLabel = const Value.absent(),
    this.processName = const Value.absent(),
    this.windowTitle = const Value.absent(),
    this.packageName = const Value.absent(),
    this.category = const Value.absent(),
    this.appUsageRuleId = const Value.absent(),
    this.linkedTaskId = const Value.absent(),
    this.keyCount = const Value.absent(),
    this.mouseClicks = const Value.absent(),
    this.mouseMovePx = const Value.absent(),
    this.scrollPx = const Value.absent(),
    this.keySequence = const Value.absent(),
    this.isAuto = const Value.absent(),
    this.source = const Value.absent(),
  }) : startTime = Value(startTime);
  static Insertable<ActivityRecord> custom({
    Expression<int>? id,
    Expression<DateTime>? startTime,
    Expression<DateTime>? endTime,
    Expression<int>? durationMinutes,
    Expression<String>? manualLabel,
    Expression<String>? processName,
    Expression<String>? windowTitle,
    Expression<String>? packageName,
    Expression<String>? category,
    Expression<String>? appUsageRuleId,
    Expression<int>? linkedTaskId,
    Expression<int>? keyCount,
    Expression<int>? mouseClicks,
    Expression<int>? mouseMovePx,
    Expression<int>? scrollPx,
    Expression<String>? keySequence,
    Expression<bool>? isAuto,
    Expression<String>? source,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (durationMinutes != null) 'duration_minutes': durationMinutes,
      if (manualLabel != null) 'manual_label': manualLabel,
      if (processName != null) 'process_name': processName,
      if (windowTitle != null) 'window_title': windowTitle,
      if (packageName != null) 'package_name': packageName,
      if (category != null) 'category': category,
      if (appUsageRuleId != null) 'app_usage_rule_id': appUsageRuleId,
      if (linkedTaskId != null) 'linked_task_id': linkedTaskId,
      if (keyCount != null) 'key_count': keyCount,
      if (mouseClicks != null) 'mouse_clicks': mouseClicks,
      if (mouseMovePx != null) 'mouse_move_px': mouseMovePx,
      if (scrollPx != null) 'scroll_px': scrollPx,
      if (keySequence != null) 'key_sequence': keySequence,
      if (isAuto != null) 'is_auto': isAuto,
      if (source != null) 'source': source,
    });
  }

  ActivityRecordsCompanion copyWith(
      {Value<int>? id,
      Value<DateTime>? startTime,
      Value<DateTime?>? endTime,
      Value<int>? durationMinutes,
      Value<String?>? manualLabel,
      Value<String?>? processName,
      Value<String?>? windowTitle,
      Value<String?>? packageName,
      Value<String?>? category,
      Value<String?>? appUsageRuleId,
      Value<int?>? linkedTaskId,
      Value<int>? keyCount,
      Value<int>? mouseClicks,
      Value<int>? mouseMovePx,
      Value<int>? scrollPx,
      Value<String?>? keySequence,
      Value<bool>? isAuto,
      Value<String>? source}) {
    return ActivityRecordsCompanion(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      manualLabel: manualLabel ?? this.manualLabel,
      processName: processName ?? this.processName,
      windowTitle: windowTitle ?? this.windowTitle,
      packageName: packageName ?? this.packageName,
      category: category ?? this.category,
      appUsageRuleId: appUsageRuleId ?? this.appUsageRuleId,
      linkedTaskId: linkedTaskId ?? this.linkedTaskId,
      keyCount: keyCount ?? this.keyCount,
      mouseClicks: mouseClicks ?? this.mouseClicks,
      mouseMovePx: mouseMovePx ?? this.mouseMovePx,
      scrollPx: scrollPx ?? this.scrollPx,
      keySequence: keySequence ?? this.keySequence,
      isAuto: isAuto ?? this.isAuto,
      source: source ?? this.source,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<DateTime>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<DateTime>(endTime.value);
    }
    if (durationMinutes.present) {
      map['duration_minutes'] = Variable<int>(durationMinutes.value);
    }
    if (manualLabel.present) {
      map['manual_label'] = Variable<String>(manualLabel.value);
    }
    if (processName.present) {
      map['process_name'] = Variable<String>(processName.value);
    }
    if (windowTitle.present) {
      map['window_title'] = Variable<String>(windowTitle.value);
    }
    if (packageName.present) {
      map['package_name'] = Variable<String>(packageName.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (appUsageRuleId.present) {
      map['app_usage_rule_id'] = Variable<String>(appUsageRuleId.value);
    }
    if (linkedTaskId.present) {
      map['linked_task_id'] = Variable<int>(linkedTaskId.value);
    }
    if (keyCount.present) {
      map['key_count'] = Variable<int>(keyCount.value);
    }
    if (mouseClicks.present) {
      map['mouse_clicks'] = Variable<int>(mouseClicks.value);
    }
    if (mouseMovePx.present) {
      map['mouse_move_px'] = Variable<int>(mouseMovePx.value);
    }
    if (scrollPx.present) {
      map['scroll_px'] = Variable<int>(scrollPx.value);
    }
    if (keySequence.present) {
      map['key_sequence'] = Variable<String>(keySequence.value);
    }
    if (isAuto.present) {
      map['is_auto'] = Variable<bool>(isAuto.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivityRecordsCompanion(')
          ..write('id: $id, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('durationMinutes: $durationMinutes, ')
          ..write('manualLabel: $manualLabel, ')
          ..write('processName: $processName, ')
          ..write('windowTitle: $windowTitle, ')
          ..write('packageName: $packageName, ')
          ..write('category: $category, ')
          ..write('appUsageRuleId: $appUsageRuleId, ')
          ..write('linkedTaskId: $linkedTaskId, ')
          ..write('keyCount: $keyCount, ')
          ..write('mouseClicks: $mouseClicks, ')
          ..write('mouseMovePx: $mouseMovePx, ')
          ..write('scrollPx: $scrollPx, ')
          ..write('keySequence: $keySequence, ')
          ..write('isAuto: $isAuto, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }
}

class $AppUsageRulesTable extends AppUsageRules
    with TableInfo<$AppUsageRulesTable, AppUsageRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppUsageRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _processNameMeta =
      const VerificationMeta('processName');
  @override
  late final GeneratedColumn<String> processName = GeneratedColumn<String>(
      'process_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _windowTitlePatternMeta =
      const VerificationMeta('windowTitlePattern');
  @override
  late final GeneratedColumn<String> windowTitlePattern =
      GeneratedColumn<String>('window_title_pattern', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _customLabelMeta =
      const VerificationMeta('customLabel');
  @override
  late final GeneratedColumn<String> customLabel = GeneratedColumn<String>(
      'custom_label', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _hitCountMeta =
      const VerificationMeta('hitCount');
  @override
  late final GeneratedColumn<int> hitCount = GeneratedColumn<int>(
      'hit_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [id, processName, windowTitlePattern, category, customLabel, hitCount];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_usage_rules';
  @override
  VerificationContext validateIntegrity(Insertable<AppUsageRule> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('process_name')) {
      context.handle(
          _processNameMeta,
          processName.isAcceptableOrUnknown(
              data['process_name']!, _processNameMeta));
    } else if (isInserting) {
      context.missing(_processNameMeta);
    }
    if (data.containsKey('window_title_pattern')) {
      context.handle(
          _windowTitlePatternMeta,
          windowTitlePattern.isAcceptableOrUnknown(
              data['window_title_pattern']!, _windowTitlePatternMeta));
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('custom_label')) {
      context.handle(
          _customLabelMeta,
          customLabel.isAcceptableOrUnknown(
              data['custom_label']!, _customLabelMeta));
    }
    if (data.containsKey('hit_count')) {
      context.handle(_hitCountMeta,
          hitCount.isAcceptableOrUnknown(data['hit_count']!, _hitCountMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppUsageRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppUsageRule(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      processName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}process_name'])!,
      windowTitlePattern: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}window_title_pattern']),
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      customLabel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}custom_label']),
      hitCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}hit_count'])!,
    );
  }

  @override
  $AppUsageRulesTable createAlias(String alias) {
    return $AppUsageRulesTable(attachedDatabase, alias);
  }
}

class AppUsageRule extends DataClass implements Insertable<AppUsageRule> {
  final int id;
  final String processName;
  final String? windowTitlePattern;
  final String category;
  final String? customLabel;
  final int hitCount;
  const AppUsageRule(
      {required this.id,
      required this.processName,
      this.windowTitlePattern,
      required this.category,
      this.customLabel,
      required this.hitCount});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['process_name'] = Variable<String>(processName);
    if (!nullToAbsent || windowTitlePattern != null) {
      map['window_title_pattern'] = Variable<String>(windowTitlePattern);
    }
    map['category'] = Variable<String>(category);
    if (!nullToAbsent || customLabel != null) {
      map['custom_label'] = Variable<String>(customLabel);
    }
    map['hit_count'] = Variable<int>(hitCount);
    return map;
  }

  AppUsageRulesCompanion toCompanion(bool nullToAbsent) {
    return AppUsageRulesCompanion(
      id: Value(id),
      processName: Value(processName),
      windowTitlePattern: windowTitlePattern == null && nullToAbsent
          ? const Value.absent()
          : Value(windowTitlePattern),
      category: Value(category),
      customLabel: customLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(customLabel),
      hitCount: Value(hitCount),
    );
  }

  factory AppUsageRule.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppUsageRule(
      id: serializer.fromJson<int>(json['id']),
      processName: serializer.fromJson<String>(json['processName']),
      windowTitlePattern:
          serializer.fromJson<String?>(json['windowTitlePattern']),
      category: serializer.fromJson<String>(json['category']),
      customLabel: serializer.fromJson<String?>(json['customLabel']),
      hitCount: serializer.fromJson<int>(json['hitCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'processName': serializer.toJson<String>(processName),
      'windowTitlePattern': serializer.toJson<String?>(windowTitlePattern),
      'category': serializer.toJson<String>(category),
      'customLabel': serializer.toJson<String?>(customLabel),
      'hitCount': serializer.toJson<int>(hitCount),
    };
  }

  AppUsageRule copyWith(
          {int? id,
          String? processName,
          Value<String?> windowTitlePattern = const Value.absent(),
          String? category,
          Value<String?> customLabel = const Value.absent(),
          int? hitCount}) =>
      AppUsageRule(
        id: id ?? this.id,
        processName: processName ?? this.processName,
        windowTitlePattern: windowTitlePattern.present
            ? windowTitlePattern.value
            : this.windowTitlePattern,
        category: category ?? this.category,
        customLabel: customLabel.present ? customLabel.value : this.customLabel,
        hitCount: hitCount ?? this.hitCount,
      );
  AppUsageRule copyWithCompanion(AppUsageRulesCompanion data) {
    return AppUsageRule(
      id: data.id.present ? data.id.value : this.id,
      processName:
          data.processName.present ? data.processName.value : this.processName,
      windowTitlePattern: data.windowTitlePattern.present
          ? data.windowTitlePattern.value
          : this.windowTitlePattern,
      category: data.category.present ? data.category.value : this.category,
      customLabel:
          data.customLabel.present ? data.customLabel.value : this.customLabel,
      hitCount: data.hitCount.present ? data.hitCount.value : this.hitCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppUsageRule(')
          ..write('id: $id, ')
          ..write('processName: $processName, ')
          ..write('windowTitlePattern: $windowTitlePattern, ')
          ..write('category: $category, ')
          ..write('customLabel: $customLabel, ')
          ..write('hitCount: $hitCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, processName, windowTitlePattern, category, customLabel, hitCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppUsageRule &&
          other.id == this.id &&
          other.processName == this.processName &&
          other.windowTitlePattern == this.windowTitlePattern &&
          other.category == this.category &&
          other.customLabel == this.customLabel &&
          other.hitCount == this.hitCount);
}

class AppUsageRulesCompanion extends UpdateCompanion<AppUsageRule> {
  final Value<int> id;
  final Value<String> processName;
  final Value<String?> windowTitlePattern;
  final Value<String> category;
  final Value<String?> customLabel;
  final Value<int> hitCount;
  const AppUsageRulesCompanion({
    this.id = const Value.absent(),
    this.processName = const Value.absent(),
    this.windowTitlePattern = const Value.absent(),
    this.category = const Value.absent(),
    this.customLabel = const Value.absent(),
    this.hitCount = const Value.absent(),
  });
  AppUsageRulesCompanion.insert({
    this.id = const Value.absent(),
    required String processName,
    this.windowTitlePattern = const Value.absent(),
    required String category,
    this.customLabel = const Value.absent(),
    this.hitCount = const Value.absent(),
  })  : processName = Value(processName),
        category = Value(category);
  static Insertable<AppUsageRule> custom({
    Expression<int>? id,
    Expression<String>? processName,
    Expression<String>? windowTitlePattern,
    Expression<String>? category,
    Expression<String>? customLabel,
    Expression<int>? hitCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (processName != null) 'process_name': processName,
      if (windowTitlePattern != null)
        'window_title_pattern': windowTitlePattern,
      if (category != null) 'category': category,
      if (customLabel != null) 'custom_label': customLabel,
      if (hitCount != null) 'hit_count': hitCount,
    });
  }

  AppUsageRulesCompanion copyWith(
      {Value<int>? id,
      Value<String>? processName,
      Value<String?>? windowTitlePattern,
      Value<String>? category,
      Value<String?>? customLabel,
      Value<int>? hitCount}) {
    return AppUsageRulesCompanion(
      id: id ?? this.id,
      processName: processName ?? this.processName,
      windowTitlePattern: windowTitlePattern ?? this.windowTitlePattern,
      category: category ?? this.category,
      customLabel: customLabel ?? this.customLabel,
      hitCount: hitCount ?? this.hitCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (processName.present) {
      map['process_name'] = Variable<String>(processName.value);
    }
    if (windowTitlePattern.present) {
      map['window_title_pattern'] = Variable<String>(windowTitlePattern.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (customLabel.present) {
      map['custom_label'] = Variable<String>(customLabel.value);
    }
    if (hitCount.present) {
      map['hit_count'] = Variable<int>(hitCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppUsageRulesCompanion(')
          ..write('id: $id, ')
          ..write('processName: $processName, ')
          ..write('windowTitlePattern: $windowTitlePattern, ')
          ..write('category: $category, ')
          ..write('customLabel: $customLabel, ')
          ..write('hitCount: $hitCount')
          ..write(')'))
        .toString();
  }
}

class $EventCalendarsTable extends EventCalendars
    with TableInfo<$EventCalendarsTable, EventCalendar> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventCalendarsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _colorHexMeta =
      const VerificationMeta('colorHex');
  @override
  late final GeneratedColumn<String> colorHex = GeneratedColumn<String>(
      'color_hex', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('#6B5EE4'));
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isVisibleMeta =
      const VerificationMeta('isVisible');
  @override
  late final GeneratedColumn<bool> isVisible = GeneratedColumn<bool>(
      'is_visible', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_visible" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _isDefaultMeta =
      const VerificationMeta('isDefault');
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
      'is_default', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_default" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
      'source', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('local'));
  static const VerificationMeta _syncUrlMeta =
      const VerificationMeta('syncUrl');
  @override
  late final GeneratedColumn<String> syncUrl = GeneratedColumn<String>(
      'sync_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        colorHex,
        description,
        isVisible,
        isDefault,
        source,
        syncUrl,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'event_calendars';
  @override
  VerificationContext validateIntegrity(Insertable<EventCalendar> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_hex')) {
      context.handle(_colorHexMeta,
          colorHex.isAcceptableOrUnknown(data['color_hex']!, _colorHexMeta));
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('is_visible')) {
      context.handle(_isVisibleMeta,
          isVisible.isAcceptableOrUnknown(data['is_visible']!, _isVisibleMeta));
    }
    if (data.containsKey('is_default')) {
      context.handle(_isDefaultMeta,
          isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta));
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    }
    if (data.containsKey('sync_url')) {
      context.handle(_syncUrlMeta,
          syncUrl.isAcceptableOrUnknown(data['sync_url']!, _syncUrlMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EventCalendar map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EventCalendar(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      colorHex: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}color_hex'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      isVisible: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_visible'])!,
      isDefault: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_default'])!,
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source'])!,
      syncUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_url']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $EventCalendarsTable createAlias(String alias) {
    return $EventCalendarsTable(attachedDatabase, alias);
  }
}

class EventCalendar extends DataClass implements Insertable<EventCalendar> {
  final int id;
  final String name;
  final String colorHex;
  final String? description;
  final bool isVisible;
  final bool isDefault;
  final String source;
  final String? syncUrl;
  final DateTime createdAt;
  const EventCalendar(
      {required this.id,
      required this.name,
      required this.colorHex,
      this.description,
      required this.isVisible,
      required this.isDefault,
      required this.source,
      this.syncUrl,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['color_hex'] = Variable<String>(colorHex);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['is_visible'] = Variable<bool>(isVisible);
    map['is_default'] = Variable<bool>(isDefault);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || syncUrl != null) {
      map['sync_url'] = Variable<String>(syncUrl);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  EventCalendarsCompanion toCompanion(bool nullToAbsent) {
    return EventCalendarsCompanion(
      id: Value(id),
      name: Value(name),
      colorHex: Value(colorHex),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      isVisible: Value(isVisible),
      isDefault: Value(isDefault),
      source: Value(source),
      syncUrl: syncUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(syncUrl),
      createdAt: Value(createdAt),
    );
  }

  factory EventCalendar.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EventCalendar(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      colorHex: serializer.fromJson<String>(json['colorHex']),
      description: serializer.fromJson<String?>(json['description']),
      isVisible: serializer.fromJson<bool>(json['isVisible']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      source: serializer.fromJson<String>(json['source']),
      syncUrl: serializer.fromJson<String?>(json['syncUrl']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'colorHex': serializer.toJson<String>(colorHex),
      'description': serializer.toJson<String?>(description),
      'isVisible': serializer.toJson<bool>(isVisible),
      'isDefault': serializer.toJson<bool>(isDefault),
      'source': serializer.toJson<String>(source),
      'syncUrl': serializer.toJson<String?>(syncUrl),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  EventCalendar copyWith(
          {int? id,
          String? name,
          String? colorHex,
          Value<String?> description = const Value.absent(),
          bool? isVisible,
          bool? isDefault,
          String? source,
          Value<String?> syncUrl = const Value.absent(),
          DateTime? createdAt}) =>
      EventCalendar(
        id: id ?? this.id,
        name: name ?? this.name,
        colorHex: colorHex ?? this.colorHex,
        description: description.present ? description.value : this.description,
        isVisible: isVisible ?? this.isVisible,
        isDefault: isDefault ?? this.isDefault,
        source: source ?? this.source,
        syncUrl: syncUrl.present ? syncUrl.value : this.syncUrl,
        createdAt: createdAt ?? this.createdAt,
      );
  EventCalendar copyWithCompanion(EventCalendarsCompanion data) {
    return EventCalendar(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      colorHex: data.colorHex.present ? data.colorHex.value : this.colorHex,
      description:
          data.description.present ? data.description.value : this.description,
      isVisible: data.isVisible.present ? data.isVisible.value : this.isVisible,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      source: data.source.present ? data.source.value : this.source,
      syncUrl: data.syncUrl.present ? data.syncUrl.value : this.syncUrl,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EventCalendar(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorHex: $colorHex, ')
          ..write('description: $description, ')
          ..write('isVisible: $isVisible, ')
          ..write('isDefault: $isDefault, ')
          ..write('source: $source, ')
          ..write('syncUrl: $syncUrl, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, colorHex, description, isVisible,
      isDefault, source, syncUrl, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventCalendar &&
          other.id == this.id &&
          other.name == this.name &&
          other.colorHex == this.colorHex &&
          other.description == this.description &&
          other.isVisible == this.isVisible &&
          other.isDefault == this.isDefault &&
          other.source == this.source &&
          other.syncUrl == this.syncUrl &&
          other.createdAt == this.createdAt);
}

class EventCalendarsCompanion extends UpdateCompanion<EventCalendar> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> colorHex;
  final Value<String?> description;
  final Value<bool> isVisible;
  final Value<bool> isDefault;
  final Value<String> source;
  final Value<String?> syncUrl;
  final Value<DateTime> createdAt;
  const EventCalendarsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.description = const Value.absent(),
    this.isVisible = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.source = const Value.absent(),
    this.syncUrl = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  EventCalendarsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.colorHex = const Value.absent(),
    this.description = const Value.absent(),
    this.isVisible = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.source = const Value.absent(),
    this.syncUrl = const Value.absent(),
    required DateTime createdAt,
  })  : name = Value(name),
        createdAt = Value(createdAt);
  static Insertable<EventCalendar> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? colorHex,
    Expression<String>? description,
    Expression<bool>? isVisible,
    Expression<bool>? isDefault,
    Expression<String>? source,
    Expression<String>? syncUrl,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (colorHex != null) 'color_hex': colorHex,
      if (description != null) 'description': description,
      if (isVisible != null) 'is_visible': isVisible,
      if (isDefault != null) 'is_default': isDefault,
      if (source != null) 'source': source,
      if (syncUrl != null) 'sync_url': syncUrl,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  EventCalendarsCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<String>? colorHex,
      Value<String?>? description,
      Value<bool>? isVisible,
      Value<bool>? isDefault,
      Value<String>? source,
      Value<String?>? syncUrl,
      Value<DateTime>? createdAt}) {
    return EventCalendarsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      description: description ?? this.description,
      isVisible: isVisible ?? this.isVisible,
      isDefault: isDefault ?? this.isDefault,
      source: source ?? this.source,
      syncUrl: syncUrl ?? this.syncUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorHex.present) {
      map['color_hex'] = Variable<String>(colorHex.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (isVisible.present) {
      map['is_visible'] = Variable<bool>(isVisible.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (syncUrl.present) {
      map['sync_url'] = Variable<String>(syncUrl.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventCalendarsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorHex: $colorHex, ')
          ..write('description: $description, ')
          ..write('isVisible: $isVisible, ')
          ..write('isDefault: $isDefault, ')
          ..write('source: $source, ')
          ..write('syncUrl: $syncUrl, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $TaskListsTable extends TaskLists
    with TableInfo<$TaskListsTable, TaskList> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskListsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _colorHexMeta =
      const VerificationMeta('colorHex');
  @override
  late final GeneratedColumn<String> colorHex = GeneratedColumn<String>(
      'color_hex', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('#0EA8A0'));
  static const VerificationMeta _emojiMeta = const VerificationMeta('emoji');
  @override
  late final GeneratedColumn<String> emoji = GeneratedColumn<String>(
      'emoji', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isVisibleMeta =
      const VerificationMeta('isVisible');
  @override
  late final GeneratedColumn<bool> isVisible = GeneratedColumn<bool>(
      'is_visible', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_visible" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _isDefaultMeta =
      const VerificationMeta('isDefault');
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
      'is_default', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_default" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isArchivedMeta =
      const VerificationMeta('isArchived');
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
      'is_archived', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_archived" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, colorHex, emoji, isVisible, isDefault, isArchived, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_lists';
  @override
  VerificationContext validateIntegrity(Insertable<TaskList> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_hex')) {
      context.handle(_colorHexMeta,
          colorHex.isAcceptableOrUnknown(data['color_hex']!, _colorHexMeta));
    }
    if (data.containsKey('emoji')) {
      context.handle(
          _emojiMeta, emoji.isAcceptableOrUnknown(data['emoji']!, _emojiMeta));
    }
    if (data.containsKey('is_visible')) {
      context.handle(_isVisibleMeta,
          isVisible.isAcceptableOrUnknown(data['is_visible']!, _isVisibleMeta));
    }
    if (data.containsKey('is_default')) {
      context.handle(_isDefaultMeta,
          isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta));
    }
    if (data.containsKey('is_archived')) {
      context.handle(
          _isArchivedMeta,
          isArchived.isAcceptableOrUnknown(
              data['is_archived']!, _isArchivedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskList map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskList(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      colorHex: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}color_hex'])!,
      emoji: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}emoji']),
      isVisible: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_visible'])!,
      isDefault: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_default'])!,
      isArchived: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_archived'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $TaskListsTable createAlias(String alias) {
    return $TaskListsTable(attachedDatabase, alias);
  }
}

class TaskList extends DataClass implements Insertable<TaskList> {
  final int id;
  final String name;
  final String colorHex;
  final String? emoji;
  final bool isVisible;
  final bool isDefault;
  final bool isArchived;
  final DateTime createdAt;
  const TaskList(
      {required this.id,
      required this.name,
      required this.colorHex,
      this.emoji,
      required this.isVisible,
      required this.isDefault,
      required this.isArchived,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['color_hex'] = Variable<String>(colorHex);
    if (!nullToAbsent || emoji != null) {
      map['emoji'] = Variable<String>(emoji);
    }
    map['is_visible'] = Variable<bool>(isVisible);
    map['is_default'] = Variable<bool>(isDefault);
    map['is_archived'] = Variable<bool>(isArchived);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TaskListsCompanion toCompanion(bool nullToAbsent) {
    return TaskListsCompanion(
      id: Value(id),
      name: Value(name),
      colorHex: Value(colorHex),
      emoji:
          emoji == null && nullToAbsent ? const Value.absent() : Value(emoji),
      isVisible: Value(isVisible),
      isDefault: Value(isDefault),
      isArchived: Value(isArchived),
      createdAt: Value(createdAt),
    );
  }

  factory TaskList.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskList(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      colorHex: serializer.fromJson<String>(json['colorHex']),
      emoji: serializer.fromJson<String?>(json['emoji']),
      isVisible: serializer.fromJson<bool>(json['isVisible']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'colorHex': serializer.toJson<String>(colorHex),
      'emoji': serializer.toJson<String?>(emoji),
      'isVisible': serializer.toJson<bool>(isVisible),
      'isDefault': serializer.toJson<bool>(isDefault),
      'isArchived': serializer.toJson<bool>(isArchived),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  TaskList copyWith(
          {int? id,
          String? name,
          String? colorHex,
          Value<String?> emoji = const Value.absent(),
          bool? isVisible,
          bool? isDefault,
          bool? isArchived,
          DateTime? createdAt}) =>
      TaskList(
        id: id ?? this.id,
        name: name ?? this.name,
        colorHex: colorHex ?? this.colorHex,
        emoji: emoji.present ? emoji.value : this.emoji,
        isVisible: isVisible ?? this.isVisible,
        isDefault: isDefault ?? this.isDefault,
        isArchived: isArchived ?? this.isArchived,
        createdAt: createdAt ?? this.createdAt,
      );
  TaskList copyWithCompanion(TaskListsCompanion data) {
    return TaskList(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      colorHex: data.colorHex.present ? data.colorHex.value : this.colorHex,
      emoji: data.emoji.present ? data.emoji.value : this.emoji,
      isVisible: data.isVisible.present ? data.isVisible.value : this.isVisible,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      isArchived:
          data.isArchived.present ? data.isArchived.value : this.isArchived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskList(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorHex: $colorHex, ')
          ..write('emoji: $emoji, ')
          ..write('isVisible: $isVisible, ')
          ..write('isDefault: $isDefault, ')
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, name, colorHex, emoji, isVisible, isDefault, isArchived, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskList &&
          other.id == this.id &&
          other.name == this.name &&
          other.colorHex == this.colorHex &&
          other.emoji == this.emoji &&
          other.isVisible == this.isVisible &&
          other.isDefault == this.isDefault &&
          other.isArchived == this.isArchived &&
          other.createdAt == this.createdAt);
}

class TaskListsCompanion extends UpdateCompanion<TaskList> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> colorHex;
  final Value<String?> emoji;
  final Value<bool> isVisible;
  final Value<bool> isDefault;
  final Value<bool> isArchived;
  final Value<DateTime> createdAt;
  const TaskListsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.emoji = const Value.absent(),
    this.isVisible = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  TaskListsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.colorHex = const Value.absent(),
    this.emoji = const Value.absent(),
    this.isVisible = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.isArchived = const Value.absent(),
    required DateTime createdAt,
  })  : name = Value(name),
        createdAt = Value(createdAt);
  static Insertable<TaskList> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? colorHex,
    Expression<String>? emoji,
    Expression<bool>? isVisible,
    Expression<bool>? isDefault,
    Expression<bool>? isArchived,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (colorHex != null) 'color_hex': colorHex,
      if (emoji != null) 'emoji': emoji,
      if (isVisible != null) 'is_visible': isVisible,
      if (isDefault != null) 'is_default': isDefault,
      if (isArchived != null) 'is_archived': isArchived,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  TaskListsCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<String>? colorHex,
      Value<String?>? emoji,
      Value<bool>? isVisible,
      Value<bool>? isDefault,
      Value<bool>? isArchived,
      Value<DateTime>? createdAt}) {
    return TaskListsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      emoji: emoji ?? this.emoji,
      isVisible: isVisible ?? this.isVisible,
      isDefault: isDefault ?? this.isDefault,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorHex.present) {
      map['color_hex'] = Variable<String>(colorHex.value);
    }
    if (emoji.present) {
      map['emoji'] = Variable<String>(emoji.value);
    }
    if (isVisible.present) {
      map['is_visible'] = Variable<bool>(isVisible.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskListsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorHex: $colorHex, ')
          ..write('emoji: $emoji, ')
          ..write('isVisible: $isVisible, ')
          ..write('isDefault: $isDefault, ')
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TaskItemsTable taskItems = $TaskItemsTable(this);
  late final $CalendarEventsTable calendarEvents = $CalendarEventsTable(this);
  late final $TimeBlocksTable timeBlocks = $TimeBlocksTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $ProjectsTable projects = $ProjectsTable(this);
  late final $ActivityRecordsTable activityRecords =
      $ActivityRecordsTable(this);
  late final $AppUsageRulesTable appUsageRules = $AppUsageRulesTable(this);
  late final $EventCalendarsTable eventCalendars = $EventCalendarsTable(this);
  late final $TaskListsTable taskLists = $TaskListsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        taskItems,
        calendarEvents,
        timeBlocks,
        tags,
        projects,
        activityRecords,
        appUsageRules,
        eventCalendars,
        taskLists
      ];
}

typedef $$TaskItemsTableCreateCompanionBuilder = TaskItemsCompanion Function({
  Value<int> id,
  required String uid,
  required DateTime dtstamp,
  required String summary,
  Value<String?> description,
  Value<String?> location,
  Value<DateTime?> dtstart,
  Value<DateTime?> due,
  Value<DateTime?> completed,
  Value<int> priority,
  Value<String> status,
  Value<int> percentComplete,
  Value<String> categories,
  Value<String?> rrule,
  Value<int> durationMinutes,
  Value<bool> isSplittable,
  Value<int> priorityLocal,
  Value<bool> isAutoScheduled,
  Value<int?> taskListId,
  Value<String?> tagId,
  Value<bool> isLocked,
  Value<int> reminderMinutesBefore,
});
typedef $$TaskItemsTableUpdateCompanionBuilder = TaskItemsCompanion Function({
  Value<int> id,
  Value<String> uid,
  Value<DateTime> dtstamp,
  Value<String> summary,
  Value<String?> description,
  Value<String?> location,
  Value<DateTime?> dtstart,
  Value<DateTime?> due,
  Value<DateTime?> completed,
  Value<int> priority,
  Value<String> status,
  Value<int> percentComplete,
  Value<String> categories,
  Value<String?> rrule,
  Value<int> durationMinutes,
  Value<bool> isSplittable,
  Value<int> priorityLocal,
  Value<bool> isAutoScheduled,
  Value<int?> taskListId,
  Value<String?> tagId,
  Value<bool> isLocked,
  Value<int> reminderMinutesBefore,
});

class $$TaskItemsTableFilterComposer
    extends Composer<_$AppDatabase, $TaskItemsTable> {
  $$TaskItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get uid => $composableBuilder(
      column: $table.uid, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get dtstamp => $composableBuilder(
      column: $table.dtstamp, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get summary => $composableBuilder(
      column: $table.summary, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get location => $composableBuilder(
      column: $table.location, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get dtstart => $composableBuilder(
      column: $table.dtstart, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get due => $composableBuilder(
      column: $table.due, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get completed => $composableBuilder(
      column: $table.completed, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get percentComplete => $composableBuilder(
      column: $table.percentComplete,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get categories => $composableBuilder(
      column: $table.categories, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rrule => $composableBuilder(
      column: $table.rrule, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMinutes => $composableBuilder(
      column: $table.durationMinutes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSplittable => $composableBuilder(
      column: $table.isSplittable, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get priorityLocal => $composableBuilder(
      column: $table.priorityLocal, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isAutoScheduled => $composableBuilder(
      column: $table.isAutoScheduled,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get taskListId => $composableBuilder(
      column: $table.taskListId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tagId => $composableBuilder(
      column: $table.tagId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isLocked => $composableBuilder(
      column: $table.isLocked, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get reminderMinutesBefore => $composableBuilder(
      column: $table.reminderMinutesBefore,
      builder: (column) => ColumnFilters(column));
}

class $$TaskItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskItemsTable> {
  $$TaskItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get uid => $composableBuilder(
      column: $table.uid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get dtstamp => $composableBuilder(
      column: $table.dtstamp, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get summary => $composableBuilder(
      column: $table.summary, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get location => $composableBuilder(
      column: $table.location, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get dtstart => $composableBuilder(
      column: $table.dtstart, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get due => $composableBuilder(
      column: $table.due, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get completed => $composableBuilder(
      column: $table.completed, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get percentComplete => $composableBuilder(
      column: $table.percentComplete,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get categories => $composableBuilder(
      column: $table.categories, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rrule => $composableBuilder(
      column: $table.rrule, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMinutes => $composableBuilder(
      column: $table.durationMinutes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSplittable => $composableBuilder(
      column: $table.isSplittable,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get priorityLocal => $composableBuilder(
      column: $table.priorityLocal,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isAutoScheduled => $composableBuilder(
      column: $table.isAutoScheduled,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get taskListId => $composableBuilder(
      column: $table.taskListId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tagId => $composableBuilder(
      column: $table.tagId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isLocked => $composableBuilder(
      column: $table.isLocked, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get reminderMinutesBefore => $composableBuilder(
      column: $table.reminderMinutesBefore,
      builder: (column) => ColumnOrderings(column));
}

class $$TaskItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskItemsTable> {
  $$TaskItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uid =>
      $composableBuilder(column: $table.uid, builder: (column) => column);

  GeneratedColumn<DateTime> get dtstamp =>
      $composableBuilder(column: $table.dtstamp, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<DateTime> get dtstart =>
      $composableBuilder(column: $table.dtstart, builder: (column) => column);

  GeneratedColumn<DateTime> get due =>
      $composableBuilder(column: $table.due, builder: (column) => column);

  GeneratedColumn<DateTime> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get percentComplete => $composableBuilder(
      column: $table.percentComplete, builder: (column) => column);

  GeneratedColumn<String> get categories => $composableBuilder(
      column: $table.categories, builder: (column) => column);

  GeneratedColumn<String> get rrule =>
      $composableBuilder(column: $table.rrule, builder: (column) => column);

  GeneratedColumn<int> get durationMinutes => $composableBuilder(
      column: $table.durationMinutes, builder: (column) => column);

  GeneratedColumn<bool> get isSplittable => $composableBuilder(
      column: $table.isSplittable, builder: (column) => column);

  GeneratedColumn<int> get priorityLocal => $composableBuilder(
      column: $table.priorityLocal, builder: (column) => column);

  GeneratedColumn<bool> get isAutoScheduled => $composableBuilder(
      column: $table.isAutoScheduled, builder: (column) => column);

  GeneratedColumn<int> get taskListId => $composableBuilder(
      column: $table.taskListId, builder: (column) => column);

  GeneratedColumn<String> get tagId =>
      $composableBuilder(column: $table.tagId, builder: (column) => column);

  GeneratedColumn<bool> get isLocked =>
      $composableBuilder(column: $table.isLocked, builder: (column) => column);

  GeneratedColumn<int> get reminderMinutesBefore => $composableBuilder(
      column: $table.reminderMinutesBefore, builder: (column) => column);
}

class $$TaskItemsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TaskItemsTable,
    TaskItem,
    $$TaskItemsTableFilterComposer,
    $$TaskItemsTableOrderingComposer,
    $$TaskItemsTableAnnotationComposer,
    $$TaskItemsTableCreateCompanionBuilder,
    $$TaskItemsTableUpdateCompanionBuilder,
    (TaskItem, BaseReferences<_$AppDatabase, $TaskItemsTable, TaskItem>),
    TaskItem,
    PrefetchHooks Function()> {
  $$TaskItemsTableTableManager(_$AppDatabase db, $TaskItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> uid = const Value.absent(),
            Value<DateTime> dtstamp = const Value.absent(),
            Value<String> summary = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String?> location = const Value.absent(),
            Value<DateTime?> dtstart = const Value.absent(),
            Value<DateTime?> due = const Value.absent(),
            Value<DateTime?> completed = const Value.absent(),
            Value<int> priority = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> percentComplete = const Value.absent(),
            Value<String> categories = const Value.absent(),
            Value<String?> rrule = const Value.absent(),
            Value<int> durationMinutes = const Value.absent(),
            Value<bool> isSplittable = const Value.absent(),
            Value<int> priorityLocal = const Value.absent(),
            Value<bool> isAutoScheduled = const Value.absent(),
            Value<int?> taskListId = const Value.absent(),
            Value<String?> tagId = const Value.absent(),
            Value<bool> isLocked = const Value.absent(),
            Value<int> reminderMinutesBefore = const Value.absent(),
          }) =>
              TaskItemsCompanion(
            id: id,
            uid: uid,
            dtstamp: dtstamp,
            summary: summary,
            description: description,
            location: location,
            dtstart: dtstart,
            due: due,
            completed: completed,
            priority: priority,
            status: status,
            percentComplete: percentComplete,
            categories: categories,
            rrule: rrule,
            durationMinutes: durationMinutes,
            isSplittable: isSplittable,
            priorityLocal: priorityLocal,
            isAutoScheduled: isAutoScheduled,
            taskListId: taskListId,
            tagId: tagId,
            isLocked: isLocked,
            reminderMinutesBefore: reminderMinutesBefore,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String uid,
            required DateTime dtstamp,
            required String summary,
            Value<String?> description = const Value.absent(),
            Value<String?> location = const Value.absent(),
            Value<DateTime?> dtstart = const Value.absent(),
            Value<DateTime?> due = const Value.absent(),
            Value<DateTime?> completed = const Value.absent(),
            Value<int> priority = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> percentComplete = const Value.absent(),
            Value<String> categories = const Value.absent(),
            Value<String?> rrule = const Value.absent(),
            Value<int> durationMinutes = const Value.absent(),
            Value<bool> isSplittable = const Value.absent(),
            Value<int> priorityLocal = const Value.absent(),
            Value<bool> isAutoScheduled = const Value.absent(),
            Value<int?> taskListId = const Value.absent(),
            Value<String?> tagId = const Value.absent(),
            Value<bool> isLocked = const Value.absent(),
            Value<int> reminderMinutesBefore = const Value.absent(),
          }) =>
              TaskItemsCompanion.insert(
            id: id,
            uid: uid,
            dtstamp: dtstamp,
            summary: summary,
            description: description,
            location: location,
            dtstart: dtstart,
            due: due,
            completed: completed,
            priority: priority,
            status: status,
            percentComplete: percentComplete,
            categories: categories,
            rrule: rrule,
            durationMinutes: durationMinutes,
            isSplittable: isSplittable,
            priorityLocal: priorityLocal,
            isAutoScheduled: isAutoScheduled,
            taskListId: taskListId,
            tagId: tagId,
            isLocked: isLocked,
            reminderMinutesBefore: reminderMinutesBefore,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TaskItemsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TaskItemsTable,
    TaskItem,
    $$TaskItemsTableFilterComposer,
    $$TaskItemsTableOrderingComposer,
    $$TaskItemsTableAnnotationComposer,
    $$TaskItemsTableCreateCompanionBuilder,
    $$TaskItemsTableUpdateCompanionBuilder,
    (TaskItem, BaseReferences<_$AppDatabase, $TaskItemsTable, TaskItem>),
    TaskItem,
    PrefetchHooks Function()>;
typedef $$CalendarEventsTableCreateCompanionBuilder = CalendarEventsCompanion
    Function({
  Value<int> id,
  required String uid,
  required DateTime dtstamp,
  required String summary,
  Value<String?> description,
  Value<String?> location,
  required DateTime dtstart,
  Value<DateTime?> dtend,
  Value<String?> rrule,
  Value<String> status,
  Value<String> transp,
  Value<String> source,
  Value<int?> eventCalendarId,
  Value<String> colorHex,
  Value<bool> isBlock,
});
typedef $$CalendarEventsTableUpdateCompanionBuilder = CalendarEventsCompanion
    Function({
  Value<int> id,
  Value<String> uid,
  Value<DateTime> dtstamp,
  Value<String> summary,
  Value<String?> description,
  Value<String?> location,
  Value<DateTime> dtstart,
  Value<DateTime?> dtend,
  Value<String?> rrule,
  Value<String> status,
  Value<String> transp,
  Value<String> source,
  Value<int?> eventCalendarId,
  Value<String> colorHex,
  Value<bool> isBlock,
});

class $$CalendarEventsTableFilterComposer
    extends Composer<_$AppDatabase, $CalendarEventsTable> {
  $$CalendarEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get uid => $composableBuilder(
      column: $table.uid, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get dtstamp => $composableBuilder(
      column: $table.dtstamp, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get summary => $composableBuilder(
      column: $table.summary, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get location => $composableBuilder(
      column: $table.location, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get dtstart => $composableBuilder(
      column: $table.dtstart, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get dtend => $composableBuilder(
      column: $table.dtend, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rrule => $composableBuilder(
      column: $table.rrule, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get transp => $composableBuilder(
      column: $table.transp, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get eventCalendarId => $composableBuilder(
      column: $table.eventCalendarId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get colorHex => $composableBuilder(
      column: $table.colorHex, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isBlock => $composableBuilder(
      column: $table.isBlock, builder: (column) => ColumnFilters(column));
}

class $$CalendarEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $CalendarEventsTable> {
  $$CalendarEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get uid => $composableBuilder(
      column: $table.uid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get dtstamp => $composableBuilder(
      column: $table.dtstamp, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get summary => $composableBuilder(
      column: $table.summary, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get location => $composableBuilder(
      column: $table.location, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get dtstart => $composableBuilder(
      column: $table.dtstart, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get dtend => $composableBuilder(
      column: $table.dtend, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rrule => $composableBuilder(
      column: $table.rrule, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get transp => $composableBuilder(
      column: $table.transp, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get eventCalendarId => $composableBuilder(
      column: $table.eventCalendarId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get colorHex => $composableBuilder(
      column: $table.colorHex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isBlock => $composableBuilder(
      column: $table.isBlock, builder: (column) => ColumnOrderings(column));
}

class $$CalendarEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CalendarEventsTable> {
  $$CalendarEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uid =>
      $composableBuilder(column: $table.uid, builder: (column) => column);

  GeneratedColumn<DateTime> get dtstamp =>
      $composableBuilder(column: $table.dtstamp, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<DateTime> get dtstart =>
      $composableBuilder(column: $table.dtstart, builder: (column) => column);

  GeneratedColumn<DateTime> get dtend =>
      $composableBuilder(column: $table.dtend, builder: (column) => column);

  GeneratedColumn<String> get rrule =>
      $composableBuilder(column: $table.rrule, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get transp =>
      $composableBuilder(column: $table.transp, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<int> get eventCalendarId => $composableBuilder(
      column: $table.eventCalendarId, builder: (column) => column);

  GeneratedColumn<String> get colorHex =>
      $composableBuilder(column: $table.colorHex, builder: (column) => column);

  GeneratedColumn<bool> get isBlock =>
      $composableBuilder(column: $table.isBlock, builder: (column) => column);
}

class $$CalendarEventsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CalendarEventsTable,
    CalendarEvent,
    $$CalendarEventsTableFilterComposer,
    $$CalendarEventsTableOrderingComposer,
    $$CalendarEventsTableAnnotationComposer,
    $$CalendarEventsTableCreateCompanionBuilder,
    $$CalendarEventsTableUpdateCompanionBuilder,
    (
      CalendarEvent,
      BaseReferences<_$AppDatabase, $CalendarEventsTable, CalendarEvent>
    ),
    CalendarEvent,
    PrefetchHooks Function()> {
  $$CalendarEventsTableTableManager(
      _$AppDatabase db, $CalendarEventsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CalendarEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CalendarEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CalendarEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> uid = const Value.absent(),
            Value<DateTime> dtstamp = const Value.absent(),
            Value<String> summary = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String?> location = const Value.absent(),
            Value<DateTime> dtstart = const Value.absent(),
            Value<DateTime?> dtend = const Value.absent(),
            Value<String?> rrule = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> transp = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<int?> eventCalendarId = const Value.absent(),
            Value<String> colorHex = const Value.absent(),
            Value<bool> isBlock = const Value.absent(),
          }) =>
              CalendarEventsCompanion(
            id: id,
            uid: uid,
            dtstamp: dtstamp,
            summary: summary,
            description: description,
            location: location,
            dtstart: dtstart,
            dtend: dtend,
            rrule: rrule,
            status: status,
            transp: transp,
            source: source,
            eventCalendarId: eventCalendarId,
            colorHex: colorHex,
            isBlock: isBlock,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String uid,
            required DateTime dtstamp,
            required String summary,
            Value<String?> description = const Value.absent(),
            Value<String?> location = const Value.absent(),
            required DateTime dtstart,
            Value<DateTime?> dtend = const Value.absent(),
            Value<String?> rrule = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> transp = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<int?> eventCalendarId = const Value.absent(),
            Value<String> colorHex = const Value.absent(),
            Value<bool> isBlock = const Value.absent(),
          }) =>
              CalendarEventsCompanion.insert(
            id: id,
            uid: uid,
            dtstamp: dtstamp,
            summary: summary,
            description: description,
            location: location,
            dtstart: dtstart,
            dtend: dtend,
            rrule: rrule,
            status: status,
            transp: transp,
            source: source,
            eventCalendarId: eventCalendarId,
            colorHex: colorHex,
            isBlock: isBlock,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CalendarEventsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CalendarEventsTable,
    CalendarEvent,
    $$CalendarEventsTableFilterComposer,
    $$CalendarEventsTableOrderingComposer,
    $$CalendarEventsTableAnnotationComposer,
    $$CalendarEventsTableCreateCompanionBuilder,
    $$CalendarEventsTableUpdateCompanionBuilder,
    (
      CalendarEvent,
      BaseReferences<_$AppDatabase, $CalendarEventsTable, CalendarEvent>
    ),
    CalendarEvent,
    PrefetchHooks Function()>;
typedef $$TimeBlocksTableCreateCompanionBuilder = TimeBlocksCompanion Function({
  Value<int> id,
  required String name,
  required int startHour,
  Value<int> startMinute,
  required int endHour,
  Value<int> endMinute,
  Value<String> weekdays,
  Value<bool> isActive,
  Value<String> colorHex,
  Value<String> emoji,
});
typedef $$TimeBlocksTableUpdateCompanionBuilder = TimeBlocksCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<int> startHour,
  Value<int> startMinute,
  Value<int> endHour,
  Value<int> endMinute,
  Value<String> weekdays,
  Value<bool> isActive,
  Value<String> colorHex,
  Value<String> emoji,
});

class $$TimeBlocksTableFilterComposer
    extends Composer<_$AppDatabase, $TimeBlocksTable> {
  $$TimeBlocksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startHour => $composableBuilder(
      column: $table.startHour, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startMinute => $composableBuilder(
      column: $table.startMinute, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get endHour => $composableBuilder(
      column: $table.endHour, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get endMinute => $composableBuilder(
      column: $table.endMinute, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get weekdays => $composableBuilder(
      column: $table.weekdays, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get colorHex => $composableBuilder(
      column: $table.colorHex, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get emoji => $composableBuilder(
      column: $table.emoji, builder: (column) => ColumnFilters(column));
}

class $$TimeBlocksTableOrderingComposer
    extends Composer<_$AppDatabase, $TimeBlocksTable> {
  $$TimeBlocksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startHour => $composableBuilder(
      column: $table.startHour, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startMinute => $composableBuilder(
      column: $table.startMinute, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get endHour => $composableBuilder(
      column: $table.endHour, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get endMinute => $composableBuilder(
      column: $table.endMinute, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get weekdays => $composableBuilder(
      column: $table.weekdays, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get colorHex => $composableBuilder(
      column: $table.colorHex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get emoji => $composableBuilder(
      column: $table.emoji, builder: (column) => ColumnOrderings(column));
}

class $$TimeBlocksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TimeBlocksTable> {
  $$TimeBlocksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get startHour =>
      $composableBuilder(column: $table.startHour, builder: (column) => column);

  GeneratedColumn<int> get startMinute => $composableBuilder(
      column: $table.startMinute, builder: (column) => column);

  GeneratedColumn<int> get endHour =>
      $composableBuilder(column: $table.endHour, builder: (column) => column);

  GeneratedColumn<int> get endMinute =>
      $composableBuilder(column: $table.endMinute, builder: (column) => column);

  GeneratedColumn<String> get weekdays =>
      $composableBuilder(column: $table.weekdays, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<String> get colorHex =>
      $composableBuilder(column: $table.colorHex, builder: (column) => column);

  GeneratedColumn<String> get emoji =>
      $composableBuilder(column: $table.emoji, builder: (column) => column);
}

class $$TimeBlocksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TimeBlocksTable,
    TimeBlock,
    $$TimeBlocksTableFilterComposer,
    $$TimeBlocksTableOrderingComposer,
    $$TimeBlocksTableAnnotationComposer,
    $$TimeBlocksTableCreateCompanionBuilder,
    $$TimeBlocksTableUpdateCompanionBuilder,
    (TimeBlock, BaseReferences<_$AppDatabase, $TimeBlocksTable, TimeBlock>),
    TimeBlock,
    PrefetchHooks Function()> {
  $$TimeBlocksTableTableManager(_$AppDatabase db, $TimeBlocksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TimeBlocksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TimeBlocksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TimeBlocksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> startHour = const Value.absent(),
            Value<int> startMinute = const Value.absent(),
            Value<int> endHour = const Value.absent(),
            Value<int> endMinute = const Value.absent(),
            Value<String> weekdays = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<String> colorHex = const Value.absent(),
            Value<String> emoji = const Value.absent(),
          }) =>
              TimeBlocksCompanion(
            id: id,
            name: name,
            startHour: startHour,
            startMinute: startMinute,
            endHour: endHour,
            endMinute: endMinute,
            weekdays: weekdays,
            isActive: isActive,
            colorHex: colorHex,
            emoji: emoji,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            required int startHour,
            Value<int> startMinute = const Value.absent(),
            required int endHour,
            Value<int> endMinute = const Value.absent(),
            Value<String> weekdays = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<String> colorHex = const Value.absent(),
            Value<String> emoji = const Value.absent(),
          }) =>
              TimeBlocksCompanion.insert(
            id: id,
            name: name,
            startHour: startHour,
            startMinute: startMinute,
            endHour: endHour,
            endMinute: endMinute,
            weekdays: weekdays,
            isActive: isActive,
            colorHex: colorHex,
            emoji: emoji,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TimeBlocksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TimeBlocksTable,
    TimeBlock,
    $$TimeBlocksTableFilterComposer,
    $$TimeBlocksTableOrderingComposer,
    $$TimeBlocksTableAnnotationComposer,
    $$TimeBlocksTableCreateCompanionBuilder,
    $$TimeBlocksTableUpdateCompanionBuilder,
    (TimeBlock, BaseReferences<_$AppDatabase, $TimeBlocksTable, TimeBlock>),
    TimeBlock,
    PrefetchHooks Function()>;
typedef $$TagsTableCreateCompanionBuilder = TagsCompanion Function({
  Value<int> id,
  required String name,
  required String colorHex,
  Value<String?> iconName,
});
typedef $$TagsTableUpdateCompanionBuilder = TagsCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String> colorHex,
  Value<String?> iconName,
});

class $$TagsTableFilterComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get colorHex => $composableBuilder(
      column: $table.colorHex, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get iconName => $composableBuilder(
      column: $table.iconName, builder: (column) => ColumnFilters(column));
}

class $$TagsTableOrderingComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get colorHex => $composableBuilder(
      column: $table.colorHex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get iconName => $composableBuilder(
      column: $table.iconName, builder: (column) => ColumnOrderings(column));
}

class $$TagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get colorHex =>
      $composableBuilder(column: $table.colorHex, builder: (column) => column);

  GeneratedColumn<String> get iconName =>
      $composableBuilder(column: $table.iconName, builder: (column) => column);
}

class $$TagsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TagsTable,
    Tag,
    $$TagsTableFilterComposer,
    $$TagsTableOrderingComposer,
    $$TagsTableAnnotationComposer,
    $$TagsTableCreateCompanionBuilder,
    $$TagsTableUpdateCompanionBuilder,
    (Tag, BaseReferences<_$AppDatabase, $TagsTable, Tag>),
    Tag,
    PrefetchHooks Function()> {
  $$TagsTableTableManager(_$AppDatabase db, $TagsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> colorHex = const Value.absent(),
            Value<String?> iconName = const Value.absent(),
          }) =>
              TagsCompanion(
            id: id,
            name: name,
            colorHex: colorHex,
            iconName: iconName,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            required String colorHex,
            Value<String?> iconName = const Value.absent(),
          }) =>
              TagsCompanion.insert(
            id: id,
            name: name,
            colorHex: colorHex,
            iconName: iconName,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TagsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TagsTable,
    Tag,
    $$TagsTableFilterComposer,
    $$TagsTableOrderingComposer,
    $$TagsTableAnnotationComposer,
    $$TagsTableCreateCompanionBuilder,
    $$TagsTableUpdateCompanionBuilder,
    (Tag, BaseReferences<_$AppDatabase, $TagsTable, Tag>),
    Tag,
    PrefetchHooks Function()>;
typedef $$ProjectsTableCreateCompanionBuilder = ProjectsCompanion Function({
  Value<int> id,
  required String name,
  required String colorHex,
  Value<String?> description,
  Value<DateTime?> deadline,
  Value<bool> isArchived,
  required DateTime createdAt,
});
typedef $$ProjectsTableUpdateCompanionBuilder = ProjectsCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String> colorHex,
  Value<String?> description,
  Value<DateTime?> deadline,
  Value<bool> isArchived,
  Value<DateTime> createdAt,
});

class $$ProjectsTableFilterComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get colorHex => $composableBuilder(
      column: $table.colorHex, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deadline => $composableBuilder(
      column: $table.deadline, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isArchived => $composableBuilder(
      column: $table.isArchived, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$ProjectsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get colorHex => $composableBuilder(
      column: $table.colorHex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deadline => $composableBuilder(
      column: $table.deadline, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isArchived => $composableBuilder(
      column: $table.isArchived, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ProjectsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get colorHex =>
      $composableBuilder(column: $table.colorHex, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<DateTime> get deadline =>
      $composableBuilder(column: $table.deadline, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
      column: $table.isArchived, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ProjectsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProjectsTable,
    Project,
    $$ProjectsTableFilterComposer,
    $$ProjectsTableOrderingComposer,
    $$ProjectsTableAnnotationComposer,
    $$ProjectsTableCreateCompanionBuilder,
    $$ProjectsTableUpdateCompanionBuilder,
    (Project, BaseReferences<_$AppDatabase, $ProjectsTable, Project>),
    Project,
    PrefetchHooks Function()> {
  $$ProjectsTableTableManager(_$AppDatabase db, $ProjectsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> colorHex = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<DateTime?> deadline = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              ProjectsCompanion(
            id: id,
            name: name,
            colorHex: colorHex,
            description: description,
            deadline: deadline,
            isArchived: isArchived,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            required String colorHex,
            Value<String?> description = const Value.absent(),
            Value<DateTime?> deadline = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            required DateTime createdAt,
          }) =>
              ProjectsCompanion.insert(
            id: id,
            name: name,
            colorHex: colorHex,
            description: description,
            deadline: deadline,
            isArchived: isArchived,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ProjectsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ProjectsTable,
    Project,
    $$ProjectsTableFilterComposer,
    $$ProjectsTableOrderingComposer,
    $$ProjectsTableAnnotationComposer,
    $$ProjectsTableCreateCompanionBuilder,
    $$ProjectsTableUpdateCompanionBuilder,
    (Project, BaseReferences<_$AppDatabase, $ProjectsTable, Project>),
    Project,
    PrefetchHooks Function()>;
typedef $$ActivityRecordsTableCreateCompanionBuilder = ActivityRecordsCompanion
    Function({
  Value<int> id,
  required DateTime startTime,
  Value<DateTime?> endTime,
  Value<int> durationMinutes,
  Value<String?> manualLabel,
  Value<String?> processName,
  Value<String?> windowTitle,
  Value<String?> packageName,
  Value<String?> category,
  Value<String?> appUsageRuleId,
  Value<int?> linkedTaskId,
  Value<bool> isAuto,
  Value<String> source,
});
typedef $$ActivityRecordsTableUpdateCompanionBuilder = ActivityRecordsCompanion
    Function({
  Value<int> id,
  Value<DateTime> startTime,
  Value<DateTime?> endTime,
  Value<int> durationMinutes,
  Value<String?> manualLabel,
  Value<String?> processName,
  Value<String?> windowTitle,
  Value<String?> packageName,
  Value<String?> category,
  Value<String?> appUsageRuleId,
  Value<int?> linkedTaskId,
  Value<bool> isAuto,
  Value<String> source,
});

class $$ActivityRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $ActivityRecordsTable> {
  $$ActivityRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startTime => $composableBuilder(
      column: $table.startTime, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get endTime => $composableBuilder(
      column: $table.endTime, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMinutes => $composableBuilder(
      column: $table.durationMinutes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get manualLabel => $composableBuilder(
      column: $table.manualLabel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get processName => $composableBuilder(
      column: $table.processName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get windowTitle => $composableBuilder(
      column: $table.windowTitle, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get appUsageRuleId => $composableBuilder(
      column: $table.appUsageRuleId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get linkedTaskId => $composableBuilder(
      column: $table.linkedTaskId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isAuto => $composableBuilder(
      column: $table.isAuto, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));
}

class $$ActivityRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $ActivityRecordsTable> {
  $$ActivityRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startTime => $composableBuilder(
      column: $table.startTime, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get endTime => $composableBuilder(
      column: $table.endTime, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMinutes => $composableBuilder(
      column: $table.durationMinutes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get manualLabel => $composableBuilder(
      column: $table.manualLabel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get processName => $composableBuilder(
      column: $table.processName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get windowTitle => $composableBuilder(
      column: $table.windowTitle, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get appUsageRuleId => $composableBuilder(
      column: $table.appUsageRuleId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get linkedTaskId => $composableBuilder(
      column: $table.linkedTaskId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isAuto => $composableBuilder(
      column: $table.isAuto, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));
}

class $$ActivityRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActivityRecordsTable> {
  $$ActivityRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<DateTime> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<int> get durationMinutes => $composableBuilder(
      column: $table.durationMinutes, builder: (column) => column);

  GeneratedColumn<String> get manualLabel => $composableBuilder(
      column: $table.manualLabel, builder: (column) => column);

  GeneratedColumn<String> get processName => $composableBuilder(
      column: $table.processName, builder: (column) => column);

  GeneratedColumn<String> get windowTitle => $composableBuilder(
      column: $table.windowTitle, builder: (column) => column);

  GeneratedColumn<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get appUsageRuleId => $composableBuilder(
      column: $table.appUsageRuleId, builder: (column) => column);

  GeneratedColumn<int> get linkedTaskId => $composableBuilder(
      column: $table.linkedTaskId, builder: (column) => column);

  GeneratedColumn<bool> get isAuto =>
      $composableBuilder(column: $table.isAuto, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);
}

class $$ActivityRecordsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ActivityRecordsTable,
    ActivityRecord,
    $$ActivityRecordsTableFilterComposer,
    $$ActivityRecordsTableOrderingComposer,
    $$ActivityRecordsTableAnnotationComposer,
    $$ActivityRecordsTableCreateCompanionBuilder,
    $$ActivityRecordsTableUpdateCompanionBuilder,
    (
      ActivityRecord,
      BaseReferences<_$AppDatabase, $ActivityRecordsTable, ActivityRecord>
    ),
    ActivityRecord,
    PrefetchHooks Function()> {
  $$ActivityRecordsTableTableManager(
      _$AppDatabase db, $ActivityRecordsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivityRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivityRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActivityRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<DateTime> startTime = const Value.absent(),
            Value<DateTime?> endTime = const Value.absent(),
            Value<int> durationMinutes = const Value.absent(),
            Value<String?> manualLabel = const Value.absent(),
            Value<String?> processName = const Value.absent(),
            Value<String?> windowTitle = const Value.absent(),
            Value<String?> packageName = const Value.absent(),
            Value<String?> category = const Value.absent(),
            Value<String?> appUsageRuleId = const Value.absent(),
            Value<int?> linkedTaskId = const Value.absent(),
            Value<bool> isAuto = const Value.absent(),
            Value<String> source = const Value.absent(),
          }) =>
              ActivityRecordsCompanion(
            id: id,
            startTime: startTime,
            endTime: endTime,
            durationMinutes: durationMinutes,
            manualLabel: manualLabel,
            processName: processName,
            windowTitle: windowTitle,
            packageName: packageName,
            category: category,
            appUsageRuleId: appUsageRuleId,
            linkedTaskId: linkedTaskId,
            isAuto: isAuto,
            source: source,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required DateTime startTime,
            Value<DateTime?> endTime = const Value.absent(),
            Value<int> durationMinutes = const Value.absent(),
            Value<String?> manualLabel = const Value.absent(),
            Value<String?> processName = const Value.absent(),
            Value<String?> windowTitle = const Value.absent(),
            Value<String?> packageName = const Value.absent(),
            Value<String?> category = const Value.absent(),
            Value<String?> appUsageRuleId = const Value.absent(),
            Value<int?> linkedTaskId = const Value.absent(),
            Value<bool> isAuto = const Value.absent(),
            Value<String> source = const Value.absent(),
          }) =>
              ActivityRecordsCompanion.insert(
            id: id,
            startTime: startTime,
            endTime: endTime,
            durationMinutes: durationMinutes,
            manualLabel: manualLabel,
            processName: processName,
            windowTitle: windowTitle,
            packageName: packageName,
            category: category,
            appUsageRuleId: appUsageRuleId,
            linkedTaskId: linkedTaskId,
            isAuto: isAuto,
            source: source,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ActivityRecordsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ActivityRecordsTable,
    ActivityRecord,
    $$ActivityRecordsTableFilterComposer,
    $$ActivityRecordsTableOrderingComposer,
    $$ActivityRecordsTableAnnotationComposer,
    $$ActivityRecordsTableCreateCompanionBuilder,
    $$ActivityRecordsTableUpdateCompanionBuilder,
    (
      ActivityRecord,
      BaseReferences<_$AppDatabase, $ActivityRecordsTable, ActivityRecord>
    ),
    ActivityRecord,
    PrefetchHooks Function()>;
typedef $$AppUsageRulesTableCreateCompanionBuilder = AppUsageRulesCompanion
    Function({
  Value<int> id,
  required String processName,
  Value<String?> windowTitlePattern,
  required String category,
  Value<String?> customLabel,
  Value<int> hitCount,
});
typedef $$AppUsageRulesTableUpdateCompanionBuilder = AppUsageRulesCompanion
    Function({
  Value<int> id,
  Value<String> processName,
  Value<String?> windowTitlePattern,
  Value<String> category,
  Value<String?> customLabel,
  Value<int> hitCount,
});

class $$AppUsageRulesTableFilterComposer
    extends Composer<_$AppDatabase, $AppUsageRulesTable> {
  $$AppUsageRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get processName => $composableBuilder(
      column: $table.processName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get windowTitlePattern => $composableBuilder(
      column: $table.windowTitlePattern,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get customLabel => $composableBuilder(
      column: $table.customLabel, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get hitCount => $composableBuilder(
      column: $table.hitCount, builder: (column) => ColumnFilters(column));
}

class $$AppUsageRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $AppUsageRulesTable> {
  $$AppUsageRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get processName => $composableBuilder(
      column: $table.processName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get windowTitlePattern => $composableBuilder(
      column: $table.windowTitlePattern,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get customLabel => $composableBuilder(
      column: $table.customLabel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get hitCount => $composableBuilder(
      column: $table.hitCount, builder: (column) => ColumnOrderings(column));
}

class $$AppUsageRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppUsageRulesTable> {
  $$AppUsageRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get processName => $composableBuilder(
      column: $table.processName, builder: (column) => column);

  GeneratedColumn<String> get windowTitlePattern => $composableBuilder(
      column: $table.windowTitlePattern, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get customLabel => $composableBuilder(
      column: $table.customLabel, builder: (column) => column);

  GeneratedColumn<int> get hitCount =>
      $composableBuilder(column: $table.hitCount, builder: (column) => column);
}

class $$AppUsageRulesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AppUsageRulesTable,
    AppUsageRule,
    $$AppUsageRulesTableFilterComposer,
    $$AppUsageRulesTableOrderingComposer,
    $$AppUsageRulesTableAnnotationComposer,
    $$AppUsageRulesTableCreateCompanionBuilder,
    $$AppUsageRulesTableUpdateCompanionBuilder,
    (
      AppUsageRule,
      BaseReferences<_$AppDatabase, $AppUsageRulesTable, AppUsageRule>
    ),
    AppUsageRule,
    PrefetchHooks Function()> {
  $$AppUsageRulesTableTableManager(_$AppDatabase db, $AppUsageRulesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppUsageRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppUsageRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppUsageRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> processName = const Value.absent(),
            Value<String?> windowTitlePattern = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<String?> customLabel = const Value.absent(),
            Value<int> hitCount = const Value.absent(),
          }) =>
              AppUsageRulesCompanion(
            id: id,
            processName: processName,
            windowTitlePattern: windowTitlePattern,
            category: category,
            customLabel: customLabel,
            hitCount: hitCount,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String processName,
            Value<String?> windowTitlePattern = const Value.absent(),
            required String category,
            Value<String?> customLabel = const Value.absent(),
            Value<int> hitCount = const Value.absent(),
          }) =>
              AppUsageRulesCompanion.insert(
            id: id,
            processName: processName,
            windowTitlePattern: windowTitlePattern,
            category: category,
            customLabel: customLabel,
            hitCount: hitCount,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AppUsageRulesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AppUsageRulesTable,
    AppUsageRule,
    $$AppUsageRulesTableFilterComposer,
    $$AppUsageRulesTableOrderingComposer,
    $$AppUsageRulesTableAnnotationComposer,
    $$AppUsageRulesTableCreateCompanionBuilder,
    $$AppUsageRulesTableUpdateCompanionBuilder,
    (
      AppUsageRule,
      BaseReferences<_$AppDatabase, $AppUsageRulesTable, AppUsageRule>
    ),
    AppUsageRule,
    PrefetchHooks Function()>;
typedef $$EventCalendarsTableCreateCompanionBuilder = EventCalendarsCompanion
    Function({
  Value<int> id,
  required String name,
  Value<String> colorHex,
  Value<String?> description,
  Value<bool> isVisible,
  Value<bool> isDefault,
  Value<String> source,
  Value<String?> syncUrl,
  required DateTime createdAt,
});
typedef $$EventCalendarsTableUpdateCompanionBuilder = EventCalendarsCompanion
    Function({
  Value<int> id,
  Value<String> name,
  Value<String> colorHex,
  Value<String?> description,
  Value<bool> isVisible,
  Value<bool> isDefault,
  Value<String> source,
  Value<String?> syncUrl,
  Value<DateTime> createdAt,
});

class $$EventCalendarsTableFilterComposer
    extends Composer<_$AppDatabase, $EventCalendarsTable> {
  $$EventCalendarsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get colorHex => $composableBuilder(
      column: $table.colorHex, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isVisible => $composableBuilder(
      column: $table.isVisible, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isDefault => $composableBuilder(
      column: $table.isDefault, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncUrl => $composableBuilder(
      column: $table.syncUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$EventCalendarsTableOrderingComposer
    extends Composer<_$AppDatabase, $EventCalendarsTable> {
  $$EventCalendarsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get colorHex => $composableBuilder(
      column: $table.colorHex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isVisible => $composableBuilder(
      column: $table.isVisible, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isDefault => $composableBuilder(
      column: $table.isDefault, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncUrl => $composableBuilder(
      column: $table.syncUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$EventCalendarsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventCalendarsTable> {
  $$EventCalendarsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get colorHex =>
      $composableBuilder(column: $table.colorHex, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<bool> get isVisible =>
      $composableBuilder(column: $table.isVisible, builder: (column) => column);

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get syncUrl =>
      $composableBuilder(column: $table.syncUrl, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$EventCalendarsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $EventCalendarsTable,
    EventCalendar,
    $$EventCalendarsTableFilterComposer,
    $$EventCalendarsTableOrderingComposer,
    $$EventCalendarsTableAnnotationComposer,
    $$EventCalendarsTableCreateCompanionBuilder,
    $$EventCalendarsTableUpdateCompanionBuilder,
    (
      EventCalendar,
      BaseReferences<_$AppDatabase, $EventCalendarsTable, EventCalendar>
    ),
    EventCalendar,
    PrefetchHooks Function()> {
  $$EventCalendarsTableTableManager(
      _$AppDatabase db, $EventCalendarsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventCalendarsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventCalendarsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventCalendarsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> colorHex = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<bool> isVisible = const Value.absent(),
            Value<bool> isDefault = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<String?> syncUrl = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              EventCalendarsCompanion(
            id: id,
            name: name,
            colorHex: colorHex,
            description: description,
            isVisible: isVisible,
            isDefault: isDefault,
            source: source,
            syncUrl: syncUrl,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<String> colorHex = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<bool> isVisible = const Value.absent(),
            Value<bool> isDefault = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<String?> syncUrl = const Value.absent(),
            required DateTime createdAt,
          }) =>
              EventCalendarsCompanion.insert(
            id: id,
            name: name,
            colorHex: colorHex,
            description: description,
            isVisible: isVisible,
            isDefault: isDefault,
            source: source,
            syncUrl: syncUrl,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$EventCalendarsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $EventCalendarsTable,
    EventCalendar,
    $$EventCalendarsTableFilterComposer,
    $$EventCalendarsTableOrderingComposer,
    $$EventCalendarsTableAnnotationComposer,
    $$EventCalendarsTableCreateCompanionBuilder,
    $$EventCalendarsTableUpdateCompanionBuilder,
    (
      EventCalendar,
      BaseReferences<_$AppDatabase, $EventCalendarsTable, EventCalendar>
    ),
    EventCalendar,
    PrefetchHooks Function()>;
typedef $$TaskListsTableCreateCompanionBuilder = TaskListsCompanion Function({
  Value<int> id,
  required String name,
  Value<String> colorHex,
  Value<String?> emoji,
  Value<bool> isVisible,
  Value<bool> isDefault,
  Value<bool> isArchived,
  required DateTime createdAt,
});
typedef $$TaskListsTableUpdateCompanionBuilder = TaskListsCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String> colorHex,
  Value<String?> emoji,
  Value<bool> isVisible,
  Value<bool> isDefault,
  Value<bool> isArchived,
  Value<DateTime> createdAt,
});

class $$TaskListsTableFilterComposer
    extends Composer<_$AppDatabase, $TaskListsTable> {
  $$TaskListsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get colorHex => $composableBuilder(
      column: $table.colorHex, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get emoji => $composableBuilder(
      column: $table.emoji, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isVisible => $composableBuilder(
      column: $table.isVisible, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isDefault => $composableBuilder(
      column: $table.isDefault, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isArchived => $composableBuilder(
      column: $table.isArchived, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$TaskListsTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskListsTable> {
  $$TaskListsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get colorHex => $composableBuilder(
      column: $table.colorHex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get emoji => $composableBuilder(
      column: $table.emoji, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isVisible => $composableBuilder(
      column: $table.isVisible, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isDefault => $composableBuilder(
      column: $table.isDefault, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isArchived => $composableBuilder(
      column: $table.isArchived, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$TaskListsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskListsTable> {
  $$TaskListsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get colorHex =>
      $composableBuilder(column: $table.colorHex, builder: (column) => column);

  GeneratedColumn<String> get emoji =>
      $composableBuilder(column: $table.emoji, builder: (column) => column);

  GeneratedColumn<bool> get isVisible =>
      $composableBuilder(column: $table.isVisible, builder: (column) => column);

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
      column: $table.isArchived, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TaskListsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TaskListsTable,
    TaskList,
    $$TaskListsTableFilterComposer,
    $$TaskListsTableOrderingComposer,
    $$TaskListsTableAnnotationComposer,
    $$TaskListsTableCreateCompanionBuilder,
    $$TaskListsTableUpdateCompanionBuilder,
    (TaskList, BaseReferences<_$AppDatabase, $TaskListsTable, TaskList>),
    TaskList,
    PrefetchHooks Function()> {
  $$TaskListsTableTableManager(_$AppDatabase db, $TaskListsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskListsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskListsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskListsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> colorHex = const Value.absent(),
            Value<String?> emoji = const Value.absent(),
            Value<bool> isVisible = const Value.absent(),
            Value<bool> isDefault = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              TaskListsCompanion(
            id: id,
            name: name,
            colorHex: colorHex,
            emoji: emoji,
            isVisible: isVisible,
            isDefault: isDefault,
            isArchived: isArchived,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<String> colorHex = const Value.absent(),
            Value<String?> emoji = const Value.absent(),
            Value<bool> isVisible = const Value.absent(),
            Value<bool> isDefault = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            required DateTime createdAt,
          }) =>
              TaskListsCompanion.insert(
            id: id,
            name: name,
            colorHex: colorHex,
            emoji: emoji,
            isVisible: isVisible,
            isDefault: isDefault,
            isArchived: isArchived,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TaskListsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TaskListsTable,
    TaskList,
    $$TaskListsTableFilterComposer,
    $$TaskListsTableOrderingComposer,
    $$TaskListsTableAnnotationComposer,
    $$TaskListsTableCreateCompanionBuilder,
    $$TaskListsTableUpdateCompanionBuilder,
    (TaskList, BaseReferences<_$AppDatabase, $TaskListsTable, TaskList>),
    TaskList,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TaskItemsTableTableManager get taskItems =>
      $$TaskItemsTableTableManager(_db, _db.taskItems);
  $$CalendarEventsTableTableManager get calendarEvents =>
      $$CalendarEventsTableTableManager(_db, _db.calendarEvents);
  $$TimeBlocksTableTableManager get timeBlocks =>
      $$TimeBlocksTableTableManager(_db, _db.timeBlocks);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db, _db.projects);
  $$ActivityRecordsTableTableManager get activityRecords =>
      $$ActivityRecordsTableTableManager(_db, _db.activityRecords);
  $$AppUsageRulesTableTableManager get appUsageRules =>
      $$AppUsageRulesTableTableManager(_db, _db.appUsageRules);
  $$EventCalendarsTableTableManager get eventCalendars =>
      $$EventCalendarsTableTableManager(_db, _db.eventCalendars);
  $$TaskListsTableTableManager get taskLists =>
      $$TaskListsTableTableManager(_db, _db.taskLists);
}
