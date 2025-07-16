// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PrefixTableTable extends PrefixTable
    with TableInfo<$PrefixTableTable, PrefixTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PrefixTableTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _callMeta = const VerificationMeta('call');
  @override
  late final GeneratedColumn<String> call = GeneratedColumn<String>(
    'call',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dxccIdMeta = const VerificationMeta('dxccId');
  @override
  late final GeneratedColumn<int> dxccId = GeneratedColumn<int>(
    'dxcc_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _continentMeta = const VerificationMeta(
    'continent',
  );
  @override
  late final GeneratedColumn<String> continent = GeneratedColumn<String>(
    'continent',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, call, dxccId, continent];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'prefix_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<PrefixTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('call')) {
      context.handle(
        _callMeta,
        call.isAcceptableOrUnknown(data['call']!, _callMeta),
      );
    } else if (isInserting) {
      context.missing(_callMeta);
    }
    if (data.containsKey('dxcc_id')) {
      context.handle(
        _dxccIdMeta,
        dxccId.isAcceptableOrUnknown(data['dxcc_id']!, _dxccIdMeta),
      );
    } else if (isInserting) {
      context.missing(_dxccIdMeta);
    }
    if (data.containsKey('continent')) {
      context.handle(
        _continentMeta,
        continent.isAcceptableOrUnknown(data['continent']!, _continentMeta),
      );
    } else if (isInserting) {
      context.missing(_continentMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PrefixTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PrefixTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      call: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}call'],
      )!,
      dxccId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dxcc_id'],
      )!,
      continent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}continent'],
      )!,
    );
  }

  @override
  $PrefixTableTable createAlias(String alias) {
    return $PrefixTableTable(attachedDatabase, alias);
  }
}

