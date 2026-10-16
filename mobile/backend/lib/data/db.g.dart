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
  static const VerificationMeta _languagesMeta = const VerificationMeta(
    'languages',
  );
  @override
  late final GeneratedColumn<String> languages = GeneratedColumn<String>(
    'languages',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('en'),
  );
  static const VerificationMeta _preferIndicMeta = const VerificationMeta(
    'preferIndic',
  );
  @override
  late final GeneratedColumn<String> preferIndic = GeneratedColumn<String>(
    'prefer_indic',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('gu'),
  );
  static const VerificationMeta _englishModelMeta = const VerificationMeta(
    'englishModel',
  );
  @override
  late final GeneratedColumn<String> englishModel = GeneratedColumn<String>(
    'english_model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('faster'),
  );
  static const VerificationMeta _reprocessingMeta = const VerificationMeta(
    'reprocessing',
  );
  @override
  late final GeneratedColumn<bool> reprocessing = GeneratedColumn<bool>(
    'reprocessing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reprocessing" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _speakersMeta = const VerificationMeta(
    'speakers',
  );
  @override
  late final GeneratedColumn<bool> speakers = GeneratedColumn<bool>(
    'speakers',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("speakers" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _audioDeletedMeta = const VerificationMeta(
    'audioDeleted',
  );
  @override
  late final GeneratedColumn<bool> audioDeleted = GeneratedColumn<bool>(
    'audio_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("audio_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _flacFailuresMeta = const VerificationMeta(
    'flacFailures',
  );
  @override
  late final GeneratedColumn<int> flacFailures = GeneratedColumn<int>(
    'flac_failures',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tasksStatusMeta = const VerificationMeta(
    'tasksStatus',
  );
  @override
  late final GeneratedColumn<String> tasksStatus = GeneratedColumn<String>(
    'tasks_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _tasksPartMeta = const VerificationMeta(
    'tasksPart',
  );
  @override
  late final GeneratedColumn<int> tasksPart = GeneratedColumn<int>(
    'tasks_part',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tasksWorkMeta = const VerificationMeta(
    'tasksWork',
  );
  @override
  late final GeneratedColumn<String> tasksWork = GeneratedColumn<String>(
    'tasks_work',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
    languages,
    preferIndic,
    englishModel,
    reprocessing,
    speakers,
    audioDeleted,
    flacFailures,
    tasksStatus,
    tasksPart,
    tasksWork,
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
    if (data.containsKey('languages')) {
      context.handle(
        _languagesMeta,
        languages.isAcceptableOrUnknown(data['languages']!, _languagesMeta),
      );
    }
    if (data.containsKey('prefer_indic')) {
      context.handle(
        _preferIndicMeta,
        preferIndic.isAcceptableOrUnknown(
          data['prefer_indic']!,
          _preferIndicMeta,
        ),
      );
    }
    if (data.containsKey('english_model')) {
      context.handle(
        _englishModelMeta,
        englishModel.isAcceptableOrUnknown(
          data['english_model']!,
          _englishModelMeta,
        ),
      );
    }
    if (data.containsKey('reprocessing')) {
      context.handle(
        _reprocessingMeta,
        reprocessing.isAcceptableOrUnknown(
          data['reprocessing']!,
          _reprocessingMeta,
        ),
      );
    }
    if (data.containsKey('speakers')) {
      context.handle(
        _speakersMeta,
        speakers.isAcceptableOrUnknown(data['speakers']!, _speakersMeta),
      );
    }
    if (data.containsKey('audio_deleted')) {
      context.handle(
        _audioDeletedMeta,
        audioDeleted.isAcceptableOrUnknown(
          data['audio_deleted']!,
          _audioDeletedMeta,
        ),
      );
    }
    if (data.containsKey('flac_failures')) {
      context.handle(
        _flacFailuresMeta,
        flacFailures.isAcceptableOrUnknown(
          data['flac_failures']!,
          _flacFailuresMeta,
        ),
      );
    }
    if (data.containsKey('tasks_status')) {
      context.handle(
        _tasksStatusMeta,
        tasksStatus.isAcceptableOrUnknown(
          data['tasks_status']!,
          _tasksStatusMeta,
        ),
      );
    }
    if (data.containsKey('tasks_part')) {
      context.handle(
        _tasksPartMeta,
        tasksPart.isAcceptableOrUnknown(data['tasks_part']!, _tasksPartMeta),
      );
    }
    if (data.containsKey('tasks_work')) {
      context.handle(
        _tasksWorkMeta,
        tasksWork.isAcceptableOrUnknown(data['tasks_work']!, _tasksWorkMeta),
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
      languages: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}languages'],
      )!,
      preferIndic: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prefer_indic'],
      )!,
      englishModel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}english_model'],
      )!,
      reprocessing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reprocessing'],
      )!,
      speakers: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}speakers'],
      )!,
      audioDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}audio_deleted'],
      )!,
      flacFailures: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}flac_failures'],
      )!,
      tasksStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tasks_status'],
      )!,
      tasksPart: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tasks_part'],
      )!,
      tasksWork: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tasks_work'],
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

  /// The checked FLAC once processing ended (`audio.flac`); until then the
  /// pieces in the recording's folder.
  final String? audioPath;

  /// Speech to text is done up to here (ms from the start); a job resumes here.
  final int processedMs;

  /// Processing jobs started since the last one that finished: a job cut off
  /// twice (the app killed while processing) stops with a message.
  final int attempts;

  /// How it is turned into text (`SpeechSetup`), fixed when it is made:
  /// languages (`en,gu`), Hindi or Gujarati when unclear, the English model.
  final String languages;
  final String preferIndic;
  final String englishModel;

  /// Being processed again: its new lines are drafts until the run completes.
  final bool reprocessing;

  /// Made with speaker detection on (part of its setup).
  final bool speakers;

  /// Its audio was deleted by "Keep recordings for" (the text stays).
  final bool audioDeleted;

  /// Times its FLAC didn't match the pieces (it stops trying at 3).
  final int flacFailures;

  /// Its summary and tasks (`TasksStatus.id`): none, waiting, finding, found, failed.
  final String tasksStatus;

  /// The task step continues from this part (a step that gave way, or was cut off).
  final int tasksPart;

  /// The parts' answers so far (JSON), or why it failed.
  final String tasksWork;
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
    required this.languages,
    required this.preferIndic,
    required this.englishModel,
    required this.reprocessing,
    required this.speakers,
    required this.audioDeleted,
    required this.flacFailures,
    required this.tasksStatus,
    required this.tasksPart,
    required this.tasksWork,
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
    map['languages'] = Variable<String>(languages);
    map['prefer_indic'] = Variable<String>(preferIndic);
    map['english_model'] = Variable<String>(englishModel);
    map['reprocessing'] = Variable<bool>(reprocessing);
    map['speakers'] = Variable<bool>(speakers);
    map['audio_deleted'] = Variable<bool>(audioDeleted);
    map['flac_failures'] = Variable<int>(flacFailures);
    map['tasks_status'] = Variable<String>(tasksStatus);
    map['tasks_part'] = Variable<int>(tasksPart);
    map['tasks_work'] = Variable<String>(tasksWork);
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
      languages: Value(languages),
      preferIndic: Value(preferIndic),
      englishModel: Value(englishModel),
      reprocessing: Value(reprocessing),
      speakers: Value(speakers),
      audioDeleted: Value(audioDeleted),
      flacFailures: Value(flacFailures),
      tasksStatus: Value(tasksStatus),
      tasksPart: Value(tasksPart),
      tasksWork: Value(tasksWork),
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
      languages: serializer.fromJson<String>(json['languages']),
      preferIndic: serializer.fromJson<String>(json['preferIndic']),
      englishModel: serializer.fromJson<String>(json['englishModel']),
      reprocessing: serializer.fromJson<bool>(json['reprocessing']),
      speakers: serializer.fromJson<bool>(json['speakers']),
      audioDeleted: serializer.fromJson<bool>(json['audioDeleted']),
      flacFailures: serializer.fromJson<int>(json['flacFailures']),
      tasksStatus: serializer.fromJson<String>(json['tasksStatus']),
      tasksPart: serializer.fromJson<int>(json['tasksPart']),
      tasksWork: serializer.fromJson<String>(json['tasksWork']),
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
      'languages': serializer.toJson<String>(languages),
      'preferIndic': serializer.toJson<String>(preferIndic),
      'englishModel': serializer.toJson<String>(englishModel),
      'reprocessing': serializer.toJson<bool>(reprocessing),
      'speakers': serializer.toJson<bool>(speakers),
      'audioDeleted': serializer.toJson<bool>(audioDeleted),
      'flacFailures': serializer.toJson<int>(flacFailures),
      'tasksStatus': serializer.toJson<String>(tasksStatus),
      'tasksPart': serializer.toJson<int>(tasksPart),
      'tasksWork': serializer.toJson<String>(tasksWork),
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
    String? languages,
    String? preferIndic,
    String? englishModel,
    bool? reprocessing,
    bool? speakers,
    bool? audioDeleted,
    int? flacFailures,
    String? tasksStatus,
    int? tasksPart,
    String? tasksWork,
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
    languages: languages ?? this.languages,
    preferIndic: preferIndic ?? this.preferIndic,
    englishModel: englishModel ?? this.englishModel,
    reprocessing: reprocessing ?? this.reprocessing,
    speakers: speakers ?? this.speakers,
    audioDeleted: audioDeleted ?? this.audioDeleted,
    flacFailures: flacFailures ?? this.flacFailures,
    tasksStatus: tasksStatus ?? this.tasksStatus,
    tasksPart: tasksPart ?? this.tasksPart,
    tasksWork: tasksWork ?? this.tasksWork,
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
      languages: data.languages.present ? data.languages.value : this.languages,
      preferIndic: data.preferIndic.present
          ? data.preferIndic.value
          : this.preferIndic,
      englishModel: data.englishModel.present
          ? data.englishModel.value
          : this.englishModel,
      reprocessing: data.reprocessing.present
          ? data.reprocessing.value
          : this.reprocessing,
      speakers: data.speakers.present ? data.speakers.value : this.speakers,
      audioDeleted: data.audioDeleted.present
          ? data.audioDeleted.value
          : this.audioDeleted,
      flacFailures: data.flacFailures.present
          ? data.flacFailures.value
          : this.flacFailures,
      tasksStatus: data.tasksStatus.present
          ? data.tasksStatus.value
          : this.tasksStatus,
      tasksPart: data.tasksPart.present ? data.tasksPart.value : this.tasksPart,
      tasksWork: data.tasksWork.present ? data.tasksWork.value : this.tasksWork,
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
          ..write('attempts: $attempts, ')
          ..write('languages: $languages, ')
          ..write('preferIndic: $preferIndic, ')
          ..write('englishModel: $englishModel, ')
          ..write('reprocessing: $reprocessing, ')
          ..write('speakers: $speakers, ')
          ..write('audioDeleted: $audioDeleted, ')
          ..write('flacFailures: $flacFailures, ')
          ..write('tasksStatus: $tasksStatus, ')
          ..write('tasksPart: $tasksPart, ')
          ..write('tasksWork: $tasksWork')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
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
    languages,
    preferIndic,
    englishModel,
    reprocessing,
    speakers,
    audioDeleted,
    flacFailures,
    tasksStatus,
    tasksPart,
    tasksWork,
  ]);
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
          other.attempts == this.attempts &&
          other.languages == this.languages &&
          other.preferIndic == this.preferIndic &&
          other.englishModel == this.englishModel &&
          other.reprocessing == this.reprocessing &&
          other.speakers == this.speakers &&
          other.audioDeleted == this.audioDeleted &&
          other.flacFailures == this.flacFailures &&
          other.tasksStatus == this.tasksStatus &&
          other.tasksPart == this.tasksPart &&
          other.tasksWork == this.tasksWork);
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
  final Value<String> languages;
  final Value<String> preferIndic;
  final Value<String> englishModel;
  final Value<bool> reprocessing;
  final Value<bool> speakers;
  final Value<bool> audioDeleted;
  final Value<int> flacFailures;
  final Value<String> tasksStatus;
  final Value<int> tasksPart;
  final Value<String> tasksWork;
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
    this.languages = const Value.absent(),
    this.preferIndic = const Value.absent(),
    this.englishModel = const Value.absent(),
    this.reprocessing = const Value.absent(),
    this.speakers = const Value.absent(),
    this.audioDeleted = const Value.absent(),
    this.flacFailures = const Value.absent(),
    this.tasksStatus = const Value.absent(),
    this.tasksPart = const Value.absent(),
    this.tasksWork = const Value.absent(),
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
    this.languages = const Value.absent(),
    this.preferIndic = const Value.absent(),
    this.englishModel = const Value.absent(),
    this.reprocessing = const Value.absent(),
    this.speakers = const Value.absent(),
    this.audioDeleted = const Value.absent(),
    this.flacFailures = const Value.absent(),
    this.tasksStatus = const Value.absent(),
    this.tasksPart = const Value.absent(),
    this.tasksWork = const Value.absent(),
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
    Expression<String>? languages,
    Expression<String>? preferIndic,
    Expression<String>? englishModel,
    Expression<bool>? reprocessing,
    Expression<bool>? speakers,
    Expression<bool>? audioDeleted,
    Expression<int>? flacFailures,
    Expression<String>? tasksStatus,
    Expression<int>? tasksPart,
    Expression<String>? tasksWork,
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
      if (languages != null) 'languages': languages,
      if (preferIndic != null) 'prefer_indic': preferIndic,
      if (englishModel != null) 'english_model': englishModel,
      if (reprocessing != null) 'reprocessing': reprocessing,
      if (speakers != null) 'speakers': speakers,
      if (audioDeleted != null) 'audio_deleted': audioDeleted,
      if (flacFailures != null) 'flac_failures': flacFailures,
      if (tasksStatus != null) 'tasks_status': tasksStatus,
      if (tasksPart != null) 'tasks_part': tasksPart,
      if (tasksWork != null) 'tasks_work': tasksWork,
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
    Value<String>? languages,
    Value<String>? preferIndic,
    Value<String>? englishModel,
    Value<bool>? reprocessing,
    Value<bool>? speakers,
    Value<bool>? audioDeleted,
    Value<int>? flacFailures,
    Value<String>? tasksStatus,
    Value<int>? tasksPart,
    Value<String>? tasksWork,
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
      languages: languages ?? this.languages,
      preferIndic: preferIndic ?? this.preferIndic,
      englishModel: englishModel ?? this.englishModel,
      reprocessing: reprocessing ?? this.reprocessing,
      speakers: speakers ?? this.speakers,
      audioDeleted: audioDeleted ?? this.audioDeleted,
      flacFailures: flacFailures ?? this.flacFailures,
      tasksStatus: tasksStatus ?? this.tasksStatus,
      tasksPart: tasksPart ?? this.tasksPart,
      tasksWork: tasksWork ?? this.tasksWork,
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
    if (languages.present) {
      map['languages'] = Variable<String>(languages.value);
    }
    if (preferIndic.present) {
      map['prefer_indic'] = Variable<String>(preferIndic.value);
    }
    if (englishModel.present) {
      map['english_model'] = Variable<String>(englishModel.value);
    }
    if (reprocessing.present) {
      map['reprocessing'] = Variable<bool>(reprocessing.value);
    }
    if (speakers.present) {
      map['speakers'] = Variable<bool>(speakers.value);
    }
    if (audioDeleted.present) {
      map['audio_deleted'] = Variable<bool>(audioDeleted.value);
    }
    if (flacFailures.present) {
      map['flac_failures'] = Variable<int>(flacFailures.value);
    }
    if (tasksStatus.present) {
      map['tasks_status'] = Variable<String>(tasksStatus.value);
    }
    if (tasksPart.present) {
      map['tasks_part'] = Variable<int>(tasksPart.value);
    }
    if (tasksWork.present) {
      map['tasks_work'] = Variable<String>(tasksWork.value);
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
          ..write('attempts: $attempts, ')
          ..write('languages: $languages, ')
          ..write('preferIndic: $preferIndic, ')
          ..write('englishModel: $englishModel, ')
          ..write('reprocessing: $reprocessing, ')
          ..write('speakers: $speakers, ')
          ..write('audioDeleted: $audioDeleted, ')
          ..write('flacFailures: $flacFailures, ')
          ..write('tasksStatus: $tasksStatus, ')
          ..write('tasksPart: $tasksPart, ')
          ..write('tasksWork: $tasksWork')
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
  static const VerificationMeta _draftMeta = const VerificationMeta('draft');
  @override
  late final GeneratedColumn<bool> draft = GeneratedColumn<bool>(
    'draft',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("draft" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _voicesJsonMeta = const VerificationMeta(
    'voicesJson',
  );
  @override
  late final GeneratedColumn<String> voicesJson = GeneratedColumn<String>(
    'voices_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _speakerMeta = const VerificationMeta(
    'speaker',
  );
  @override
  late final GeneratedColumn<String> speaker = GeneratedColumn<String>(
    'speaker',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _speakerGroupMeta = const VerificationMeta(
    'speakerGroup',
  );
  @override
  late final GeneratedColumn<int> speakerGroup = GeneratedColumn<int>(
    'speaker_group',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    meetingId,
    startMs,
    endMs,
    content,
    wordsJson,
    draft,
    voicesJson,
    speaker,
    speakerGroup,
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
    if (data.containsKey('draft')) {
      context.handle(
        _draftMeta,
        draft.isAcceptableOrUnknown(data['draft']!, _draftMeta),
      );
    }
    if (data.containsKey('voices_json')) {
      context.handle(
        _voicesJsonMeta,
        voicesJson.isAcceptableOrUnknown(data['voices_json']!, _voicesJsonMeta),
      );
    }
    if (data.containsKey('speaker')) {
      context.handle(
        _speakerMeta,
        speaker.isAcceptableOrUnknown(data['speaker']!, _speakerMeta),
      );
    }
    if (data.containsKey('speaker_group')) {
      context.handle(
        _speakerGroupMeta,
        speakerGroup.isAcceptableOrUnknown(
          data['speaker_group']!,
          _speakerGroupMeta,
        ),
      );
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
      draft: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}draft'],
      )!,
      voicesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}voices_json'],
      )!,
      speaker: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}speaker'],
      ),
      speakerGroup: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}speaker_group'],
      ),
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

  /// `[["word", startMs, endMs], …]`, with the confidence as a fourth value when known.
  final String wordsJson;

  /// A line of a run of Process again not finished yet: not shown; it replaces
  /// the recording's lines when the run completes.
  final bool draft;

  /// Voice prints: `[[startMs, endMs, "<base64 float32>"], …]`.
  final String voicesJson;

  /// Who said it (the name shown) and the recording's speaker group.
  final String? speaker;
  final int? speakerGroup;
  const TranscriptLine({
    required this.id,
    required this.meetingId,
    required this.startMs,
    required this.endMs,
    required this.content,
    required this.wordsJson,
    required this.draft,
    required this.voicesJson,
    this.speaker,
    this.speakerGroup,
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
    map['draft'] = Variable<bool>(draft);
    map['voices_json'] = Variable<String>(voicesJson);
    if (!nullToAbsent || speaker != null) {
      map['speaker'] = Variable<String>(speaker);
    }
    if (!nullToAbsent || speakerGroup != null) {
      map['speaker_group'] = Variable<int>(speakerGroup);
    }
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
      draft: Value(draft),
      voicesJson: Value(voicesJson),
      speaker: speaker == null && nullToAbsent
          ? const Value.absent()
          : Value(speaker),
      speakerGroup: speakerGroup == null && nullToAbsent
          ? const Value.absent()
          : Value(speakerGroup),
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
      draft: serializer.fromJson<bool>(json['draft']),
      voicesJson: serializer.fromJson<String>(json['voicesJson']),
      speaker: serializer.fromJson<String?>(json['speaker']),
      speakerGroup: serializer.fromJson<int?>(json['speakerGroup']),
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
      'draft': serializer.toJson<bool>(draft),
      'voicesJson': serializer.toJson<String>(voicesJson),
      'speaker': serializer.toJson<String?>(speaker),
      'speakerGroup': serializer.toJson<int?>(speakerGroup),
    };
  }

  TranscriptLine copyWith({
    int? id,
    int? meetingId,
    int? startMs,
    int? endMs,
    String? content,
    String? wordsJson,
    bool? draft,
    String? voicesJson,
    Value<String?> speaker = const Value.absent(),
    Value<int?> speakerGroup = const Value.absent(),
  }) => TranscriptLine(
    id: id ?? this.id,
    meetingId: meetingId ?? this.meetingId,
    startMs: startMs ?? this.startMs,
    endMs: endMs ?? this.endMs,
    content: content ?? this.content,
    wordsJson: wordsJson ?? this.wordsJson,
    draft: draft ?? this.draft,
    voicesJson: voicesJson ?? this.voicesJson,
    speaker: speaker.present ? speaker.value : this.speaker,
    speakerGroup: speakerGroup.present ? speakerGroup.value : this.speakerGroup,
  );
  TranscriptLine copyWithCompanion(TranscriptLinesCompanion data) {
    return TranscriptLine(
      id: data.id.present ? data.id.value : this.id,
      meetingId: data.meetingId.present ? data.meetingId.value : this.meetingId,
      startMs: data.startMs.present ? data.startMs.value : this.startMs,
      endMs: data.endMs.present ? data.endMs.value : this.endMs,
      content: data.content.present ? data.content.value : this.content,
      wordsJson: data.wordsJson.present ? data.wordsJson.value : this.wordsJson,
      draft: data.draft.present ? data.draft.value : this.draft,
      voicesJson: data.voicesJson.present
          ? data.voicesJson.value
          : this.voicesJson,
      speaker: data.speaker.present ? data.speaker.value : this.speaker,
      speakerGroup: data.speakerGroup.present
          ? data.speakerGroup.value
          : this.speakerGroup,
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
          ..write('wordsJson: $wordsJson, ')
          ..write('draft: $draft, ')
          ..write('voicesJson: $voicesJson, ')
          ..write('speaker: $speaker, ')
          ..write('speakerGroup: $speakerGroup')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    meetingId,
    startMs,
    endMs,
    content,
    wordsJson,
    draft,
    voicesJson,
    speaker,
    speakerGroup,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TranscriptLine &&
          other.id == this.id &&
          other.meetingId == this.meetingId &&
          other.startMs == this.startMs &&
          other.endMs == this.endMs &&
          other.content == this.content &&
          other.wordsJson == this.wordsJson &&
          other.draft == this.draft &&
          other.voicesJson == this.voicesJson &&
          other.speaker == this.speaker &&
          other.speakerGroup == this.speakerGroup);
}

