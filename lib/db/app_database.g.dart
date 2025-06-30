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
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  @override
  late final GeneratedColumn<String> runId = GeneratedColumn<String>(
    'run_id',
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
  static const VerificationMeta _exchangeRecvMeta = const VerificationMeta(
    'exchangeRecv',
  );
  @override
  late final GeneratedColumn<String> exchangeRecv = GeneratedColumn<String>(
    'exchange_recv',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exchangeSentMeta = const VerificationMeta(
    'exchangeSent',
  );
  @override
  late final GeneratedColumn<String> exchangeSent = GeneratedColumn<String>(
    'exchange_sent',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rstSentMeta = const VerificationMeta(
    'rstSent',
  );
  @override
  late final GeneratedColumn<int> rstSent = GeneratedColumn<int>(
    'rst_sent',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rstRecvMeta = const VerificationMeta(
    'rstRecv',
  );
  @override
  late final GeneratedColumn<int> rstRecv = GeneratedColumn<int>(
    'rst_recv',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    runId,
    callsign,
    stationCallsign,
    exchangeRecv,
    exchangeSent,
    rstSent,
    rstRecv,
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
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('callsign')) {
      context.handle(
        _callsignMeta,
        callsign.isAcceptableOrUnknown(data['callsign']!, _callsignMeta),
      );
    } else if (isInserting) {
      context.missing(_callsignMeta);
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
    if (data.containsKey('exchange_recv')) {
      context.handle(
        _exchangeRecvMeta,
        exchangeRecv.isAcceptableOrUnknown(
          data['exchange_recv']!,
          _exchangeRecvMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_exchangeRecvMeta);
    }
    if (data.containsKey('exchange_sent')) {
      context.handle(
        _exchangeSentMeta,
        exchangeSent.isAcceptableOrUnknown(
          data['exchange_sent']!,
          _exchangeSentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_exchangeSentMeta);
    }
    if (data.containsKey('rst_sent')) {
      context.handle(
        _rstSentMeta,
        rstSent.isAcceptableOrUnknown(data['rst_sent']!, _rstSentMeta),
      );
    } else if (isInserting) {
      context.missing(_rstSentMeta);
    }
    if (data.containsKey('rst_recv')) {
      context.handle(
        _rstRecvMeta,
        rstRecv.isAcceptableOrUnknown(data['rst_recv']!, _rstRecvMeta),
      );
    } else if (isInserting) {
      context.missing(_rstRecvMeta);
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
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}run_id'],
      )!,
      callsign: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}callsign'],
      )!,
      stationCallsign: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_callsign'],
      )!,
      exchangeRecv: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exchange_recv'],
      )!,
      exchangeSent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exchange_sent'],
      )!,
      rstSent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rst_sent'],
      )!,
      rstRecv: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rst_recv'],
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
  final String runId;
  final String callsign;
  final String stationCallsign;
  final String exchangeRecv;
  final String exchangeSent;
  final int rstSent;
  final int rstRecv;
  const QsoTableData({
    required this.id,
    required this.runId,
    required this.callsign,
    required this.stationCallsign,
    required this.exchangeRecv,
    required this.exchangeSent,
    required this.rstSent,
    required this.rstRecv,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['run_id'] = Variable<String>(runId);
    map['callsign'] = Variable<String>(callsign);
    map['station_callsign'] = Variable<String>(stationCallsign);
    map['exchange_recv'] = Variable<String>(exchangeRecv);
    map['exchange_sent'] = Variable<String>(exchangeSent);
    map['rst_sent'] = Variable<int>(rstSent);
    map['rst_recv'] = Variable<int>(rstRecv);
    return map;
  }

  QsoTableCompanion toCompanion(bool nullToAbsent) {
    return QsoTableCompanion(
      id: Value(id),
      runId: Value(runId),
      callsign: Value(callsign),
      stationCallsign: Value(stationCallsign),
      exchangeRecv: Value(exchangeRecv),
      exchangeSent: Value(exchangeSent),
      rstSent: Value(rstSent),
      rstRecv: Value(rstRecv),
    );
  }

  factory QsoTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QsoTableData(
      id: serializer.fromJson<int>(json['id']),
      runId: serializer.fromJson<String>(json['runId']),
      callsign: serializer.fromJson<String>(json['callsign']),
      stationCallsign: serializer.fromJson<String>(json['stationCallsign']),
      exchangeRecv: serializer.fromJson<String>(json['exchangeRecv']),
      exchangeSent: serializer.fromJson<String>(json['exchangeSent']),
      rstSent: serializer.fromJson<int>(json['rstSent']),
      rstRecv: serializer.fromJson<int>(json['rstRecv']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'runId': serializer.toJson<String>(runId),
      'callsign': serializer.toJson<String>(callsign),
      'stationCallsign': serializer.toJson<String>(stationCallsign),
      'exchangeRecv': serializer.toJson<String>(exchangeRecv),
      'exchangeSent': serializer.toJson<String>(exchangeSent),
      'rstSent': serializer.toJson<int>(rstSent),
      'rstRecv': serializer.toJson<int>(rstRecv),
    };
  }

  QsoTableData copyWith({
    int? id,
    String? runId,
    String? callsign,
    String? stationCallsign,
    String? exchangeRecv,
    String? exchangeSent,
    int? rstSent,
    int? rstRecv,
  }) => QsoTableData(
    id: id ?? this.id,
    runId: runId ?? this.runId,
    callsign: callsign ?? this.callsign,
    stationCallsign: stationCallsign ?? this.stationCallsign,
    exchangeRecv: exchangeRecv ?? this.exchangeRecv,
    exchangeSent: exchangeSent ?? this.exchangeSent,
    rstSent: rstSent ?? this.rstSent,
    rstRecv: rstRecv ?? this.rstRecv,
  );
  QsoTableData copyWithCompanion(QsoTableCompanion data) {
    return QsoTableData(
      id: data.id.present ? data.id.value : this.id,
      runId: data.runId.present ? data.runId.value : this.runId,
      callsign: data.callsign.present ? data.callsign.value : this.callsign,
      stationCallsign: data.stationCallsign.present
          ? data.stationCallsign.value
          : this.stationCallsign,
      exchangeRecv: data.exchangeRecv.present
          ? data.exchangeRecv.value
          : this.exchangeRecv,
      exchangeSent: data.exchangeSent.present
          ? data.exchangeSent.value
          : this.exchangeSent,
      rstSent: data.rstSent.present ? data.rstSent.value : this.rstSent,
      rstRecv: data.rstRecv.present ? data.rstRecv.value : this.rstRecv,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QsoTableData(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('callsign: $callsign, ')
          ..write('stationCallsign: $stationCallsign, ')
          ..write('exchangeRecv: $exchangeRecv, ')
          ..write('exchangeSent: $exchangeSent, ')
          ..write('rstSent: $rstSent, ')
          ..write('rstRecv: $rstRecv')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    runId,
    callsign,
    stationCallsign,
    exchangeRecv,
    exchangeSent,
    rstSent,
    rstRecv,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QsoTableData &&
          other.id == this.id &&
          other.runId == this.runId &&
          other.callsign == this.callsign &&
          other.stationCallsign == this.stationCallsign &&
          other.exchangeRecv == this.exchangeRecv &&
          other.exchangeSent == this.exchangeSent &&
          other.rstSent == this.rstSent &&
          other.rstRecv == this.rstRecv);
}

class QsoTableCompanion extends UpdateCompanion<QsoTableData> {
  final Value<int> id;
  final Value<String> runId;
  final Value<String> callsign;
  final Value<String> stationCallsign;
  final Value<String> exchangeRecv;
  final Value<String> exchangeSent;
  final Value<int> rstSent;
  final Value<int> rstRecv;
  const QsoTableCompanion({
    this.id = const Value.absent(),
    this.runId = const Value.absent(),
    this.callsign = const Value.absent(),
    this.stationCallsign = const Value.absent(),
    this.exchangeRecv = const Value.absent(),
    this.exchangeSent = const Value.absent(),
    this.rstSent = const Value.absent(),
    this.rstRecv = const Value.absent(),
  });
  QsoTableCompanion.insert({
    this.id = const Value.absent(),
    required String runId,
    required String callsign,
    required String stationCallsign,
    required String exchangeRecv,
    required String exchangeSent,
    required int rstSent,
    required int rstRecv,
  }) : runId = Value(runId),
       callsign = Value(callsign),
       stationCallsign = Value(stationCallsign),
       exchangeRecv = Value(exchangeRecv),
       exchangeSent = Value(exchangeSent),
       rstSent = Value(rstSent),
       rstRecv = Value(rstRecv);
  static Insertable<QsoTableData> custom({
    Expression<int>? id,
    Expression<String>? runId,
    Expression<String>? callsign,
    Expression<String>? stationCallsign,
    Expression<String>? exchangeRecv,
    Expression<String>? exchangeSent,
    Expression<int>? rstSent,
    Expression<int>? rstRecv,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (runId != null) 'run_id': runId,
      if (callsign != null) 'callsign': callsign,
      if (stationCallsign != null) 'station_callsign': stationCallsign,
      if (exchangeRecv != null) 'exchange_recv': exchangeRecv,
      if (exchangeSent != null) 'exchange_sent': exchangeSent,
      if (rstSent != null) 'rst_sent': rstSent,
      if (rstRecv != null) 'rst_recv': rstRecv,
    });
  }

  QsoTableCompanion copyWith({
    Value<int>? id,
    Value<String>? runId,
    Value<String>? callsign,
    Value<String>? stationCallsign,
    Value<String>? exchangeRecv,
    Value<String>? exchangeSent,
    Value<int>? rstSent,
    Value<int>? rstRecv,
  }) {
    return QsoTableCompanion(
      id: id ?? this.id,
      runId: runId ?? this.runId,
      callsign: callsign ?? this.callsign,
      stationCallsign: stationCallsign ?? this.stationCallsign,
      exchangeRecv: exchangeRecv ?? this.exchangeRecv,
      exchangeSent: exchangeSent ?? this.exchangeSent,
      rstSent: rstSent ?? this.rstSent,
      rstRecv: rstRecv ?? this.rstRecv,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<String>(runId.value);
    }
    if (callsign.present) {
      map['callsign'] = Variable<String>(callsign.value);
    }
    if (stationCallsign.present) {
      map['station_callsign'] = Variable<String>(stationCallsign.value);
    }
    if (exchangeRecv.present) {
      map['exchange_recv'] = Variable<String>(exchangeRecv.value);
    }
    if (exchangeSent.present) {
      map['exchange_sent'] = Variable<String>(exchangeSent.value);
    }
    if (rstSent.present) {
      map['rst_sent'] = Variable<int>(rstSent.value);
    }
    if (rstRecv.present) {
      map['rst_recv'] = Variable<int>(rstRecv.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QsoTableCompanion(')
          ..write('id: $id, ')
          ..write('runId: $runId, ')
          ..write('callsign: $callsign, ')
          ..write('stationCallsign: $stationCallsign, ')
          ..write('exchangeRecv: $exchangeRecv, ')
          ..write('exchangeSent: $exchangeSent, ')
          ..write('rstSent: $rstSent, ')
          ..write('rstRecv: $rstRecv')
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
      required String runId,
      required String callsign,
      required String stationCallsign,
      required String exchangeRecv,
      required String exchangeSent,
      required int rstSent,
      required int rstRecv,
    });
typedef $$QsoTableTableUpdateCompanionBuilder =
    QsoTableCompanion Function({
      Value<int> id,
      Value<String> runId,
      Value<String> callsign,
      Value<String> stationCallsign,
      Value<String> exchangeRecv,
      Value<String> exchangeSent,
      Value<int> rstSent,
      Value<int> rstRecv,
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

  ColumnFilters<String> get runId => $composableBuilder(
    column: $table.runId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get callsign => $composableBuilder(
    column: $table.callsign,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stationCallsign => $composableBuilder(
    column: $table.stationCallsign,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exchangeRecv => $composableBuilder(
    column: $table.exchangeRecv,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exchangeSent => $composableBuilder(
    column: $table.exchangeSent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rstSent => $composableBuilder(
    column: $table.rstSent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rstRecv => $composableBuilder(
    column: $table.rstRecv,
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

  ColumnOrderings<String> get runId => $composableBuilder(
    column: $table.runId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get callsign => $composableBuilder(
    column: $table.callsign,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stationCallsign => $composableBuilder(
    column: $table.stationCallsign,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exchangeRecv => $composableBuilder(
    column: $table.exchangeRecv,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exchangeSent => $composableBuilder(
    column: $table.exchangeSent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rstSent => $composableBuilder(
    column: $table.rstSent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rstRecv => $composableBuilder(
    column: $table.rstRecv,
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

  GeneratedColumn<String> get runId =>
      $composableBuilder(column: $table.runId, builder: (column) => column);

  GeneratedColumn<String> get callsign =>
      $composableBuilder(column: $table.callsign, builder: (column) => column);

  GeneratedColumn<String> get stationCallsign => $composableBuilder(
    column: $table.stationCallsign,
    builder: (column) => column,
  );

  GeneratedColumn<String> get exchangeRecv => $composableBuilder(
    column: $table.exchangeRecv,
    builder: (column) => column,
  );

  GeneratedColumn<String> get exchangeSent => $composableBuilder(
    column: $table.exchangeSent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rstSent =>
      $composableBuilder(column: $table.rstSent, builder: (column) => column);

  GeneratedColumn<int> get rstRecv =>
      $composableBuilder(column: $table.rstRecv, builder: (column) => column);
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
                Value<String> runId = const Value.absent(),
                Value<String> callsign = const Value.absent(),
                Value<String> stationCallsign = const Value.absent(),
                Value<String> exchangeRecv = const Value.absent(),
                Value<String> exchangeSent = const Value.absent(),
                Value<int> rstSent = const Value.absent(),
                Value<int> rstRecv = const Value.absent(),
              }) => QsoTableCompanion(
                id: id,
                runId: runId,
                callsign: callsign,
                stationCallsign: stationCallsign,
                exchangeRecv: exchangeRecv,
                exchangeSent: exchangeSent,
                rstSent: rstSent,
                rstRecv: rstRecv,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String runId,
                required String callsign,
                required String stationCallsign,
                required String exchangeRecv,
                required String exchangeSent,
                required int rstSent,
                required int rstRecv,
              }) => QsoTableCompanion.insert(
                id: id,
                runId: runId,
                callsign: callsign,
                stationCallsign: stationCallsign,
                exchangeRecv: exchangeRecv,
                exchangeSent: exchangeSent,
                rstSent: rstSent,
                rstRecv: rstRecv,
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