class PrefixTableData extends DataClass implements Insertable<PrefixTableData> {
  final int id;
  final String call;
  final int dxccId;
  final String continent;
  const PrefixTableData({
    required this.id,
    required this.call,
    required this.dxccId,
    required this.continent,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['call'] = Variable<String>(call);
    map['dxcc_id'] = Variable<int>(dxccId);
    map['continent'] = Variable<String>(continent);
    return map;
  }

  PrefixTableCompanion toCompanion(bool nullToAbsent) {
    return PrefixTableCompanion(
      id: Value(id),
      call: Value(call),
      dxccId: Value(dxccId),
      continent: Value(continent),
    );
  }

  factory PrefixTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PrefixTableData(
      id: serializer.fromJson<int>(json['id']),
      call: serializer.fromJson<String>(json['call']),
      dxccId: serializer.fromJson<int>(json['dxccId']),
      continent: serializer.fromJson<String>(json['continent']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'call': serializer.toJson<String>(call),
      'dxccId': serializer.toJson<int>(dxccId),
      'continent': serializer.toJson<String>(continent),
    };
  }

  PrefixTableData copyWith({
    int? id,
    String? call,
    int? dxccId,
    String? continent,
  }) => PrefixTableData(
    id: id ?? this.id,
    call: call ?? this.call,
    dxccId: dxccId ?? this.dxccId,
    continent: continent ?? this.continent,
  );
  PrefixTableData copyWithCompanion(PrefixTableCompanion data) {
    return PrefixTableData(
      id: data.id.present ? data.id.value : this.id,
      call: data.call.present ? data.call.value : this.call,
      dxccId: data.dxccId.present ? data.dxccId.value : this.dxccId,
      continent: data.continent.present ? data.continent.value : this.continent,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PrefixTableData(')
          ..write('id: $id, ')
          ..write('call: $call, ')
          ..write('dxccId: $dxccId, ')
          ..write('continent: $continent')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, call, dxccId, continent);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PrefixTableData &&
          other.id == this.id &&
          other.call == this.call &&
          other.dxccId == this.dxccId &&
          other.continent == this.continent);
}

class PrefixTableCompanion extends UpdateCompanion<PrefixTableData> {
  final Value<int> id;
  final Value<String> call;
  final Value<int> dxccId;
  final Value<String> continent;
  const PrefixTableCompanion({
    this.id = const Value.absent(),
    this.call = const Value.absent(),
    this.dxccId = const Value.absent(),
    this.continent = const Value.absent(),
  });
  PrefixTableCompanion.insert({
    this.id = const Value.absent(),
    required String call,
    required int dxccId,
    required String continent,
  }) : call = Value(call),
       dxccId = Value(dxccId),
       continent = Value(continent);
  static Insertable<PrefixTableData> custom({
    Expression<int>? id,
    Expression<String>? call,
    Expression<int>? dxccId,
    Expression<String>? continent,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (call != null) 'call': call,
      if (dxccId != null) 'dxcc_id': dxccId,
      if (continent != null) 'continent': continent,
    });
  }

  PrefixTableCompanion copyWith({
    Value<int>? id,
    Value<String>? call,
    Value<int>? dxccId,
    Value<String>? continent,
  }) {
    return PrefixTableCompanion(
      id: id ?? this.id,
      call: call ?? this.call,
      dxccId: dxccId ?? this.dxccId,
      continent: continent ?? this.continent,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (call.present) {
      map['call'] = Variable<String>(call.value);
    }
    if (dxccId.present) {
      map['dxcc_id'] = Variable<int>(dxccId.value);
    }
    if (continent.present) {
      map['continent'] = Variable<String>(continent.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PrefixTableCompanion(')
          ..write('id: $id, ')
          ..write('call: $call, ')
          ..write('dxccId: $dxccId, ')
          ..write('continent: $continent')
          ..write(')'))
        .toString();
  }
}

class $QsoTableTable extends QsoTable
    with TableInfo<$QsoTableTable, QsoTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QsoTableTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _utcInSecondsMeta = const VerificationMeta(
    'utcInSeconds',
  );
  @override
  late final GeneratedColumn<int> utcInSeconds = GeneratedColumn<int>(
    'utc_in_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  @override
  late final GeneratedColumn<String> runId = GeneratedColumn<String>(
    'run_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stationCallsignMeta = const VerificationMeta(
    'stationCallsign',
  );
  @override
  late final GeneratedColumn<String> stationCallsign = GeneratedColumn<String>(
    'station_callsign',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _callsignMeta = const VerificationMeta(
    'callsign',
  );
  @override
  late final GeneratedColumn<String> callsign = GeneratedColumn<String>(
    'callsign',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _callsignCorrectMeta = const VerificationMeta(
    'callsignCorrect',
  );
  @override
  late final GeneratedColumn<String> callsignCorrect = GeneratedColumn<String>(
    'callsign_correct',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exchangeMeta = const VerificationMeta(
    'exchange',
  );
  @override
  late final GeneratedColumn<String> exchange = GeneratedColumn<String>(
    'exchange',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exchangeCorrectMeta = const VerificationMeta(
    'exchangeCorrect',
  );
  @override
  late final GeneratedColumn<String> exchangeCorrect = GeneratedColumn<String>(
    'exchange_correct',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rstMeta = const VerificationMeta('rst');
  @override
  late final GeneratedColumn<int> rst = GeneratedColumn<int>(
    'rst',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rstCorrectMeta = const VerificationMeta(
    'rstCorrect',
  );
  @override
  late final GeneratedColumn<int> rstCorrect = GeneratedColumn<int>(
    'rst_correct',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    utcInSeconds,
    runId,
    stationCallsign,
    callsign,
    callsignCorrect,
    exchange,
    exchangeCorrect,
    rst,
    rstCorrect,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'qso_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<QsoTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('utc_in_seconds')) {
      context.handle(
        _utcInSecondsMeta,
        utcInSeconds.isAcceptableOrUnknown(
          data['utc_in_seconds']!,
          _utcInSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_utcInSecondsMeta);
    }
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('station_callsign')) {
      context.handle(
        _stationCallsignMeta,
        stationCallsign.isAcceptableOrUnknown(
          data['station_callsign']!,
          _stationCallsignMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_stationCallsignMeta);
    }
    if (data.containsKey('callsign')) {
      context.handle(
        _callsignMeta,
        callsign.isAcceptableOrUnknown(data['callsign']!, _callsignMeta),
      );
    } else if (isInserting) {
      context.missing(_callsignMeta);
    }
    if (data.containsKey('callsign_correct')) {
      context.handle(
        _callsignCorrectMeta,
        callsignCorrect.isAcceptableOrUnknown(
          data['callsign_correct']!,
          _callsignCorrectMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_callsignCorrectMeta);
    }
    if (data.containsKey('exchange')) {
      context.handle(
        _exchangeMeta,
        exchange.isAcceptableOrUnknown(data['exchange']!, _exchangeMeta),
      );
    } else if (isInserting) {
      context.missing(_exchangeMeta);
    }
    if (data.containsKey('exchange_correct')) {
      context.handle(
        _exchangeCorrectMeta,
        exchangeCorrect.isAcceptableOrUnknown(
          data['exchange_correct']!,
          _exchangeCorrectMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_exchangeCorrectMeta);
    }
    if (data.containsKey('rst')) {
      context.handle(
        _rstMeta,
        rst.isAcceptableOrUnknown(data['rst']!, _rstMeta),
      );
    } else if (isInserting) {
      context.missing(_rstMeta);
    }
    if (data.containsKey('rst_correct')) {
      context.handle(
        _rstCorrectMeta,
        rstCorrect.isAcceptableOrUnknown(data['rst_correct']!, _rstCorrectMeta),
      );
    } else if (isInserting) {
      context.missing(_rstCorrectMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  QsoTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QsoTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      utcInSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}utc_in_seconds'],
      )!,
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}run_id'],
      )!,
      stationCallsign: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_callsign'],
      )!,
      callsign: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}callsign'],
      )!,
      callsignCorrect: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}callsign_correct'],
      )!,
      exchange: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exchange'],
      )!,
      exchangeCorrect: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exchange_correct'],
      )!,
      rst: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rst'],
      )!,
      rstCorrect: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rst_correct'],
      )!,
    );
  }

