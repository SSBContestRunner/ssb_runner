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

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PrefixTableTable prefixTable = $PrefixTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [prefixTable];
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

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PrefixTableTableTableManager get prefixTable =>
      $$PrefixTableTableTableManager(_db, _db.prefixTable);
}