class TranscriptLinesCompanion extends UpdateCompanion<TranscriptLine> {
  final Value<int> id;
  final Value<int> meetingId;
  final Value<int> startMs;
  final Value<int> endMs;
  final Value<String> content;
  final Value<String> wordsJson;
  final Value<bool> draft;
  final Value<String> voicesJson;
  final Value<String?> speaker;
  final Value<int?> speakerGroup;
  const TranscriptLinesCompanion({
    this.id = const Value.absent(),
    this.meetingId = const Value.absent(),
    this.startMs = const Value.absent(),
    this.endMs = const Value.absent(),
    this.content = const Value.absent(),
    this.wordsJson = const Value.absent(),
    this.draft = const Value.absent(),
    this.voicesJson = const Value.absent(),
    this.speaker = const Value.absent(),
    this.speakerGroup = const Value.absent(),
  });
  TranscriptLinesCompanion.insert({
    this.id = const Value.absent(),
    required int meetingId,
    required int startMs,
    required int endMs,
    required String content,
    required String wordsJson,
    this.draft = const Value.absent(),
    this.voicesJson = const Value.absent(),
    this.speaker = const Value.absent(),
    this.speakerGroup = const Value.absent(),
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
    Expression<bool>? draft,
    Expression<String>? voicesJson,
    Expression<String>? speaker,
    Expression<int>? speakerGroup,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (meetingId != null) 'meeting_id': meetingId,
      if (startMs != null) 'start_ms': startMs,
      if (endMs != null) 'end_ms': endMs,
      if (content != null) 'text': content,
      if (wordsJson != null) 'words_json': wordsJson,
      if (draft != null) 'draft': draft,
      if (voicesJson != null) 'voices_json': voicesJson,
      if (speaker != null) 'speaker': speaker,
      if (speakerGroup != null) 'speaker_group': speakerGroup,
    });
  }

  TranscriptLinesCompanion copyWith({
    Value<int>? id,
    Value<int>? meetingId,
    Value<int>? startMs,
    Value<int>? endMs,
    Value<String>? content,
    Value<String>? wordsJson,
    Value<bool>? draft,
    Value<String>? voicesJson,
    Value<String?>? speaker,
    Value<int?>? speakerGroup,
  }) {
    return TranscriptLinesCompanion(
      id: id ?? this.id,
      meetingId: meetingId ?? this.meetingId,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      content: content ?? this.content,
      wordsJson: wordsJson ?? this.wordsJson,
      draft: draft ?? this.draft,
      voicesJson: voicesJson ?? this.voicesJson,
      speaker: speaker ?? this.speaker,
      speakerGroup: speakerGroup ?? this.speakerGroup,
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
    if (draft.present) {
      map['draft'] = Variable<bool>(draft.value);
    }
    if (voicesJson.present) {
      map['voices_json'] = Variable<String>(voicesJson.value);
    }
    if (speaker.present) {
      map['speaker'] = Variable<String>(speaker.value);
    }
    if (speakerGroup.present) {
      map['speaker_group'] = Variable<int>(speakerGroup.value);
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
          ..write('wordsJson: $wordsJson, ')
          ..write('draft: $draft, ')
          ..write('voicesJson: $voicesJson, ')
          ..write('speaker: $speaker, ')
          ..write('speakerGroup: $speakerGroup')
          ..write(')'))
        .toString();
  }
}