  @override
  $QsoTableTable createAlias(String alias) {
    return $QsoTableTable(attachedDatabase, alias);
  }
}

class QsoTableData extends DataClass implements Insertable<QsoTableData> {
  final int id;
  final int utcInSeconds;
  final String runId;
  final String stationCallsign;
  final String callsign;
  final String callsignCorrect;
  final String exchange;
  final String exchangeCorrect;
  final int rst;
  final int rstCorrect;
  const QsoTableData({
    required this.id,
    required this.utcInSeconds,
    required this.runId,
    required this.stationCallsign,
    required this.callsign,
    required this.callsignCorrect,
    required this.exchange,
    required this.exchangeCorrect,
    required this.rst,
    required this.rstCorrect,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['utc_in_seconds'] = Variable<int>(utcInSeconds);
    map['run_id'] = Variable<String>(runId);
    map['station_callsign'] = Variable<String>(stationCallsign);
    map['callsign'] = Variable<String>(callsign);
    map['callsign_correct'] = Variable<String>(callsignCorrect);
    map['exchange'] = Variable<String>(exchange);
    map['exchange_correct'] = Variable<String>(exchangeCorrect);
    map['rst'] = Variable<int>(rst);
    map['rst_correct'] = Variable<int>(rstCorrect);
    return map;
  }

  QsoTableCompanion toCompanion(bool nullToAbsent) {
    return QsoTableCompanion(
      id: Value(id),
      utcInSeconds: Value(utcInSeconds),
      runId: Value(runId),
      stationCallsign: Value(stationCallsign),
      callsign: Value(callsign),
      callsignCorrect: Value(callsignCorrect),
      exchange: Value(exchange),
      exchangeCorrect: Value(exchangeCorrect),
      rst: Value(rst),
      rstCorrect: Value(rstCorrect),
    );
  }

  factory QsoTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QsoTableData(
      id: serializer.fromJson<int>(json['id']),
      utcInSeconds: serializer.fromJson<int>(json['utcInSeconds']),
      runId: serializer.fromJson<String>(json['runId']),
      stationCallsign: serializer.fromJson<String>(json['stationCallsign']),
      callsign: serializer.fromJson<String>(json['callsign']),
      callsignCorrect: serializer.fromJson<String>(json['callsignCorrect']),
      exchange: serializer.fromJson<String>(json['exchange']),
      exchangeCorrect: serializer.fromJson<String>(json['exchangeCorrect']),
      rst: serializer.fromJson<int>(json['rst']),
      rstCorrect: serializer.fromJson<int>(json['rstCorrect']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'utcInSeconds': serializer.toJson<int>(utcInSeconds),
      'runId': serializer.toJson<String>(runId),
      'stationCallsign': serializer.toJson<String>(stationCallsign),
      'callsign': serializer.toJson<String>(callsign),
      'callsignCorrect': serializer.toJson<String>(callsignCorrect),
      'exchange': serializer.toJson<String>(exchange),
      'exchangeCorrect': serializer.toJson<String>(exchangeCorrect),
      'rst': serializer.toJson<int>(rst),
      'rstCorrect': serializer.toJson<int>(rstCorrect),
    };
  }

  QsoTableData copyWith({
    int? id,
    int? utcInSeconds,
    String? runId,
    String? stationCallsign,
    String? callsign,
    String? callsignCorrect,
    String? exchange,
    String? exchangeCorrect,
    int? rst,
    int? rstCorrect,
  }) => QsoTableData(
    id: id ?? this.id,
    utcInSeconds: utcInSeconds ?? this.utcInSeconds,
    runId: runId ?? this.runId,
    stationCallsign: stationCallsign ?? this.stationCallsign,
    callsign: callsign ?? this.callsign,
    callsignCorrect: callsignCorrect ?? this.callsignCorrect,
    exchange: exchange ?? this.exchange,
    exchangeCorrect: exchangeCorrect ?? this.exchangeCorrect,
    rst: rst ?? this.rst,
    rstCorrect: rstCorrect ?? this.rstCorrect,
  );
  QsoTableData copyWithCompanion(QsoTableCompanion data) {
    return QsoTableData(
      id: data.id.present ? data.id.value : this.id,
      utcInSeconds: data.utcInSeconds.present
          ? data.utcInSeconds.value
          : this.utcInSeconds,
      runId: data.runId.present ? data.runId.value : this.runId,
      stationCallsign: data.stationCallsign.present
          ? data.stationCallsign.value
          : this.stationCallsign,
      callsign: data.callsign.present ? data.callsign.value : this.callsign,
      callsignCorrect: data.callsignCorrect.present
          ? data.callsignCorrect.value
          : this.callsignCorrect,
      exchange: data.exchange.present ? data.exchange.value : this.exchange,
      exchangeCorrect: data.exchangeCorrect.present
          ? data.exchangeCorrect.value
          : this.exchangeCorrect,
      rst: data.rst.present ? data.rst.value : this.rst,
      rstCorrect: data.rstCorrect.present
          ? data.rstCorrect.value
          : this.rstCorrect,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QsoTableData(')
          ..write('id: $id, ')
          ..write('utcInSeconds: $utcInSeconds, ')
          ..write('runId: $runId, ')
          ..write('stationCallsign: $stationCallsign, ')
          ..write('callsign: $callsign, ')
          ..write('callsignCorrect: $callsignCorrect, ')
          ..write('exchange: $exchange, ')
          ..write('exchangeCorrect: $exchangeCorrect, ')
          ..write('rst: $rst, ')
          ..write('rstCorrect: $rstCorrect')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    utcInSeconds,
    runId,
    stationCallsign,
    callsign,
    callsignCorrect,
    exchange,
    exchangeCorrect,
    rst,
    rstCorrect,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QsoTableData &&
          other.id == this.id &&
          other.utcInSeconds == this.utcInSeconds &&
          other.runId == this.runId &&
          other.stationCallsign == this.stationCallsign &&
          other.callsign == this.callsign &&
          other.callsignCorrect == this.callsignCorrect &&
          other.exchange == this.exchange &&
          other.exchangeCorrect == this.exchangeCorrect &&
          other.rst == this.rst &&
          other.rstCorrect == this.rstCorrect);
}

class QsoTableCompanion extends UpdateCompanion<QsoTableData> {
  final Value<int> id;
  final Value<int> utcInSeconds;
  final Value<String> runId;
  final Value<String> stationCallsign;
  final Value<String> callsign;
  final Value<String> callsignCorrect;
  final Value<String> exchange;
  final Value<String> exchangeCorrect;
  final Value<int> rst;
  final Value<int> rstCorrect;
  const QsoTableCompanion({
    this.id = const Value.absent(),
    this.utcInSeconds = const Value.absent(),
    this.runId = const Value.absent(),
    this.stationCallsign = const Value.absent(),
    this.callsign = const Value.absent(),
    this.callsignCorrect = const Value.absent(),
    this.exchange = const Value.absent(),
    this.exchangeCorrect = const Value.absent(),
    this.rst = const Value.absent(),
    this.rstCorrect = const Value.absent(),
  });
  QsoTableCompanion.insert({
    this.id = const Value.absent(),
    required int utcInSeconds,
    required String runId,
    required String stationCallsign,
    required String callsign,
    required String callsignCorrect,
    required String exchange,
    required String exchangeCorrect,
    required int rst,
    required int rstCorrect,
  }) : utcInSeconds = Value(utcInSeconds),
       runId = Value(runId),
       stationCallsign = Value(stationCallsign),
       callsign = Value(callsign),
       callsignCorrect = Value(callsignCorrect),
       exchange = Value(exchange),
       exchangeCorrect = Value(exchangeCorrect),
       rst = Value(rst),
       rstCorrect = Value(rstCorrect);
  static Insertable<QsoTableData> custom({
    Expression<int>? id,
    Expression<int>? utcInSeconds,
    Expression<String>? runId,
    Expression<String>? stationCallsign,
    Expression<String>? callsign,
    Expression<String>? callsignCorrect,
    Expression<String>? exchange,
    Expression<String>? exchangeCorrect,
    Expression<int>? rst,
    Expression<int>? rstCorrect,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (utcInSeconds != null) 'utc_in_seconds': utcInSeconds,
      if (runId != null) 'run_id': runId,
      if (stationCallsign != null) 'station_callsign': stationCallsign,
      if (callsign != null) 'callsign': callsign,
      if (callsignCorrect != null) 'callsign_correct': callsignCorrect,
      if (exchange != null) 'exchange': exchange,
      if (exchangeCorrect != null) 'exchange_correct': exchangeCorrect,
      if (rst != null) 'rst': rst,
      if (rstCorrect != null) 'rst_correct': rstCorrect,
    });
  }

  QsoTableCompanion copyWith({
    Value<int>? id,
    Value<int>? utcInSeconds,
    Value<String>? runId,
    Value<String>? stationCallsign,
    Value<String>? callsign,
    Value<String>? callsignCorrect,
    Value<String>? exchange,
    Value<String>? exchangeCorrect,
    Value<int>? rst,
    Value<int>? rstCorrect,
  }) {
    return QsoTableCompanion(
      id: id ?? this.id,
      utcInSeconds: utcInSeconds ?? this.utcInSeconds,
      runId: runId ?? this.runId,
      stationCallsign: stationCallsign ?? this.stationCallsign,
      callsign: callsign ?? this.callsign,
      callsignCorrect: callsignCorrect ?? this.callsignCorrect,
      exchange: exchange ?? this.exchange,
      exchangeCorrect: exchangeCorrect ?? this.exchangeCorrect,
      rst: rst ?? this.rst,
      rstCorrect: rstCorrect ?? this.rstCorrect,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (utcInSeconds.present) {
      map['utc_in_seconds'] = Variable<int>(utcInSeconds.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<String>(runId.value);
    }
    if (stationCallsign.present) {
      map['station_callsign'] = Variable<String>(stationCallsign.value);
    }
    if (callsign.present) {
      map['callsign'] = Variable<String>(callsign.value);
    }
    if (callsignCorrect.present) {
      map['callsign_correct'] = Variable<String>(callsignCorrect.value);
    }
    if (exchange.present) {
      map['exchange'] = Variable<String>(exchange.value);
    }
    if (exchangeCorrect.present) {
      map['exchange_correct'] = Variable<String>(exchangeCorrect.value);
    }
    if (rst.present) {
      map['rst'] = Variable<int>(rst.value);
    }
    if (rstCorrect.present) {
      map['rst_correct'] = Variable<int>(rstCorrect.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QsoTableCompanion(')
          ..write('id: $id, ')
          ..write('utcInSeconds: $utcInSeconds, ')
          ..write('runId: $runId, ')
          ..write('stationCallsign: $stationCallsign, ')
          ..write('callsign: $callsign, ')
          ..write('callsignCorrect: $callsignCorrect, ')
          ..write('exchange: $exchange, ')
          ..write('exchangeCorrect: $exchangeCorrect, ')
          ..write('rst: $rst, ')
          ..write('rstCorrect: $rstCorrect')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PrefixTableTable prefixTable = $PrefixTableTable(this);
  late final $QsoTableTable qsoTable = $QsoTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [prefixTable, qsoTable];
}

typedef $$PrefixTableTableCreateCompanionBuilder =
    PrefixTableCompanion Function({
      Value<int> id,
      required String call,
      required int dxccId,
      required String continent,
    });
typedef $$PrefixTableTableUpdateCompanionBuilder =
    PrefixTableCompanion Function({
      Value<int> id,
      Value<String> call,
      Value<int> dxccId,
      Value<String> continent,
    });

class $$PrefixTableTableFilterComposer
    extends Composer<_$AppDatabase, $PrefixTableTable> {
  $$PrefixTableTableFilterComposer({
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

  ColumnFilters<String> get call => $composableBuilder(
    column: $table.call,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dxccId => $composableBuilder(
    column: $table.dxccId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get continent => $composableBuilder(
    column: $table.continent,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PrefixTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PrefixTableTable> {
  $$PrefixTableTableOrderingComposer({
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

  ColumnOrderings<String> get call => $composableBuilder(
    column: $table.call,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dxccId => $composableBuilder(
    column: $table.dxccId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get continent => $composableBuilder(
    column: $table.continent,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PrefixTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PrefixTableTable> {
  $$PrefixTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get call =>
      $composableBuilder(column: $table.call, builder: (column) => column);

  GeneratedColumn<int> get dxccId =>
      $composableBuilder(column: $table.dxccId, builder: (column) => column);

  GeneratedColumn<String> get continent =>
      $composableBuilder(column: $table.continent, builder: (column) => column);
}

class $$PrefixTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PrefixTableTable,
          PrefixTableData,
          $$PrefixTableTableFilterComposer,
          $$PrefixTableTableOrderingComposer,
          $$PrefixTableTableAnnotationComposer,
          $$PrefixTableTableCreateCompanionBuilder,
          $$PrefixTableTableUpdateCompanionBuilder,
          (
            PrefixTableData,
            BaseReferences<_$AppDatabase, $PrefixTableTable, PrefixTableData>,
          ),
          PrefixTableData,
          PrefetchHooks Function()
        > {
  $$PrefixTableTableTableManager(_$AppDatabase db, $PrefixTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PrefixTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PrefixTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PrefixTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> call = const Value.absent(),
                Value<int> dxccId = const Value.absent(),
                Value<String> continent = const Value.absent(),
              }) => PrefixTableCompanion(
                id: id,
                call: call,
                dxccId: dxccId,
                continent: continent,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String call,
                required int dxccId,
                required String continent,
              }) => PrefixTableCompanion.insert(
                id: id,
                call: call,
                dxccId: dxccId,
                continent: continent,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PrefixTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PrefixTableTable,
      PrefixTableData,
      $$PrefixTableTableFilterComposer,
      $$PrefixTableTableOrderingComposer,
      $$PrefixTableTableAnnotationComposer,
      $$PrefixTableTableCreateCompanionBuilder,
      $$PrefixTableTableUpdateCompanionBuilder,
      (
        PrefixTableData,
        BaseReferences<_$AppDatabase, $PrefixTableTable, PrefixTableData>,
      ),
      PrefixTableData,
      PrefetchHooks Function()
    >;
typedef $$QsoTableTableCreateCompanionBuilder =
    QsoTableCompanion Function({
      Value<int> id,
      required int utcInSeconds,
      required String runId,
      required String stationCallsign,
      required String callsign,
      required String callsignCorrect,
      required String exchange,
      required String exchangeCorrect,
      required int rst,
      required int rstCorrect,
    });
typedef $$QsoTableTableUpdateCompanionBuilder =
    QsoTableCompanion Function({
      Value<int> id,
      Value<int> utcInSeconds,
      Value<String> runId,
      Value<String> stationCallsign,
      Value<String> callsign,
      Value<String> callsignCorrect,
      Value<String> exchange,
      Value<String> exchangeCorrect,
      Value<int> rst,
      Value<int> rstCorrect,
    });

class $$QsoTableTableFilterComposer
    extends Composer<_$AppDatabase, $QsoTableTable> {
  $$QsoTableTableFilterComposer({
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

  ColumnFilters<int> get utcInSeconds => $composableBuilder(
    column: $table.utcInSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get runId => $composableBuilder(
    column: $table.runId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stationCallsign => $composableBuilder(
    column: $table.stationCallsign,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get callsign => $composableBuilder(
    column: $table.callsign,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get callsignCorrect => $composableBuilder(
    column: $table.callsignCorrect,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exchange => $composableBuilder(
    column: $table.exchange,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exchangeCorrect => $composableBuilder(
    column: $table.exchangeCorrect,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rst => $composableBuilder(
    column: $table.rst,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rstCorrect => $composableBuilder(
    column: $table.rstCorrect,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QsoTableTableOrderingComposer
    extends Composer<_$AppDatabase, $QsoTableTable> {
  $$QsoTableTableOrderingComposer({
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

  ColumnOrderings<int> get utcInSeconds => $composableBuilder(
    column: $table.utcInSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get runId => $composableBuilder(
    column: $table.runId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stationCallsign => $composableBuilder(
    column: $table.stationCallsign,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get callsign => $composableBuilder(
    column: $table.callsign,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get callsignCorrect => $composableBuilder(
    column: $table.callsignCorrect,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exchange => $composableBuilder(
    column: $table.exchange,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exchangeCorrect => $composableBuilder(
    column: $table.exchangeCorrect,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rst => $composableBuilder(
    column: $table.rst,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rstCorrect => $composableBuilder(
    column: $table.rstCorrect,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QsoTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $QsoTableTable> {
  $$QsoTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get utcInSeconds => $composableBuilder(
    column: $table.utcInSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get runId =>
      $composableBuilder(column: $table.runId, builder: (column) => column);

  GeneratedColumn<String> get stationCallsign => $composableBuilder(
    column: $table.stationCallsign,
    builder: (column) => column,
  );

  GeneratedColumn<String> get callsign =>
      $composableBuilder(column: $table.callsign, builder: (column) => column);

  GeneratedColumn<String> get callsignCorrect => $composableBuilder(
    column: $table.callsignCorrect,
    builder: (column) => column,
  );

  GeneratedColumn<String> get exchange =>
      $composableBuilder(column: $table.exchange, builder: (column) => column);

  GeneratedColumn<String> get exchangeCorrect => $composableBuilder(
    column: $table.exchangeCorrect,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rst =>
      $composableBuilder(column: $table.rst, builder: (column) => column);

  GeneratedColumn<int> get rstCorrect => $composableBuilder(
    column: $table.rstCorrect,
    builder: (column) => column,
  );
}

class $$QsoTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $QsoTableTable,
          QsoTableData,
          $$QsoTableTableFilterComposer,
          $$QsoTableTableOrderingComposer,
          $$QsoTableTableAnnotationComposer,
          $$QsoTableTableCreateCompanionBuilder,
          $$QsoTableTableUpdateCompanionBuilder,
          (
            QsoTableData,
            BaseReferences<_$AppDatabase, $QsoTableTable, QsoTableData>,
          ),
          QsoTableData,
          PrefetchHooks Function()
        > {
  $$QsoTableTableTableManager(_$AppDatabase db, $QsoTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QsoTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QsoTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QsoTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> utcInSeconds = const Value.absent(),
                Value<String> runId = const Value.absent(),
                Value<String> stationCallsign = const Value.absent(),
                Value<String> callsign = const Value.absent(),
                Value<String> callsignCorrect = const Value.absent(),
                Value<String> exchange = const Value.absent(),
                Value<String> exchangeCorrect = const Value.absent(),
                Value<int> rst = const Value.absent(),
                Value<int> rstCorrect = const Value.absent(),
              }) => QsoTableCompanion(
                id: id,
                utcInSeconds: utcInSeconds,
                runId: runId,
                stationCallsign: stationCallsign,
                callsign: callsign,
                callsignCorrect: callsignCorrect,
                exchange: exchange,
                exchangeCorrect: exchangeCorrect,
                rst: rst,
                rstCorrect: rstCorrect,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int utcInSeconds,
                required String runId,
                required String stationCallsign,
                required String callsign,
                required String callsignCorrect,
                required String exchange,
                required String exchangeCorrect,
                required int rst,
                required int rstCorrect,
              }) => QsoTableCompanion.insert(
                id: id,
                utcInSeconds: utcInSeconds,
                runId: runId,
                stationCallsign: stationCallsign,
                callsign: callsign,
                callsignCorrect: callsignCorrect,
                exchange: exchange,
                exchangeCorrect: exchangeCorrect,
                rst: rst,
                rstCorrect: rstCorrect,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QsoTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $QsoTableTable,
      QsoTableData,
      $$QsoTableTableFilterComposer,
      $$QsoTableTableOrderingComposer,
      $$QsoTableTableAnnotationComposer,
      $$QsoTableTableCreateCompanionBuilder,
      $$QsoTableTableUpdateCompanionBuilder,
      (
        QsoTableData,
        BaseReferences<_$AppDatabase, $QsoTableTable, QsoTableData>,
      ),
      QsoTableData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PrefixTableTableTableManager get prefixTable =>
      $$PrefixTableTableTableManager(_db, _db.prefixTable);
  $$QsoTableTableTableManager get qsoTable =>
      $$QsoTableTableTableManager(_db, _db.qsoTable);
}
