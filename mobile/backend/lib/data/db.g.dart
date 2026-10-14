// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db.dart';

// ignore_for_file: type=lint
class $MeetingsTable extends Meetings with TableInfo<$MeetingsTable, Meeting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MeetingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('recording'),
  );
  static const VerificationMeta _contactMeta = const VerificationMeta(
    'contact',
  );
  @override
  late final GeneratedColumn<String> contact = GeneratedColumn<String>(
    'contact',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stepMeta = const VerificationMeta('step');
  @override
  late final GeneratedColumn<String> step = GeneratedColumn<String>(
    'step',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioPathMeta = const VerificationMeta(
    'audioPath',
  );
  @override
  late final GeneratedColumn<String> audioPath = GeneratedColumn<String>(
    'audio_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _processedMsMeta = const VerificationMeta(
    'processedMs',
  );
  @override
  late final GeneratedColumn<int> processedMs = GeneratedColumn<int>(
    'processed_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    kind,
    contact,
    startedAt,
    durationMs,
    status,
    step,
    error,
    summary,
    audioPath,
    processedMs,
    attempts,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meetings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Meeting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('contact')) {
      context.handle(
        _contactMeta,
        contact.isAcceptableOrUnknown(data['contact']!, _contactMeta),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('step')) {
      context.handle(
        _stepMeta,
        step.isAcceptableOrUnknown(data['step']!, _stepMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    }
    if (data.containsKey('audio_path')) {
      context.handle(
        _audioPathMeta,
        audioPath.isAcceptableOrUnknown(data['audio_path']!, _audioPathMeta),
      );
    }
    if (data.containsKey('processed_ms')) {
      context.handle(
        _processedMsMeta,
        processedMs.isAcceptableOrUnknown(
          data['processed_ms']!,
          _processedMsMeta,
        ),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Meeting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Meeting(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      contact: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact'],
      ),
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      step: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}step'],
      ),
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      ),
      audioPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_path'],
      ),
      processedMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}processed_ms'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
    );
  }

  @override
  $MeetingsTable createAlias(String alias) {
    return $MeetingsTable(attachedDatabase, alias);
  }
}

class Meeting extends DataClass implements Insertable<Meeting> {
  final int id;
  final String title;

  /// `recording` or `call`.
  final String kind;
  final String? contact;
  final DateTime startedAt;
  final int? durationMs;

  /// `RecordingStatus.id`.
  final String status;
  final String? step;
  final String? error;
  final String? summary;

  /// The FLAC file once processed (Plan 2); until then the pieces in the recording's folder.
  final String? audioPath;

  /// Speech to text is done up to here (ms from the start); a job resumes here.
  final int processedMs;