class $MeetingSpeakersTable extends MeetingSpeakers
    with TableInfo<$MeetingSpeakersTable, MeetingSpeaker> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MeetingSpeakersTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<int> groupId = GeneratedColumn<int>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _printB64Meta = const VerificationMeta(
    'printB64',
  );
  @override
  late final GeneratedColumn<String> printB64 = GeneratedColumn<String>(
    'print_b64',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _speechMsMeta = const VerificationMeta(
    'speechMs',
  );
  @override
  late final GeneratedColumn<int> speechMs = GeneratedColumn<int>(
    'speech_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _draftMeta = const VerificationMeta('draft');
  @override
  late final GeneratedColumn<bool> draft = GeneratedColumn<bool>(
    'draft',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("draft" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    meetingId,
    groupId,
    label,
    printB64,
    speechMs,
    draft,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meeting_speakers';
  @override
  VerificationContext validateIntegrity(
    Insertable<MeetingSpeaker> instance, {
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
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('print_b64')) {
      context.handle(
        _printB64Meta,
        printB64.isAcceptableOrUnknown(data['print_b64']!, _printB64Meta),
      );
    } else if (isInserting) {
      context.missing(_printB64Meta);
    }
    if (data.containsKey('speech_ms')) {
      context.handle(
        _speechMsMeta,
        speechMs.isAcceptableOrUnknown(data['speech_ms']!, _speechMsMeta),
      );
    } else if (isInserting) {
      context.missing(_speechMsMeta);
    }
    if (data.containsKey('draft')) {
      context.handle(
        _draftMeta,
        draft.isAcceptableOrUnknown(data['draft']!, _draftMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MeetingSpeaker map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MeetingSpeaker(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      meetingId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}meeting_id'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}group_id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      printB64: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}print_b64'],
      )!,
      speechMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}speech_ms'],
      )!,
      draft: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}draft'],
      )!,
    );
  }

  @override
  $MeetingSpeakersTable createAlias(String alias) {
    return $MeetingSpeakersTable(attachedDatabase, alias);
  }
}