  /// Processing jobs started since the last one that finished: a job cut off
  /// twice (the app killed while processing) stops with a message.
  final int attempts;
  const Meeting({
    required this.id,
    required this.title,
    required this.kind,
    this.contact,
    required this.startedAt,
    this.durationMs,
    required this.status,
    this.step,
    this.error,
    this.summary,
    this.audioPath,
    required this.processedMs,
    required this.attempts,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || contact != null) {
      map['contact'] = Variable<String>(contact);
    }
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || step != null) {
      map['step'] = Variable<String>(step);
    }
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    if (!nullToAbsent || summary != null) {
      map['summary'] = Variable<String>(summary);
    }
    if (!nullToAbsent || audioPath != null) {
      map['audio_path'] = Variable<String>(audioPath);
    }
    map['processed_ms'] = Variable<int>(processedMs);
    map['attempts'] = Variable<int>(attempts);
    return map;
  }

  MeetingsCompanion toCompanion(bool nullToAbsent) {
    return MeetingsCompanion(
      id: Value(id),
      title: Value(title),
      kind: Value(kind),
      contact: contact == null && nullToAbsent
          ? const Value.absent()
          : Value(contact),
      startedAt: Value(startedAt),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      status: Value(status),
      step: step == null && nullToAbsent ? const Value.absent() : Value(step),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      summary: summary == null && nullToAbsent
          ? const Value.absent()
          : Value(summary),
      audioPath: audioPath == null && nullToAbsent
          ? const Value.absent()
          : Value(audioPath),
      processedMs: Value(processedMs),
      attempts: Value(attempts),
    );
  }

  factory Meeting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Meeting(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      kind: serializer.fromJson<String>(json['kind']),
      contact: serializer.fromJson<String?>(json['contact']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      status: serializer.fromJson<String>(json['status']),
      step: serializer.fromJson<String?>(json['step']),
      error: serializer.fromJson<String?>(json['error']),
      summary: serializer.fromJson<String?>(json['summary']),
      audioPath: serializer.fromJson<String?>(json['audioPath']),
      processedMs: serializer.fromJson<int>(json['processedMs']),
      attempts: serializer.fromJson<int>(json['attempts']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'kind': serializer.toJson<String>(kind),
      'contact': serializer.toJson<String?>(contact),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'durationMs': serializer.toJson<int?>(durationMs),
      'status': serializer.toJson<String>(status),
      'step': serializer.toJson<String?>(step),
      'error': serializer.toJson<String?>(error),
      'summary': serializer.toJson<String?>(summary),
      'audioPath': serializer.toJson<String?>(audioPath),
      'processedMs': serializer.toJson<int>(processedMs),
      'attempts': serializer.toJson<int>(attempts),
    };
  }

  Meeting copyWith({
    int? id,
    String? title,
    String? kind,
    Value<String?> contact = const Value.absent(),
    DateTime? startedAt,
    Value<int?> durationMs = const Value.absent(),
    String? status,
    Value<String?> step = const Value.absent(),
    Value<String?> error = const Value.absent(),
    Value<String?> summary = const Value.absent(),
    Value<String?> audioPath = const Value.absent(),
    int? processedMs,
    int? attempts,
  }) => Meeting(
    id: id ?? this.id,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    contact: contact.present ? contact.value : this.contact,
    startedAt: startedAt ?? this.startedAt,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    status: status ?? this.status,
    step: step.present ? step.value : this.step,
    error: error.present ? error.value : this.error,
    summary: summary.present ? summary.value : this.summary,
    audioPath: audioPath.present ? audioPath.value : this.audioPath,
    processedMs: processedMs ?? this.processedMs,
    attempts: attempts ?? this.attempts,
  );
  Meeting copyWithCompanion(MeetingsCompanion data) {
    return Meeting(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      kind: data.kind.present ? data.kind.value : this.kind,
      contact: data.contact.present ? data.contact.value : this.contact,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      status: data.status.present ? data.status.value : this.status,
      step: data.step.present ? data.step.value : this.step,
      error: data.error.present ? data.error.value : this.error,
      summary: data.summary.present ? data.summary.value : this.summary,
      audioPath: data.audioPath.present ? data.audioPath.value : this.audioPath,
      processedMs: data.processedMs.present
          ? data.processedMs.value
          : this.processedMs,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Meeting(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('kind: $kind, ')
          ..write('contact: $contact, ')
          ..write('startedAt: $startedAt, ')
          ..write('durationMs: $durationMs, ')
          ..write('status: $status, ')
          ..write('step: $step, ')
          ..write('error: $error, ')
          ..write('summary: $summary, ')
          ..write('audioPath: $audioPath, ')
          ..write('processedMs: $processedMs, ')
          ..write('attempts: $attempts')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    kind,
    contact,
    startedAt,
    durationMs,
    status,
    step,
    error,
    summary,
    audioPath,
    processedMs,
    attempts,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Meeting &&
          other.id == this.id &&
          other.title == this.title &&
          other.kind == this.kind &&
          other.contact == this.contact &&
          other.startedAt == this.startedAt &&
          other.durationMs == this.durationMs &&
          other.status == this.status &&
          other.step == this.step &&
          other.error == this.error &&
          other.summary == this.summary &&
          other.audioPath == this.audioPath &&
          other.processedMs == this.processedMs &&
          other.attempts == this.attempts);
}

class MeetingsCompanion extends UpdateCompanion<Meeting> {
  final Value<int> id;
  final Value<String> title;
  final Value<String> kind;
  final Value<String?> contact;
  final Value<DateTime> startedAt;
  final Value<int?> durationMs;
  final Value<String> status;
  final Value<String?> step;
  final Value<String?> error;
  final Value<String?> summary;
  final Value<String?> audioPath;
  final Value<int> processedMs;
  final Value<int> attempts;
  const MeetingsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.kind = const Value.absent(),
    this.contact = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.status = const Value.absent(),
    this.step = const Value.absent(),
    this.error = const Value.absent(),
    this.summary = const Value.absent(),
    this.audioPath = const Value.absent(),
    this.processedMs = const Value.absent(),
    this.attempts = const Value.absent(),
  });
  MeetingsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    this.kind = const Value.absent(),
    this.contact = const Value.absent(),
    required DateTime startedAt,
    this.durationMs = const Value.absent(),
    required String status,
    this.step = const Value.absent(),
    this.error = const Value.absent(),
    this.summary = const Value.absent(),
    this.audioPath = const Value.absent(),
    this.processedMs = const Value.absent(),
    this.attempts = const Value.absent(),
  }) : title = Value(title),
       startedAt = Value(startedAt),
       status = Value(status);
  static Insertable<Meeting> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? kind,
    Expression<String>? contact,
    Expression<DateTime>? startedAt,
    Expression<int>? durationMs,
    Expression<String>? status,
    Expression<String>? step,
    Expression<String>? error,
    Expression<String>? summary,
    Expression<String>? audioPath,
    Expression<int>? processedMs,
    Expression<int>? attempts,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (kind != null) 'kind': kind,
      if (contact != null) 'contact': contact,
      if (startedAt != null) 'started_at': startedAt,
      if (durationMs != null) 'duration_ms': durationMs,
      if (status != null) 'status': status,
      if (step != null) 'step': step,
      if (error != null) 'error': error,
      if (summary != null) 'summary': summary,
      if (audioPath != null) 'audio_path': audioPath,
      if (processedMs != null) 'processed_ms': processedMs,
      if (attempts != null) 'attempts': attempts,
    });
  }

  MeetingsCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String>? kind,
    Value<String?>? contact,
    Value<DateTime>? startedAt,
    Value<int?>? durationMs,
    Value<String>? status,
    Value<String?>? step,
    Value<String?>? error,
    Value<String?>? summary,
    Value<String?>? audioPath,
    Value<int>? processedMs,
    Value<int>? attempts,
  }) {
    return MeetingsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      kind: kind ?? this.kind,
      contact: contact ?? this.contact,
      startedAt: startedAt ?? this.startedAt,
      durationMs: durationMs ?? this.durationMs,
      status: status ?? this.status,
      step: step ?? this.step,
      error: error ?? this.error,
      summary: summary ?? this.summary,
      audioPath: audioPath ?? this.audioPath,
      processedMs: processedMs ?? this.processedMs,
      attempts: attempts ?? this.attempts,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (contact.present) {
      map['contact'] = Variable<String>(contact.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (step.present) {
      map['step'] = Variable<String>(step.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (audioPath.present) {
      map['audio_path'] = Variable<String>(audioPath.value);
    }
    if (processedMs.present) {
      map['processed_ms'] = Variable<int>(processedMs.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MeetingsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('kind: $kind, ')
          ..write('contact: $contact, ')
          ..write('startedAt: $startedAt, ')
          ..write('durationMs: $durationMs, ')
          ..write('status: $status, ')
          ..write('step: $step, ')
          ..write('error: $error, ')
          ..write('summary: $summary, ')
          ..write('audioPath: $audioPath, ')
          ..write('processedMs: $processedMs, ')
          ..write('attempts: $attempts')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TranscriptLinesTable extends TranscriptLines
    with TableInfo<$TranscriptLinesTable, TranscriptLine> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TranscriptLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _meetingIdMeta = const VerificationMeta(
    'meetingId',
  );
  @override
  late final GeneratedColumn<int> meetingId = GeneratedColumn<int>(
    'meeting_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES meetings (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _startMsMeta = const VerificationMeta(
    'startMs',
  );
  @override
  late final GeneratedColumn<int> startMs = GeneratedColumn<int>(
    'start_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endMsMeta = const VerificationMeta('endMs');
  @override
  late final GeneratedColumn<int> endMs = GeneratedColumn<int>(
    'end_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wordsJsonMeta = const VerificationMeta(
    'wordsJson',
  );
  @override
  late final GeneratedColumn<String> wordsJson = GeneratedColumn<String>(
    'words_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    meetingId,
    startMs,
    endMs,
    content,
    wordsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transcript_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<TranscriptLine> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('meeting_id')) {
      context.handle(
        _meetingIdMeta,
        meetingId.isAcceptableOrUnknown(data['meeting_id']!, _meetingIdMeta),
      );
    } else if (isInserting) {
      context.missing(_meetingIdMeta);
    }
    if (data.containsKey('start_ms')) {
      context.handle(
        _startMsMeta,
        startMs.isAcceptableOrUnknown(data['start_ms']!, _startMsMeta),
      );
    } else if (isInserting) {
      context.missing(_startMsMeta);
    }
    if (data.containsKey('end_ms')) {
      context.handle(
        _endMsMeta,
        endMs.isAcceptableOrUnknown(data['end_ms']!, _endMsMeta),
      );
    } else if (isInserting) {
      context.missing(_endMsMeta);
    }
    if (data.containsKey('text')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['text']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('words_json')) {
      context.handle(
        _wordsJsonMeta,
        wordsJson.isAcceptableOrUnknown(data['words_json']!, _wordsJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_wordsJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TranscriptLine map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TranscriptLine(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      meetingId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}meeting_id'],
      )!,
      startMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_ms'],
      )!,
      endMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_ms'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      )!,
      wordsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}words_json'],
      )!,
    );
  }

  @override
  $TranscriptLinesTable createAlias(String alias) {
    return $TranscriptLinesTable(attachedDatabase, alias);
  }
}

class TranscriptLine extends DataClass implements Insertable<TranscriptLine> {
  final int id;
  final int meetingId;
  final int startMs;
  final int endMs;
  final String content;

  /// `[["word", startMs, endMs], …]`.
  final String wordsJson;
  const TranscriptLine({
    required this.id,
    required this.meetingId,
    required this.startMs,
    required this.endMs,
    required this.content,
    required this.wordsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['meeting_id'] = Variable<int>(meetingId);
    map['start_ms'] = Variable<int>(startMs);
    map['end_ms'] = Variable<int>(endMs);
    map['text'] = Variable<String>(content);
    map['words_json'] = Variable<String>(wordsJson);
    return map;
  }

  TranscriptLinesCompanion toCompanion(bool nullToAbsent) {
    return TranscriptLinesCompanion(
      id: Value(id),
      meetingId: Value(meetingId),
      startMs: Value(startMs),
      endMs: Value(endMs),
      content: Value(content),
      wordsJson: Value(wordsJson),
    );
  }

  factory TranscriptLine.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TranscriptLine(
      id: serializer.fromJson<int>(json['id']),
      meetingId: serializer.fromJson<int>(json['meetingId']),
      startMs: serializer.fromJson<int>(json['startMs']),
      endMs: serializer.fromJson<int>(json['endMs']),
      content: serializer.fromJson<String>(json['content']),
      wordsJson: serializer.fromJson<String>(json['wordsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'meetingId': serializer.toJson<int>(meetingId),
      'startMs': serializer.toJson<int>(startMs),
      'endMs': serializer.toJson<int>(endMs),
      'content': serializer.toJson<String>(content),
      'wordsJson': serializer.toJson<String>(wordsJson),
    };
  }

  TranscriptLine copyWith({
    int? id,
    int? meetingId,
    int? startMs,
    int? endMs,
    String? content,
    String? wordsJson,
  }) => TranscriptLine(
    id: id ?? this.id,
    meetingId: meetingId ?? this.meetingId,
    startMs: startMs ?? this.startMs,
    endMs: endMs ?? this.endMs,
    content: content ?? this.content,
    wordsJson: wordsJson ?? this.wordsJson,
  );
  TranscriptLine copyWithCompanion(TranscriptLinesCompanion data) {
    return TranscriptLine(
      id: data.id.present ? data.id.value : this.id,
      meetingId: data.meetingId.present ? data.meetingId.value : this.meetingId,
      startMs: data.startMs.present ? data.startMs.value : this.startMs,
      endMs: data.endMs.present ? data.endMs.value : this.endMs,
      content: data.content.present ? data.content.value : this.content,
      wordsJson: data.wordsJson.present ? data.wordsJson.value : this.wordsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TranscriptLine(')
          ..write('id: $id, ')
          ..write('meetingId: $meetingId, ')
          ..write('startMs: $startMs, ')
          ..write('endMs: $endMs, ')
          ..write('content: $content, ')
          ..write('wordsJson: $wordsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, meetingId, startMs, endMs, content, wordsJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TranscriptLine &&
          other.id == this.id &&
          other.meetingId == this.meetingId &&
          other.startMs == this.startMs &&
          other.endMs == this.endMs &&
          other.content == this.content &&
          other.wordsJson == this.wordsJson);
}

class TranscriptLinesCompanion extends UpdateCompanion<TranscriptLine> {
  final Value<int> id;
  final Value<int> meetingId;
  final Value<int> startMs;
  final Value<int> endMs;
  final Value<String> content;
  final Value<String> wordsJson;
  const TranscriptLinesCompanion({
    this.id = const Value.absent(),
    this.meetingId = const Value.absent(),
    this.startMs = const Value.absent(),
    this.endMs = const Value.absent(),
    this.content = const Value.absent(),
    this.wordsJson = const Value.absent(),
  });
  TranscriptLinesCompanion.insert({
    this.id = const Value.absent(),
    required int meetingId,
    required int startMs,
    required int endMs,
    required String content,
    required String wordsJson,
  }) : meetingId = Value(meetingId),
       startMs = Value(startMs),
       endMs = Value(endMs),
       content = Value(content),
       wordsJson = Value(wordsJson);
  static Insertable<TranscriptLine> custom({
    Expression<int>? id,
    Expression<int>? meetingId,
    Expression<int>? startMs,
    Expression<int>? endMs,
    Expression<String>? content,
    Expression<String>? wordsJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (meetingId != null) 'meeting_id': meetingId,
      if (startMs != null) 'start_ms': startMs,
      if (endMs != null) 'end_ms': endMs,
      if (content != null) 'text': content,
      if (wordsJson != null) 'words_json': wordsJson,
    });
  }

  TranscriptLinesCompanion copyWith({
    Value<int>? id,
    Value<int>? meetingId,
    Value<int>? startMs,
    Value<int>? endMs,
    Value<String>? content,
    Value<String>? wordsJson,
  }) {
    return TranscriptLinesCompanion(
      id: id ?? this.id,
      meetingId: meetingId ?? this.meetingId,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      content: content ?? this.content,
      wordsJson: wordsJson ?? this.wordsJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (meetingId.present) {
      map['meeting_id'] = Variable<int>(meetingId.value);
    }
    if (startMs.present) {
      map['start_ms'] = Variable<int>(startMs.value);
    }
    if (endMs.present) {
      map['end_ms'] = Variable<int>(endMs.value);
    }
    if (content.present) {
      map['text'] = Variable<String>(content.value);
    }
    if (wordsJson.present) {
      map['words_json'] = Variable<String>(wordsJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TranscriptLinesCompanion(')
          ..write('id: $id, ')
          ..write('meetingId: $meetingId, ')
          ..write('startMs: $startMs, ')
          ..write('endMs: $endMs, ')
          ..write('content: $content, ')
          ..write('wordsJson: $wordsJson')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $MeetingsTable meetings = $MeetingsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $TranscriptLinesTable transcriptLines = $TranscriptLinesTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    meetings,
    settings,
    transcriptLines,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'meetings',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('transcript_lines', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$MeetingsTableCreateCompanionBuilder = MeetingsCompanion Function({
  Value<int> id,
  required String title,
  Value<String> kind,
  Value<String?> contact,
  required DateTime startedAt,
  Value<int?> durationMs,
  required String status,
  Value<String?> step,
  Value<String?> error,
  Value<String?> summary,
  Value<String?> audioPath,
  Value<int> processedMs,
  Value<int> attempts,
});
typedef $$MeetingsTableUpdateCompanionBuilder = MeetingsCompanion Function({
  Value<int> id,
  Value<String> title,
  Value<String> kind,
  Value<String?> contact,
  Value<DateTime> startedAt,
  Value<int?> durationMs,
  Value<String> status,
  Value<String?> step,
  Value<String?> error,
  Value<String?> summary,
  Value<String?> audioPath,
  Value<int> processedMs,
  Value<int> attempts,
});

final class $$MeetingsTableReferences
    extends BaseReferences<_$AppDatabase, $MeetingsTable, Meeting> {
  $$MeetingsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TranscriptLinesTable, List<TranscriptLine>>
  _transcriptLinesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.transcriptLines,
    aliasName: 'meetings__id__transcript_lines__meeting_id',
  );

  $$TranscriptLinesTableProcessedTableManager get transcriptLinesRefs {
    final manager = $$TranscriptLinesTableTableManager(
      $_db,
      $_db.transcriptLines,
    ).filter((f) => f.meetingId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _transcriptLinesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MeetingsTableFilterComposer
    extends Composer<_$AppDatabase, $MeetingsTable> {
  $$MeetingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contact => $composableBuilder(
    column: $table.contact,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioPath => $composableBuilder(
    column: $table.audioPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get processedMs => $composableBuilder(
    column: $table.processedMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> transcriptLinesRefs(
    Expression<bool> Function($$TranscriptLinesTableFilterComposer f) f,
  ) {
    final $$TranscriptLinesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transcriptLines,
      getReferencedColumn: (t) => t.meetingId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TranscriptLinesTableFilterComposer(
            $db: $db,
            $table: $db.transcriptLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MeetingsTableOrderingComposer
    extends Composer<_$AppDatabase, $MeetingsTable> {
  $$MeetingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contact => $composableBuilder(
    column: $table.contact,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioPath => $composableBuilder(
    column: $table.audioPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get processedMs => $composableBuilder(
    column: $table.processedMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MeetingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MeetingsTable> {
  $$MeetingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get contact =>
      $composableBuilder(column: $table.contact, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get step =>
      $composableBuilder(column: $table.step, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get audioPath =>
      $composableBuilder(column: $table.audioPath, builder: (column) => column);

  GeneratedColumn<int> get processedMs => $composableBuilder(
    column: $table.processedMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  Expression<T> transcriptLinesRefs<T extends Object>(
    Expression<T> Function($$TranscriptLinesTableAnnotationComposer a) f,
  ) {
    final $$TranscriptLinesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transcriptLines,
      getReferencedColumn: (t) => t.meetingId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TranscriptLinesTableAnnotationComposer(
            $db: $db,
            $table: $db.transcriptLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MeetingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MeetingsTable,
          Meeting,
          $$MeetingsTableFilterComposer,
          $$MeetingsTableOrderingComposer,
          $$MeetingsTableAnnotationComposer,
          $$MeetingsTableCreateCompanionBuilder,
          $$MeetingsTableUpdateCompanionBuilder,
          (Meeting, $$MeetingsTableReferences),
          Meeting,
          PrefetchHooks Function({bool transcriptLinesRefs})
        > {
  $$MeetingsTableTableManager(_$AppDatabase db, $MeetingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MeetingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MeetingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MeetingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> contact = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> step = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<String?> audioPath = const Value.absent(),
                Value<int> processedMs = const Value.absent(),
                Value<int> attempts = const Value.absent(),
              }) => MeetingsCompanion(
                id: id,
                title: title,
                kind: kind,
                contact: contact,
                startedAt: startedAt,
                durationMs: durationMs,
                status: status,
                step: step,
                error: error,
                summary: summary,
                audioPath: audioPath,
                processedMs: processedMs,
                attempts: attempts,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                Value<String> kind = const Value.absent(),
                Value<String?> contact = const Value.absent(),
                required DateTime startedAt,
                Value<int?> durationMs = const Value.absent(),
                required String status,
                Value<String?> step = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<String?> audioPath = const Value.absent(),
                Value<int> processedMs = const Value.absent(),
                Value<int> attempts = const Value.absent(),
              }) => MeetingsCompanion.insert(
                id: id,
                title: title,
                kind: kind,
                contact: contact,
                startedAt: startedAt,
                durationMs: durationMs,
                status: status,
                step: step,
                error: error,
                summary: summary,
                audioPath: audioPath,
                processedMs: processedMs,
                attempts: attempts,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MeetingsTable, Meeting>(table),
                  $$MeetingsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({transcriptLinesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (transcriptLinesRefs) db.transcriptLines,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (transcriptLinesRefs)
                    await $_getPrefetchedData<
                      Meeting,
                      $MeetingsTable,
                      TranscriptLine
                    >(
                      currentTable: table,
                      referencedTable: $$MeetingsTableReferences
                          ._transcriptLinesRefsTable(db),
                      managerFromTypedResult: (p0) => $$MeetingsTableReferences(
                        db,
                        table,
                        p0,
                      ).transcriptLinesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.meetingId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$MeetingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MeetingsTable,
      Meeting,
      $$MeetingsTableFilterComposer,
      $$MeetingsTableOrderingComposer,
      $$MeetingsTableAnnotationComposer,
      $$MeetingsTableCreateCompanionBuilder,
      $$MeetingsTableUpdateCompanionBuilder,
      (Meeting, $$MeetingsTableReferences),
      Meeting,
      PrefetchHooks Function({bool transcriptLinesRefs})
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, Setting>(table),
                  BaseReferences<_$AppDatabase, $SettingsTable, Setting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$TranscriptLinesTableCreateCompanionBuilder =
    TranscriptLinesCompanion Function({
      Value<int> id,
      required int meetingId,
      required int startMs,
      required int endMs,
      required String content,
      required String wordsJson,
    });
typedef $$TranscriptLinesTableUpdateCompanionBuilder =
    TranscriptLinesCompanion Function({
      Value<int> id,
      Value<int> meetingId,
      Value<int> startMs,
      Value<int> endMs,
      Value<String> content,
      Value<String> wordsJson,
    });

final class $$TranscriptLinesTableReferences
    extends
        BaseReferences<_$AppDatabase, $TranscriptLinesTable, TranscriptLine> {
  $$TranscriptLinesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MeetingsTable _meetingIdTable(_$AppDatabase db) =>
      db.meetings.createAlias('transcript_lines__meeting_id__meetings__id');

  $$MeetingsTableProcessedTableManager get meetingId {
    final $_column = $_itemColumn<int>('meeting_id')!;

    final manager = $$MeetingsTableTableManager(
      $_db,
      $_db.meetings,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_meetingIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TranscriptLinesTableFilterComposer
    extends Composer<_$AppDatabase, $TranscriptLinesTable> {
  $$TranscriptLinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startMs => $composableBuilder(
    column: $table.startMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endMs => $composableBuilder(
    column: $table.endMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wordsJson => $composableBuilder(
    column: $table.wordsJson,
    builder: (column) => ColumnFilters(column),
  );

  $$MeetingsTableFilterComposer get meetingId {
    final $$MeetingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.meetingId,
      referencedTable: $db.meetings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MeetingsTableFilterComposer(
            $db: $db,
            $table: $db.meetings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TranscriptLinesTableOrderingComposer
    extends Composer<_$AppDatabase, $TranscriptLinesTable> {
  $$TranscriptLinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startMs => $composableBuilder(
    column: $table.startMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endMs => $composableBuilder(
    column: $table.endMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wordsJson => $composableBuilder(
    column: $table.wordsJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$MeetingsTableOrderingComposer get meetingId {
    final $$MeetingsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.meetingId,
      referencedTable: $db.meetings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MeetingsTableOrderingComposer(
            $db: $db,
            $table: $db.meetings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TranscriptLinesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TranscriptLinesTable> {
  $$TranscriptLinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get startMs =>
      $composableBuilder(column: $table.startMs, builder: (column) => column);

  GeneratedColumn<int> get endMs =>
      $composableBuilder(column: $table.endMs, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get wordsJson =>
      $composableBuilder(column: $table.wordsJson, builder: (column) => column);

  $$MeetingsTableAnnotationComposer get meetingId {
    final $$MeetingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.meetingId,
      referencedTable: $db.meetings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MeetingsTableAnnotationComposer(
            $db: $db,
            $table: $db.meetings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TranscriptLinesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TranscriptLinesTable,
          TranscriptLine,
          $$TranscriptLinesTableFilterComposer,
          $$TranscriptLinesTableOrderingComposer,
          $$TranscriptLinesTableAnnotationComposer,
          $$TranscriptLinesTableCreateCompanionBuilder,
          $$TranscriptLinesTableUpdateCompanionBuilder,
          (TranscriptLine, $$TranscriptLinesTableReferences),
          TranscriptLine,
          PrefetchHooks Function({bool meetingId})
        > {
  $$TranscriptLinesTableTableManager(
    _$AppDatabase db,
    $TranscriptLinesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TranscriptLinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TranscriptLinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TranscriptLinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> meetingId = const Value.absent(),
                Value<int> startMs = const Value.absent(),
                Value<int> endMs = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> wordsJson = const Value.absent(),
              }) => TranscriptLinesCompanion(
                id: id,
                meetingId: meetingId,
                startMs: startMs,
                endMs: endMs,
                content: content,
                wordsJson: wordsJson,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int meetingId,
                required int startMs,
                required int endMs,
                required String content,
                required String wordsJson,
              }) => TranscriptLinesCompanion.insert(
                id: id,
                meetingId: meetingId,
                startMs: startMs,
                endMs: endMs,
                content: content,
                wordsJson: wordsJson,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TranscriptLinesTable, TranscriptLine>(table),
                  $$TranscriptLinesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({meetingId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (meetingId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.meetingId,
                        referencedTable: $$TranscriptLinesTableReferences
                            ._meetingIdTable(db),
                        referencedColumn: $$TranscriptLinesTableReferences
                            ._meetingIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TranscriptLinesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TranscriptLinesTable,
      TranscriptLine,
      $$TranscriptLinesTableFilterComposer,
      $$TranscriptLinesTableOrderingComposer,
      $$TranscriptLinesTableAnnotationComposer,
      $$TranscriptLinesTableCreateCompanionBuilder,
      $$TranscriptLinesTableUpdateCompanionBuilder,
      (TranscriptLine, $$TranscriptLinesTableReferences),
      TranscriptLine,
      PrefetchHooks Function({bool meetingId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$MeetingsTableTableManager get meetings =>
      $$MeetingsTableTableManager(_db, _db.meetings);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$TranscriptLinesTableTableManager get transcriptLines =>
      $$TranscriptLinesTableTableManager(_db, _db.transcriptLines);
}