class MeetingSpeaker extends DataClass implements Insertable<MeetingSpeaker> {
  final int id;
  final int meetingId;
  final int groupId;
  final String label;
  final String printB64;
  final int speechMs;
  final bool draft;
  const MeetingSpeaker({
    required this.id,
    required this.meetingId,
    required this.groupId,
    required this.label,
    required this.printB64,
    required this.speechMs,
    required this.draft,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['meeting_id'] = Variable<int>(meetingId);
    map['group_id'] = Variable<int>(groupId);
    map['label'] = Variable<String>(label);
    map['print_b64'] = Variable<String>(printB64);
    map['speech_ms'] = Variable<int>(speechMs);
    map['draft'] = Variable<bool>(draft);
    return map;
  }

  MeetingSpeakersCompanion toCompanion(bool nullToAbsent) {
    return MeetingSpeakersCompanion(
      id: Value(id),
      meetingId: Value(meetingId),
      groupId: Value(groupId),
      label: Value(label),
      printB64: Value(printB64),
      speechMs: Value(speechMs),
      draft: Value(draft),
    );
  }

  factory MeetingSpeaker.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MeetingSpeaker(
      id: serializer.fromJson<int>(json['id']),
      meetingId: serializer.fromJson<int>(json['meetingId']),
      groupId: serializer.fromJson<int>(json['groupId']),
      label: serializer.fromJson<String>(json['label']),
      printB64: serializer.fromJson<String>(json['printB64']),
      speechMs: serializer.fromJson<int>(json['speechMs']),
      draft: serializer.fromJson<bool>(json['draft']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'meetingId': serializer.toJson<int>(meetingId),
      'groupId': serializer.toJson<int>(groupId),
      'label': serializer.toJson<String>(label),
      'printB64': serializer.toJson<String>(printB64),
      'speechMs': serializer.toJson<int>(speechMs),
      'draft': serializer.toJson<bool>(draft),
    };
  }

  MeetingSpeaker copyWith({
    int? id,
    int? meetingId,
    int? groupId,
    String? label,
    String? printB64,
    int? speechMs,
    bool? draft,
  }) => MeetingSpeaker(
    id: id ?? this.id,
    meetingId: meetingId ?? this.meetingId,
    groupId: groupId ?? this.groupId,
    label: label ?? this.label,
    printB64: printB64 ?? this.printB64,
    speechMs: speechMs ?? this.speechMs,
    draft: draft ?? this.draft,
  );
  MeetingSpeaker copyWithCompanion(MeetingSpeakersCompanion data) {
    return MeetingSpeaker(
      id: data.id.present ? data.id.value : this.id,
      meetingId: data.meetingId.present ? data.meetingId.value : this.meetingId,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      label: data.label.present ? data.label.value : this.label,
      printB64: data.printB64.present ? data.printB64.value : this.printB64,
      speechMs: data.speechMs.present ? data.speechMs.value : this.speechMs,
      draft: data.draft.present ? data.draft.value : this.draft,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MeetingSpeaker(')
          ..write('id: $id, ')
          ..write('meetingId: $meetingId, ')
          ..write('groupId: $groupId, ')
          ..write('label: $label, ')
          ..write('printB64: $printB64, ')
          ..write('speechMs: $speechMs, ')
          ..write('draft: $draft')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, meetingId, groupId, label, printB64, speechMs, draft);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MeetingSpeaker &&
          other.id == this.id &&
          other.meetingId == this.meetingId &&
          other.groupId == this.groupId &&
          other.label == this.label &&
          other.printB64 == this.printB64 &&
          other.speechMs == this.speechMs &&
          other.draft == this.draft);
}

class MeetingSpeakersCompanion extends UpdateCompanion<MeetingSpeaker> {
  final Value<int> id;
  final Value<int> meetingId;
  final Value<int> groupId;
  final Value<String> label;
  final Value<String> printB64;
  final Value<int> speechMs;
  final Value<bool> draft;
  const MeetingSpeakersCompanion({
    this.id = const Value.absent(),
    this.meetingId = const Value.absent(),
    this.groupId = const Value.absent(),
    this.label = const Value.absent(),
    this.printB64 = const Value.absent(),
    this.speechMs = const Value.absent(),
    this.draft = const Value.absent(),
  });
  MeetingSpeakersCompanion.insert({
    this.id = const Value.absent(),
    required int meetingId,
    required int groupId,
    required String label,
    required String printB64,
    required int speechMs,
    this.draft = const Value.absent(),
  }) : meetingId = Value(meetingId),
       groupId = Value(groupId),
       label = Value(label),
       printB64 = Value(printB64),
       speechMs = Value(speechMs);
  static Insertable<MeetingSpeaker> custom({
    Expression<int>? id,
    Expression<int>? meetingId,
    Expression<int>? groupId,
    Expression<String>? label,
    Expression<String>? printB64,
    Expression<int>? speechMs,
    Expression<bool>? draft,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (meetingId != null) 'meeting_id': meetingId,
      if (groupId != null) 'group_id': groupId,
      if (label != null) 'label': label,
      if (printB64 != null) 'print_b64': printB64,
      if (speechMs != null) 'speech_ms': speechMs,
      if (draft != null) 'draft': draft,
    });
  }

  MeetingSpeakersCompanion copyWith({
    Value<int>? id,
    Value<int>? meetingId,
    Value<int>? groupId,
    Value<String>? label,
    Value<String>? printB64,
    Value<int>? speechMs,
    Value<bool>? draft,
  }) {
    return MeetingSpeakersCompanion(
      id: id ?? this.id,
      meetingId: meetingId ?? this.meetingId,
      groupId: groupId ?? this.groupId,
      label: label ?? this.label,
      printB64: printB64 ?? this.printB64,
      speechMs: speechMs ?? this.speechMs,
      draft: draft ?? this.draft,
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
    if (groupId.present) {
      map['group_id'] = Variable<int>(groupId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (printB64.present) {
      map['print_b64'] = Variable<String>(printB64.value);
    }
    if (speechMs.present) {
      map['speech_ms'] = Variable<int>(speechMs.value);
    }
    if (draft.present) {
      map['draft'] = Variable<bool>(draft.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MeetingSpeakersCompanion(')
          ..write('id: $id, ')
          ..write('meetingId: $meetingId, ')
          ..write('groupId: $groupId, ')
          ..write('label: $label, ')
          ..write('printB64: $printB64, ')
          ..write('speechMs: $speechMs, ')
          ..write('draft: $draft')
          ..write(')'))
        .toString();
  }
}

class $PeopleTable extends People with TableInfo<$PeopleTable, PeopleData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeopleTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameKeyMeta = const VerificationMeta(
    'nameKey',
  );
  @override
  late final GeneratedColumn<String> nameKey = GeneratedColumn<String>(
    'name_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _printB64Meta = const VerificationMeta(
    'printB64',
  );
  @override
  late final GeneratedColumn<String> printB64 = GeneratedColumn<String>(
    'print_b64',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _speechMsMeta = const VerificationMeta(
    'speechMs',
  );
  @override
  late final GeneratedColumn<int> speechMs = GeneratedColumn<int>(
    'speech_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    nameKey,
    printB64,
    speechMs,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'people';
  @override
  VerificationContext validateIntegrity(
    Insertable<PeopleData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('name_key')) {
      context.handle(
        _nameKeyMeta,
        nameKey.isAcceptableOrUnknown(data['name_key']!, _nameKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_nameKeyMeta);
    }
    if (data.containsKey('print_b64')) {
      context.handle(
        _printB64Meta,
        printB64.isAcceptableOrUnknown(data['print_b64']!, _printB64Meta),
      );
    } else if (isInserting) {
      context.missing(_printB64Meta);
    }
    if (data.containsKey('speech_ms')) {
      context.handle(
        _speechMsMeta,
        speechMs.isAcceptableOrUnknown(data['speech_ms']!, _speechMsMeta),
      );
    } else if (isInserting) {
      context.missing(_speechMsMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PeopleData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PeopleData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_key'],
      )!,
      printB64: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}print_b64'],
      )!,
      speechMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}speech_ms'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PeopleTable createAlias(String alias) {
    return $PeopleTable(attachedDatabase, alias);
  }
}

class PeopleData extends DataClass implements Insertable<PeopleData> {
  final int id;
  final String name;

  /// The name in lowercase: one person per name, whatever its case.
  final String nameKey;
  final String printB64;
  final int speechMs;
  final DateTime updatedAt;
  const PeopleData({
    required this.id,
    required this.name,
    required this.nameKey,
    required this.printB64,
    required this.speechMs,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['name_key'] = Variable<String>(nameKey);
    map['print_b64'] = Variable<String>(printB64);
    map['speech_ms'] = Variable<int>(speechMs);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PeopleCompanion toCompanion(bool nullToAbsent) {
    return PeopleCompanion(
      id: Value(id),
      name: Value(name),
      nameKey: Value(nameKey),
      printB64: Value(printB64),
      speechMs: Value(speechMs),
      updatedAt: Value(updatedAt),
    );
  }

  factory PeopleData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PeopleData(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      nameKey: serializer.fromJson<String>(json['nameKey']),
      printB64: serializer.fromJson<String>(json['printB64']),
      speechMs: serializer.fromJson<int>(json['speechMs']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'nameKey': serializer.toJson<String>(nameKey),
      'printB64': serializer.toJson<String>(printB64),
      'speechMs': serializer.toJson<int>(speechMs),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PeopleData copyWith({
    int? id,
    String? name,
    String? nameKey,
    String? printB64,
    int? speechMs,
    DateTime? updatedAt,
  }) => PeopleData(
    id: id ?? this.id,
    name: name ?? this.name,
    nameKey: nameKey ?? this.nameKey,
    printB64: printB64 ?? this.printB64,
    speechMs: speechMs ?? this.speechMs,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PeopleData copyWithCompanion(PeopleCompanion data) {
    return PeopleData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      nameKey: data.nameKey.present ? data.nameKey.value : this.nameKey,
      printB64: data.printB64.present ? data.printB64.value : this.printB64,
      speechMs: data.speechMs.present ? data.speechMs.value : this.speechMs,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PeopleData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameKey: $nameKey, ')
          ..write('printB64: $printB64, ')
          ..write('speechMs: $speechMs, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, nameKey, printB64, speechMs, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PeopleData &&
          other.id == this.id &&
          other.name == this.name &&
          other.nameKey == this.nameKey &&
          other.printB64 == this.printB64 &&
          other.speechMs == this.speechMs &&
          other.updatedAt == this.updatedAt);
}

class PeopleCompanion extends UpdateCompanion<PeopleData> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> nameKey;
  final Value<String> printB64;
  final Value<int> speechMs;
  final Value<DateTime> updatedAt;
  const PeopleCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameKey = const Value.absent(),
    this.printB64 = const Value.absent(),
    this.speechMs = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  PeopleCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String nameKey,
    required String printB64,
    required int speechMs,
    required DateTime updatedAt,
  }) : name = Value(name),
       nameKey = Value(nameKey),
       printB64 = Value(printB64),
       speechMs = Value(speechMs),
       updatedAt = Value(updatedAt);
  static Insertable<PeopleData> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? nameKey,
    Expression<String>? printB64,
    Expression<int>? speechMs,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nameKey != null) 'name_key': nameKey,
      if (printB64 != null) 'print_b64': printB64,
      if (speechMs != null) 'speech_ms': speechMs,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  PeopleCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? nameKey,
    Value<String>? printB64,
    Value<int>? speechMs,
    Value<DateTime>? updatedAt,
  }) {
    return PeopleCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nameKey: nameKey ?? this.nameKey,
      printB64: printB64 ?? this.printB64,
      speechMs: speechMs ?? this.speechMs,
      updatedAt: updatedAt ?? this.updatedAt,
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
    if (nameKey.present) {
      map['name_key'] = Variable<String>(nameKey.value);
    }
    if (printB64.present) {
      map['print_b64'] = Variable<String>(printB64.value);
    }
    if (speechMs.present) {
      map['speech_ms'] = Variable<int>(speechMs.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeopleCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameKey: $nameKey, ')
          ..write('printB64: $printB64, ')
          ..write('speechMs: $speechMs, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, TaskRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
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
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES meetings (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assignedByMeta = const VerificationMeta(
    'assignedBy',
  );
  @override
  late final GeneratedColumn<String> assignedBy = GeneratedColumn<String>(
    'assigned_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueMeta = const VerificationMeta('due');
  @override
  late final GeneratedColumn<String> due = GeneratedColumn<String>(
    'due',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _quoteMeta = const VerificationMeta('quote');
  @override
  late final GeneratedColumn<String> quote = GeneratedColumn<String>(
    'quote',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _quoteMsMeta = const VerificationMeta(
    'quoteMs',
  );
  @override
  late final GeneratedColumn<int> quoteMs = GeneratedColumn<int>(
    'quote_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _doneMeta = const VerificationMeta('done');
  @override
  late final GeneratedColumn<bool> done = GeneratedColumn<bool>(
    'done',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("done" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromAiMeta = const VerificationMeta('fromAi');
  @override
  late final GeneratedColumn<bool> fromAi = GeneratedColumn<bool>(
    'from_ai',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("from_ai" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _editedMeta = const VerificationMeta('edited');
  @override
  late final GeneratedColumn<bool> edited = GeneratedColumn<bool>(
    'edited',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("edited" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    meetingId,
    description,
    assignedBy,
    due,
    quote,
    quoteMs,
    done,
    position,
    fromAi,
    edited,
    deleted,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskRow> instance, {
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
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('assigned_by')) {
      context.handle(
        _assignedByMeta,
        assignedBy.isAcceptableOrUnknown(data['assigned_by']!, _assignedByMeta),
      );
    }
    if (data.containsKey('due')) {
      context.handle(
        _dueMeta,
        due.isAcceptableOrUnknown(data['due']!, _dueMeta),
      );
    }
    if (data.containsKey('quote')) {
      context.handle(
        _quoteMeta,
        quote.isAcceptableOrUnknown(data['quote']!, _quoteMeta),
      );
    }
    if (data.containsKey('quote_ms')) {
      context.handle(
        _quoteMsMeta,
        quoteMs.isAcceptableOrUnknown(data['quote_ms']!, _quoteMsMeta),
      );
    }
    if (data.containsKey('done')) {
      context.handle(
        _doneMeta,
        done.isAcceptableOrUnknown(data['done']!, _doneMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('from_ai')) {
      context.handle(
        _fromAiMeta,
        fromAi.isAcceptableOrUnknown(data['from_ai']!, _fromAiMeta),
      );
    }
    if (data.containsKey('edited')) {
      context.handle(
        _editedMeta,
        edited.isAcceptableOrUnknown(data['edited']!, _editedMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      meetingId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}meeting_id'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      assignedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assigned_by'],
      ),
      due: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}due'],
      ),
      quote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quote'],
      ),
      quoteMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quote_ms'],
      ),
      done: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}done'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      fromAi: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}from_ai'],
      )!,
      edited: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}edited'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }
}

class TaskRow extends DataClass implements Insertable<TaskRow> {
  final int id;

  /// The recording it came from (null: added on the Tasks tab).
  final int? meetingId;
  final String description;
  final String? assignedBy;
  final String? due;
  final String? quote;

  /// Where the quoted line starts in the recording.
  final int? quoteMs;
  final bool done;

  /// Its place on the Tasks tab.
  final int position;

  /// Found by the task AI (not added by the owner).
  final bool fromAi;

  /// Changed or ticked by the owner: a re-run keeps it.
  final bool edited;

  /// An AI task the owner deleted: hidden, kept so a re-run doesn't find it again.
  final bool deleted;
  final DateTime createdAt;
  const TaskRow({
    required this.id,
    this.meetingId,
    required this.description,
    this.assignedBy,
    this.due,
    this.quote,
    this.quoteMs,
    required this.done,
    required this.position,
    required this.fromAi,
    required this.edited,
    required this.deleted,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || meetingId != null) {
      map['meeting_id'] = Variable<int>(meetingId);
    }
    map['description'] = Variable<String>(description);
    if (!nullToAbsent || assignedBy != null) {
      map['assigned_by'] = Variable<String>(assignedBy);
    }
    if (!nullToAbsent || due != null) {
      map['due'] = Variable<String>(due);
    }
    if (!nullToAbsent || quote != null) {
      map['quote'] = Variable<String>(quote);
    }
    if (!nullToAbsent || quoteMs != null) {
      map['quote_ms'] = Variable<int>(quoteMs);
    }
    map['done'] = Variable<bool>(done);
    map['position'] = Variable<int>(position);
    map['from_ai'] = Variable<bool>(fromAi);
    map['edited'] = Variable<bool>(edited);
    map['deleted'] = Variable<bool>(deleted);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      meetingId: meetingId == null && nullToAbsent
          ? const Value.absent()
          : Value(meetingId),
      description: Value(description),
      assignedBy: assignedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(assignedBy),
      due: due == null && nullToAbsent ? const Value.absent() : Value(due),
      quote: quote == null && nullToAbsent
          ? const Value.absent()
          : Value(quote),
      quoteMs: quoteMs == null && nullToAbsent
          ? const Value.absent()
          : Value(quoteMs),
      done: Value(done),
      position: Value(position),
      fromAi: Value(fromAi),
      edited: Value(edited),
      deleted: Value(deleted),
      createdAt: Value(createdAt),
    );
  }

  factory TaskRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskRow(
      id: serializer.fromJson<int>(json['id']),
      meetingId: serializer.fromJson<int?>(json['meetingId']),
      description: serializer.fromJson<String>(json['description']),
      assignedBy: serializer.fromJson<String?>(json['assignedBy']),
      due: serializer.fromJson<String?>(json['due']),
      quote: serializer.fromJson<String?>(json['quote']),
      quoteMs: serializer.fromJson<int?>(json['quoteMs']),
      done: serializer.fromJson<bool>(json['done']),
      position: serializer.fromJson<int>(json['position']),
      fromAi: serializer.fromJson<bool>(json['fromAi']),
      edited: serializer.fromJson<bool>(json['edited']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'meetingId': serializer.toJson<int?>(meetingId),
      'description': serializer.toJson<String>(description),
      'assignedBy': serializer.toJson<String?>(assignedBy),
      'due': serializer.toJson<String?>(due),
      'quote': serializer.toJson<String?>(quote),
      'quoteMs': serializer.toJson<int?>(quoteMs),
      'done': serializer.toJson<bool>(done),
      'position': serializer.toJson<int>(position),
      'fromAi': serializer.toJson<bool>(fromAi),
      'edited': serializer.toJson<bool>(edited),
      'deleted': serializer.toJson<bool>(deleted),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  TaskRow copyWith({
    int? id,
    Value<int?> meetingId = const Value.absent(),
    String? description,
    Value<String?> assignedBy = const Value.absent(),
    Value<String?> due = const Value.absent(),
    Value<String?> quote = const Value.absent(),
    Value<int?> quoteMs = const Value.absent(),
    bool? done,
    int? position,
    bool? fromAi,
    bool? edited,
    bool? deleted,
    DateTime? createdAt,
  }) => TaskRow(
    id: id ?? this.id,
    meetingId: meetingId.present ? meetingId.value : this.meetingId,
    description: description ?? this.description,
    assignedBy: assignedBy.present ? assignedBy.value : this.assignedBy,
    due: due.present ? due.value : this.due,
    quote: quote.present ? quote.value : this.quote,
    quoteMs: quoteMs.present ? quoteMs.value : this.quoteMs,
    done: done ?? this.done,
    position: position ?? this.position,
    fromAi: fromAi ?? this.fromAi,
    edited: edited ?? this.edited,
    deleted: deleted ?? this.deleted,
    createdAt: createdAt ?? this.createdAt,
  );
  TaskRow copyWithCompanion(TasksCompanion data) {
    return TaskRow(
      id: data.id.present ? data.id.value : this.id,
      meetingId: data.meetingId.present ? data.meetingId.value : this.meetingId,
      description: data.description.present
          ? data.description.value
          : this.description,
      assignedBy: data.assignedBy.present
          ? data.assignedBy.value
          : this.assignedBy,
      due: data.due.present ? data.due.value : this.due,
      quote: data.quote.present ? data.quote.value : this.quote,
      quoteMs: data.quoteMs.present ? data.quoteMs.value : this.quoteMs,
      done: data.done.present ? data.done.value : this.done,
      position: data.position.present ? data.position.value : this.position,
      fromAi: data.fromAi.present ? data.fromAi.value : this.fromAi,
      edited: data.edited.present ? data.edited.value : this.edited,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskRow(')
          ..write('id: $id, ')
          ..write('meetingId: $meetingId, ')
          ..write('description: $description, ')
          ..write('assignedBy: $assignedBy, ')
          ..write('due: $due, ')
          ..write('quote: $quote, ')
          ..write('quoteMs: $quoteMs, ')
          ..write('done: $done, ')
          ..write('position: $position, ')
          ..write('fromAi: $fromAi, ')
          ..write('edited: $edited, ')
          ..write('deleted: $deleted, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    meetingId,
    description,
    assignedBy,
    due,
    quote,
    quoteMs,
    done,
    position,
    fromAi,
    edited,
    deleted,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskRow &&
          other.id == this.id &&
          other.meetingId == this.meetingId &&
          other.description == this.description &&
          other.assignedBy == this.assignedBy &&
          other.due == this.due &&
          other.quote == this.quote &&
          other.quoteMs == this.quoteMs &&
          other.done == this.done &&
          other.position == this.position &&
          other.fromAi == this.fromAi &&
          other.edited == this.edited &&
          other.deleted == this.deleted &&
          other.createdAt == this.createdAt);
}

class TasksCompanion extends UpdateCompanion<TaskRow> {
  final Value<int> id;
  final Value<int?> meetingId;
  final Value<String> description;
  final Value<String?> assignedBy;
  final Value<String?> due;
  final Value<String?> quote;
  final Value<int?> quoteMs;
  final Value<bool> done;
  final Value<int> position;
  final Value<bool> fromAi;
  final Value<bool> edited;
  final Value<bool> deleted;
  final Value<DateTime> createdAt;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.meetingId = const Value.absent(),
    this.description = const Value.absent(),
    this.assignedBy = const Value.absent(),
    this.due = const Value.absent(),
    this.quote = const Value.absent(),
    this.quoteMs = const Value.absent(),
    this.done = const Value.absent(),
    this.position = const Value.absent(),
    this.fromAi = const Value.absent(),
    this.edited = const Value.absent(),
    this.deleted = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  TasksCompanion.insert({
    this.id = const Value.absent(),
    this.meetingId = const Value.absent(),
    required String description,
    this.assignedBy = const Value.absent(),
    this.due = const Value.absent(),
    this.quote = const Value.absent(),
    this.quoteMs = const Value.absent(),
    this.done = const Value.absent(),
    required int position,
    this.fromAi = const Value.absent(),
    this.edited = const Value.absent(),
    this.deleted = const Value.absent(),
    required DateTime createdAt,
  }) : description = Value(description),
       position = Value(position),
       createdAt = Value(createdAt);
  static Insertable<TaskRow> custom({
    Expression<int>? id,
    Expression<int>? meetingId,
    Expression<String>? description,
    Expression<String>? assignedBy,
    Expression<String>? due,
    Expression<String>? quote,
    Expression<int>? quoteMs,
    Expression<bool>? done,
    Expression<int>? position,
    Expression<bool>? fromAi,
    Expression<bool>? edited,
    Expression<bool>? deleted,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (meetingId != null) 'meeting_id': meetingId,
      if (description != null) 'description': description,
      if (assignedBy != null) 'assigned_by': assignedBy,
      if (due != null) 'due': due,
      if (quote != null) 'quote': quote,
      if (quoteMs != null) 'quote_ms': quoteMs,
      if (done != null) 'done': done,
      if (position != null) 'position': position,
      if (fromAi != null) 'from_ai': fromAi,
      if (edited != null) 'edited': edited,
      if (deleted != null) 'deleted': deleted,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  TasksCompanion copyWith({
    Value<int>? id,
    Value<int?>? meetingId,
    Value<String>? description,
    Value<String?>? assignedBy,
    Value<String?>? due,
    Value<String?>? quote,
    Value<int?>? quoteMs,
    Value<bool>? done,
    Value<int>? position,
    Value<bool>? fromAi,
    Value<bool>? edited,
    Value<bool>? deleted,
    Value<DateTime>? createdAt,
  }) {
    return TasksCompanion(
      id: id ?? this.id,
      meetingId: meetingId ?? this.meetingId,
      description: description ?? this.description,
      assignedBy: assignedBy ?? this.assignedBy,
      due: due ?? this.due,
      quote: quote ?? this.quote,
      quoteMs: quoteMs ?? this.quoteMs,
      done: done ?? this.done,
      position: position ?? this.position,
      fromAi: fromAi ?? this.fromAi,
      edited: edited ?? this.edited,
      deleted: deleted ?? this.deleted,
      createdAt: createdAt ?? this.createdAt,
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
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (assignedBy.present) {
      map['assigned_by'] = Variable<String>(assignedBy.value);
    }
    if (due.present) {
      map['due'] = Variable<String>(due.value);
    }
    if (quote.present) {
      map['quote'] = Variable<String>(quote.value);
    }
    if (quoteMs.present) {
      map['quote_ms'] = Variable<int>(quoteMs.value);
    }
    if (done.present) {
      map['done'] = Variable<bool>(done.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (fromAi.present) {
      map['from_ai'] = Variable<bool>(fromAi.value);
    }
    if (edited.present) {
      map['edited'] = Variable<bool>(edited.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('meetingId: $meetingId, ')
          ..write('description: $description, ')
          ..write('assignedBy: $assignedBy, ')
          ..write('due: $due, ')
          ..write('quote: $quote, ')
          ..write('quoteMs: $quoteMs, ')
          ..write('done: $done, ')
          ..write('position: $position, ')
          ..write('fromAi: $fromAi, ')
          ..write('edited: $edited, ')
          ..write('deleted: $deleted, ')
          ..write('createdAt: $createdAt')
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
  late final $MeetingSpeakersTable meetingSpeakers = $MeetingSpeakersTable(
    this,
  );
  late final $PeopleTable people = $PeopleTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    meetings,
    settings,
    transcriptLines,
    meetingSpeakers,
    people,
    tasks,
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
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'meetings',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('meeting_speakers', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'meetings',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('tasks', kind: UpdateKind.delete)],
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
  Value<String> languages,
  Value<String> preferIndic,
  Value<String> englishModel,
  Value<bool> reprocessing,
  Value<bool> speakers,
  Value<bool> audioDeleted,
  Value<int> flacFailures,
  Value<String> tasksStatus,
  Value<int> tasksPart,
  Value<String> tasksWork,
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
  Value<String> languages,
  Value<String> preferIndic,
  Value<String> englishModel,
  Value<bool> reprocessing,
  Value<bool> speakers,
  Value<bool> audioDeleted,
  Value<int> flacFailures,
  Value<String> tasksStatus,
  Value<int> tasksPart,
  Value<String> tasksWork,
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

  static MultiTypedResultKey<$MeetingSpeakersTable, List<MeetingSpeaker>>
  _meetingSpeakersRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.meetingSpeakers,
    aliasName: 'meetings__id__meeting_speakers__meeting_id',
  );

  $$MeetingSpeakersTableProcessedTableManager get meetingSpeakersRefs {
    final manager = $$MeetingSpeakersTableTableManager(
      $_db,
      $_db.meetingSpeakers,
    ).filter((f) => f.meetingId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _meetingSpeakersRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TasksTable, List<TaskRow>> _tasksRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.tasks,
    aliasName: 'meetings__id__tasks__meeting_id',
  );

  $$TasksTableProcessedTableManager get tasksRefs {
    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.meetingId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_tasksRefsTable($_db));
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

  ColumnFilters<String> get languages => $composableBuilder(
    column: $table.languages,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preferIndic => $composableBuilder(
    column: $table.preferIndic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get englishModel => $composableBuilder(
    column: $table.englishModel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get reprocessing => $composableBuilder(
    column: $table.reprocessing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get speakers => $composableBuilder(
    column: $table.speakers,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get audioDeleted => $composableBuilder(
    column: $table.audioDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get flacFailures => $composableBuilder(
    column: $table.flacFailures,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tasksStatus => $composableBuilder(
    column: $table.tasksStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tasksPart => $composableBuilder(
    column: $table.tasksPart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tasksWork => $composableBuilder(
    column: $table.tasksWork,
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

  Expression<bool> meetingSpeakersRefs(
    Expression<bool> Function($$MeetingSpeakersTableFilterComposer f) f,
  ) {
    final $$MeetingSpeakersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.meetingSpeakers,
      getReferencedColumn: (t) => t.meetingId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MeetingSpeakersTableFilterComposer(
            $db: $db,
            $table: $db.meetingSpeakers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> tasksRefs(
    Expression<bool> Function($$TasksTableFilterComposer f) f,
  ) {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.meetingId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
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

  ColumnOrderings<String> get languages => $composableBuilder(
    column: $table.languages,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preferIndic => $composableBuilder(
    column: $table.preferIndic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get englishModel => $composableBuilder(
    column: $table.englishModel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get reprocessing => $composableBuilder(
    column: $table.reprocessing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get speakers => $composableBuilder(
    column: $table.speakers,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get audioDeleted => $composableBuilder(
    column: $table.audioDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get flacFailures => $composableBuilder(
    column: $table.flacFailures,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tasksStatus => $composableBuilder(
    column: $table.tasksStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tasksPart => $composableBuilder(
    column: $table.tasksPart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tasksWork => $composableBuilder(
    column: $table.tasksWork,
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

  GeneratedColumn<String> get languages =>
      $composableBuilder(column: $table.languages, builder: (column) => column);

  GeneratedColumn<String> get preferIndic => $composableBuilder(
    column: $table.preferIndic,
    builder: (column) => column,
  );

  GeneratedColumn<String> get englishModel => $composableBuilder(
    column: $table.englishModel,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get reprocessing => $composableBuilder(
    column: $table.reprocessing,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get speakers =>
      $composableBuilder(column: $table.speakers, builder: (column) => column);

  GeneratedColumn<bool> get audioDeleted => $composableBuilder(
    column: $table.audioDeleted,
    builder: (column) => column,
  );

  GeneratedColumn<int> get flacFailures => $composableBuilder(
    column: $table.flacFailures,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tasksStatus => $composableBuilder(
    column: $table.tasksStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tasksPart =>
      $composableBuilder(column: $table.tasksPart, builder: (column) => column);

  GeneratedColumn<String> get tasksWork =>
      $composableBuilder(column: $table.tasksWork, builder: (column) => column);

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

  Expression<T> meetingSpeakersRefs<T extends Object>(
    Expression<T> Function($$MeetingSpeakersTableAnnotationComposer a) f,
  ) {
    final $$MeetingSpeakersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.meetingSpeakers,
      getReferencedColumn: (t) => t.meetingId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MeetingSpeakersTableAnnotationComposer(
            $db: $db,
            $table: $db.meetingSpeakers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> tasksRefs<T extends Object>(
    Expression<T> Function($$TasksTableAnnotationComposer a) f,
  ) {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.meetingId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
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
          PrefetchHooks Function({
            bool transcriptLinesRefs,
            bool meetingSpeakersRefs,
            bool tasksRefs,
          })
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
                Value<String> languages = const Value.absent(),
                Value<String> preferIndic = const Value.absent(),
                Value<String> englishModel = const Value.absent(),
                Value<bool> reprocessing = const Value.absent(),
                Value<bool> speakers = const Value.absent(),
                Value<bool> audioDeleted = const Value.absent(),
                Value<int> flacFailures = const Value.absent(),
                Value<String> tasksStatus = const Value.absent(),
                Value<int> tasksPart = const Value.absent(),
                Value<String> tasksWork = const Value.absent(),
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
                languages: languages,
                preferIndic: preferIndic,
                englishModel: englishModel,
                reprocessing: reprocessing,
                speakers: speakers,
                audioDeleted: audioDeleted,
                flacFailures: flacFailures,
                tasksStatus: tasksStatus,
                tasksPart: tasksPart,
                tasksWork: tasksWork,
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
                Value<String> languages = const Value.absent(),
                Value<String> preferIndic = const Value.absent(),
                Value<String> englishModel = const Value.absent(),
                Value<bool> reprocessing = const Value.absent(),
                Value<bool> speakers = const Value.absent(),
                Value<bool> audioDeleted = const Value.absent(),
                Value<int> flacFailures = const Value.absent(),
                Value<String> tasksStatus = const Value.absent(),
                Value<int> tasksPart = const Value.absent(),
                Value<String> tasksWork = const Value.absent(),
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
                languages: languages,
                preferIndic: preferIndic,
                englishModel: englishModel,
                reprocessing: reprocessing,
                speakers: speakers,
                audioDeleted: audioDeleted,
                flacFailures: flacFailures,
                tasksStatus: tasksStatus,
                tasksPart: tasksPart,
                tasksWork: tasksWork,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MeetingsTable, Meeting>(table),
                  $$MeetingsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                transcriptLinesRefs = false,
                meetingSpeakersRefs = false,
                tasksRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (transcriptLinesRefs) db.transcriptLines,
                    if (meetingSpeakersRefs) db.meetingSpeakers,
                    if (tasksRefs) db.tasks,
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
                          managerFromTypedResult: (p0) =>
                              $$MeetingsTableReferences(
                                db,
                                table,
                                p0,
                              ).transcriptLinesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.meetingId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (meetingSpeakersRefs)
                        await $_getPrefetchedData<
                          Meeting,
                          $MeetingsTable,
                          MeetingSpeaker
                        >(
                          currentTable: table,
                          referencedTable: $$MeetingsTableReferences
                              ._meetingSpeakersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MeetingsTableReferences(
                                db,
                                table,
                                p0,
                              ).meetingSpeakersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.meetingId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (tasksRefs)
                        await $_getPrefetchedData<
                          Meeting,
                          $MeetingsTable,
                          TaskRow
                        >(
                          currentTable: table,
                          referencedTable: $$MeetingsTableReferences
                              ._tasksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MeetingsTableReferences(
                                db,
                                table,
                                p0,
                              ).tasksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.meetingId == item.id,
                              ),
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
      PrefetchHooks Function({
        bool transcriptLinesRefs,
        bool meetingSpeakersRefs,
        bool tasksRefs,
      })
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
      Value<bool> draft,
      Value<String> voicesJson,
      Value<String?> speaker,
      Value<int?> speakerGroup,
    });
typedef $$TranscriptLinesTableUpdateCompanionBuilder =
    TranscriptLinesCompanion Function({
      Value<int> id,
      Value<int> meetingId,
      Value<int> startMs,
      Value<int> endMs,
      Value<String> content,
      Value<String> wordsJson,
      Value<bool> draft,
      Value<String> voicesJson,
      Value<String?> speaker,
      Value<int?> speakerGroup,
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

  ColumnFilters<bool> get draft => $composableBuilder(
    column: $table.draft,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get voicesJson => $composableBuilder(
    column: $table.voicesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get speaker => $composableBuilder(
    column: $table.speaker,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get speakerGroup => $composableBuilder(
    column: $table.speakerGroup,
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

  ColumnOrderings<bool> get draft => $composableBuilder(
    column: $table.draft,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get voicesJson => $composableBuilder(
    column: $table.voicesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get speaker => $composableBuilder(
    column: $table.speaker,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get speakerGroup => $composableBuilder(
    column: $table.speakerGroup,
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

  GeneratedColumn<bool> get draft =>
      $composableBuilder(column: $table.draft, builder: (column) => column);

  GeneratedColumn<String> get voicesJson => $composableBuilder(
    column: $table.voicesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get speaker =>
      $composableBuilder(column: $table.speaker, builder: (column) => column);

  GeneratedColumn<int> get speakerGroup => $composableBuilder(
    column: $table.speakerGroup,
    builder: (column) => column,
  );

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
                Value<bool> draft = const Value.absent(),
                Value<String> voicesJson = const Value.absent(),
                Value<String?> speaker = const Value.absent(),
                Value<int?> speakerGroup = const Value.absent(),
              }) => TranscriptLinesCompanion(
                id: id,
                meetingId: meetingId,
                startMs: startMs,
                endMs: endMs,
                content: content,
                wordsJson: wordsJson,
                draft: draft,
                voicesJson: voicesJson,
                speaker: speaker,
                speakerGroup: speakerGroup,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int meetingId,
                required int startMs,
                required int endMs,
                required String content,
                required String wordsJson,
                Value<bool> draft = const Value.absent(),
                Value<String> voicesJson = const Value.absent(),
                Value<String?> speaker = const Value.absent(),
                Value<int?> speakerGroup = const Value.absent(),
              }) => TranscriptLinesCompanion.insert(
                id: id,
                meetingId: meetingId,
                startMs: startMs,
                endMs: endMs,
                content: content,
                wordsJson: wordsJson,
                draft: draft,
                voicesJson: voicesJson,
                speaker: speaker,
                speakerGroup: speakerGroup,
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
typedef $$MeetingSpeakersTableCreateCompanionBuilder =
    MeetingSpeakersCompanion Function({
      Value<int> id,
      required int meetingId,
      required int groupId,
      required String label,
      required String printB64,
      required int speechMs,
      Value<bool> draft,
    });
typedef $$MeetingSpeakersTableUpdateCompanionBuilder =
    MeetingSpeakersCompanion Function({
      Value<int> id,
      Value<int> meetingId,
      Value<int> groupId,
      Value<String> label,
      Value<String> printB64,
      Value<int> speechMs,
      Value<bool> draft,
    });

final class $$MeetingSpeakersTableReferences
    extends
        BaseReferences<_$AppDatabase, $MeetingSpeakersTable, MeetingSpeaker> {
  $$MeetingSpeakersTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MeetingsTable _meetingIdTable(_$AppDatabase db) =>
      db.meetings.createAlias('meeting_speakers__meeting_id__meetings__id');

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

class $$MeetingSpeakersTableFilterComposer
    extends Composer<_$AppDatabase, $MeetingSpeakersTable> {
  $$MeetingSpeakersTableFilterComposer({
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

  ColumnFilters<int> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get printB64 => $composableBuilder(
    column: $table.printB64,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get speechMs => $composableBuilder(
    column: $table.speechMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get draft => $composableBuilder(
    column: $table.draft,
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

class $$MeetingSpeakersTableOrderingComposer
    extends Composer<_$AppDatabase, $MeetingSpeakersTable> {
  $$MeetingSpeakersTableOrderingComposer({
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

  ColumnOrderings<int> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get printB64 => $composableBuilder(
    column: $table.printB64,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get speechMs => $composableBuilder(
    column: $table.speechMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get draft => $composableBuilder(
    column: $table.draft,
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

class $$MeetingSpeakersTableAnnotationComposer
    extends Composer<_$AppDatabase, $MeetingSpeakersTable> {
  $$MeetingSpeakersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get printB64 =>
      $composableBuilder(column: $table.printB64, builder: (column) => column);

  GeneratedColumn<int> get speechMs =>
      $composableBuilder(column: $table.speechMs, builder: (column) => column);

  GeneratedColumn<bool> get draft =>
      $composableBuilder(column: $table.draft, builder: (column) => column);

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

class $$MeetingSpeakersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MeetingSpeakersTable,
          MeetingSpeaker,
          $$MeetingSpeakersTableFilterComposer,
          $$MeetingSpeakersTableOrderingComposer,
          $$MeetingSpeakersTableAnnotationComposer,
          $$MeetingSpeakersTableCreateCompanionBuilder,
          $$MeetingSpeakersTableUpdateCompanionBuilder,
          (MeetingSpeaker, $$MeetingSpeakersTableReferences),
          MeetingSpeaker,
          PrefetchHooks Function({bool meetingId})
        > {
  $$MeetingSpeakersTableTableManager(
    _$AppDatabase db,
    $MeetingSpeakersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MeetingSpeakersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MeetingSpeakersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MeetingSpeakersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> meetingId = const Value.absent(),
                Value<int> groupId = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> printB64 = const Value.absent(),
                Value<int> speechMs = const Value.absent(),
                Value<bool> draft = const Value.absent(),
              }) => MeetingSpeakersCompanion(
                id: id,
                meetingId: meetingId,
                groupId: groupId,
                label: label,
                printB64: printB64,
                speechMs: speechMs,
                draft: draft,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int meetingId,
                required int groupId,
                required String label,
                required String printB64,
                required int speechMs,
                Value<bool> draft = const Value.absent(),
              }) => MeetingSpeakersCompanion.insert(
                id: id,
                meetingId: meetingId,
                groupId: groupId,
                label: label,
                printB64: printB64,
                speechMs: speechMs,
                draft: draft,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MeetingSpeakersTable, MeetingSpeaker>(table),
                  $$MeetingSpeakersTableReferences(db, table, e),
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
                        referencedTable: $$MeetingSpeakersTableReferences
                            ._meetingIdTable(db),
                        referencedColumn: $$MeetingSpeakersTableReferences
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

typedef $$MeetingSpeakersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MeetingSpeakersTable,
      MeetingSpeaker,
      $$MeetingSpeakersTableFilterComposer,
      $$MeetingSpeakersTableOrderingComposer,
      $$MeetingSpeakersTableAnnotationComposer,
      $$MeetingSpeakersTableCreateCompanionBuilder,
      $$MeetingSpeakersTableUpdateCompanionBuilder,
      (MeetingSpeaker, $$MeetingSpeakersTableReferences),
      MeetingSpeaker,
      PrefetchHooks Function({bool meetingId})
    >;
typedef $$PeopleTableCreateCompanionBuilder = PeopleCompanion Function({
  Value<int> id,
  required String name,
  required String nameKey,
  required String printB64,
  required int speechMs,
  required DateTime updatedAt,
});
typedef $$PeopleTableUpdateCompanionBuilder = PeopleCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String> nameKey,
  Value<String> printB64,
  Value<int> speechMs,
  Value<DateTime> updatedAt,
});

class $$PeopleTableFilterComposer
    extends Composer<_$AppDatabase, $PeopleTable> {
  $$PeopleTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameKey => $composableBuilder(
    column: $table.nameKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get printB64 => $composableBuilder(
    column: $table.printB64,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get speechMs => $composableBuilder(
    column: $table.speechMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PeopleTableOrderingComposer
    extends Composer<_$AppDatabase, $PeopleTable> {
  $$PeopleTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameKey => $composableBuilder(
    column: $table.nameKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get printB64 => $composableBuilder(
    column: $table.printB64,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get speechMs => $composableBuilder(
    column: $table.speechMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PeopleTableAnnotationComposer
    extends Composer<_$AppDatabase, $PeopleTable> {
  $$PeopleTableAnnotationComposer({
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

  GeneratedColumn<String> get nameKey =>
      $composableBuilder(column: $table.nameKey, builder: (column) => column);

  GeneratedColumn<String> get printB64 =>
      $composableBuilder(column: $table.printB64, builder: (column) => column);

  GeneratedColumn<int> get speechMs =>
      $composableBuilder(column: $table.speechMs, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PeopleTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PeopleTable,
          PeopleData,
          $$PeopleTableFilterComposer,
          $$PeopleTableOrderingComposer,
          $$PeopleTableAnnotationComposer,
          $$PeopleTableCreateCompanionBuilder,
          $$PeopleTableUpdateCompanionBuilder,
          (PeopleData, BaseReferences<_$AppDatabase, $PeopleTable, PeopleData>),
          PeopleData,
          PrefetchHooks Function()
        > {
  $$PeopleTableTableManager(_$AppDatabase db, $PeopleTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeopleTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeopleTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeopleTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> nameKey = const Value.absent(),
                Value<String> printB64 = const Value.absent(),
                Value<int> speechMs = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PeopleCompanion(
                id: id,
                name: name,
                nameKey: nameKey,
                printB64: printB64,
                speechMs: speechMs,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String nameKey,
                required String printB64,
                required int speechMs,
                required DateTime updatedAt,
              }) => PeopleCompanion.insert(
                id: id,
                name: name,
                nameKey: nameKey,
                printB64: printB64,
                speechMs: speechMs,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PeopleTable, PeopleData>(table),
                  BaseReferences<_$AppDatabase, $PeopleTable, PeopleData>(
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

typedef $$PeopleTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PeopleTable,
      PeopleData,
      $$PeopleTableFilterComposer,
      $$PeopleTableOrderingComposer,
      $$PeopleTableAnnotationComposer,
      $$PeopleTableCreateCompanionBuilder,
      $$PeopleTableUpdateCompanionBuilder,
      (PeopleData, BaseReferences<_$AppDatabase, $PeopleTable, PeopleData>),
      PeopleData,
      PrefetchHooks Function()
    >;
typedef $$TasksTableCreateCompanionBuilder = TasksCompanion Function({
  Value<int> id,
  Value<int?> meetingId,
  required String description,
  Value<String?> assignedBy,
  Value<String?> due,
  Value<String?> quote,
  Value<int?> quoteMs,
  Value<bool> done,
  required int position,
  Value<bool> fromAi,
  Value<bool> edited,
  Value<bool> deleted,
  required DateTime createdAt,
});
typedef $$TasksTableUpdateCompanionBuilder = TasksCompanion Function({
  Value<int> id,
  Value<int?> meetingId,
  Value<String> description,
  Value<String?> assignedBy,
  Value<String?> due,
  Value<String?> quote,
  Value<int?> quoteMs,
  Value<bool> done,
  Value<int> position,
  Value<bool> fromAi,
  Value<bool> edited,
  Value<bool> deleted,
  Value<DateTime> createdAt,
});

final class $$TasksTableReferences
    extends BaseReferences<_$AppDatabase, $TasksTable, TaskRow> {
  $$TasksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MeetingsTable _meetingIdTable(_$AppDatabase db) =>
      db.meetings.createAlias('tasks__meeting_id__meetings__id');

  $$MeetingsTableProcessedTableManager? get meetingId {
    final $_column = $_itemColumn<int>('meeting_id');
    if ($_column == null) return null;
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

class $$TasksTableFilterComposer extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
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

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assignedBy => $composableBuilder(
    column: $table.assignedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get due => $composableBuilder(
    column: $table.due,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quote => $composableBuilder(
    column: $table.quote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quoteMs => $composableBuilder(
    column: $table.quoteMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get done => $composableBuilder(
    column: $table.done,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get fromAi => $composableBuilder(
    column: $table.fromAi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get edited => $composableBuilder(
    column: $table.edited,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
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

class $$TasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
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

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assignedBy => $composableBuilder(
    column: $table.assignedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get due => $composableBuilder(
    column: $table.due,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quote => $composableBuilder(
    column: $table.quote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quoteMs => $composableBuilder(
    column: $table.quoteMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get done => $composableBuilder(
    column: $table.done,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get fromAi => $composableBuilder(
    column: $table.fromAi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get edited => $composableBuilder(
    column: $table.edited,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
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

class $$TasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get assignedBy => $composableBuilder(
    column: $table.assignedBy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get due =>
      $composableBuilder(column: $table.due, builder: (column) => column);

  GeneratedColumn<String> get quote =>
      $composableBuilder(column: $table.quote, builder: (column) => column);

  GeneratedColumn<int> get quoteMs =>
      $composableBuilder(column: $table.quoteMs, builder: (column) => column);

  GeneratedColumn<bool> get done =>
      $composableBuilder(column: $table.done, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<bool> get fromAi =>
      $composableBuilder(column: $table.fromAi, builder: (column) => column);

  GeneratedColumn<bool> get edited =>
      $composableBuilder(column: $table.edited, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

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

class $$TasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TasksTable,
          TaskRow,
          $$TasksTableFilterComposer,
          $$TasksTableOrderingComposer,
          $$TasksTableAnnotationComposer,
          $$TasksTableCreateCompanionBuilder,
          $$TasksTableUpdateCompanionBuilder,
          (TaskRow, $$TasksTableReferences),
          TaskRow,
          PrefetchHooks Function({bool meetingId})
        > {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> meetingId = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String?> assignedBy = const Value.absent(),
                Value<String?> due = const Value.absent(),
                Value<String?> quote = const Value.absent(),
                Value<int?> quoteMs = const Value.absent(),
                Value<bool> done = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<bool> fromAi = const Value.absent(),
                Value<bool> edited = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TasksCompanion(
                id: id,
                meetingId: meetingId,
                description: description,
                assignedBy: assignedBy,
                due: due,
                quote: quote,
                quoteMs: quoteMs,
                done: done,
                position: position,
                fromAi: fromAi,
                edited: edited,
                deleted: deleted,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> meetingId = const Value.absent(),
                required String description,
                Value<String?> assignedBy = const Value.absent(),
                Value<String?> due = const Value.absent(),
                Value<String?> quote = const Value.absent(),
                Value<int?> quoteMs = const Value.absent(),
                Value<bool> done = const Value.absent(),
                required int position,
                Value<bool> fromAi = const Value.absent(),
                Value<bool> edited = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                required DateTime createdAt,
              }) => TasksCompanion.insert(
                id: id,
                meetingId: meetingId,
                description: description,
                assignedBy: assignedBy,
                due: due,
                quote: quote,
                quoteMs: quoteMs,
                done: done,
                position: position,
                fromAi: fromAi,
                edited: edited,
                deleted: deleted,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TasksTable, TaskRow>(table),
                  $$TasksTableReferences(db, table, e),
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
                        referencedTable: $$TasksTableReferences._meetingIdTable(
                          db,
                        ),
                        referencedColumn: $$TasksTableReferences
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

typedef $$TasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TasksTable,
      TaskRow,
      $$TasksTableFilterComposer,
      $$TasksTableOrderingComposer,
      $$TasksTableAnnotationComposer,
      $$TasksTableCreateCompanionBuilder,
      $$TasksTableUpdateCompanionBuilder,
      (TaskRow, $$TasksTableReferences),
      TaskRow,
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
  $$MeetingSpeakersTableTableManager get meetingSpeakers =>
      $$MeetingSpeakersTableTableManager(_db, _db.meetingSpeakers);
  $$PeopleTableTableManager get people =>
      $$PeopleTableTableManager(_db, _db.people);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
}
