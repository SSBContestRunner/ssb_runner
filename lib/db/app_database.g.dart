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
  @override
  List<GeneratedColumn> get $columns => [id, call, dxccId];
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
  const PrefixTableData({
    required this.id,
    required this.call,
    required this.dxccId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['call'] = Variable<String>(call);
    map['dxcc_id'] = Variable<int>(dxccId);
    return map;
  }

  PrefixTableCompanion toCompanion(bool nullToAbsent) {
    return PrefixTableCompanion(
      id: Value(id),
      call: Value(call),
      dxccId: Value(dxccId),
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
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'call': serializer.toJson<String>(call),
      'dxccId': serializer.toJson<int>(dxccId),
    };
  }

  PrefixTableData copyWith({int? id, String? call, int? dxccId}) =>
      PrefixTableData(
        id: id ?? this.id,
        call: call ?? this.call,
        dxccId: dxccId ?? this.dxccId,
      );
  PrefixTableData copyWithCompanion(PrefixTableCompanion data) {
    return PrefixTableData(
      id: data.id.present ? data.id.value : this.id,
      call: data.call.present ? data.call.value : this.call,
      dxccId: data.dxccId.present ? data.dxccId.value : this.dxccId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PrefixTableData(')
          ..write('id: $id, ')
          ..write('call: $call, ')
          ..write('dxccId: $dxccId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, call, dxccId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PrefixTableData &&
          other.id == this.id &&
          other.call == this.call &&
          other.dxccId == this.dxccId);
}

class PrefixTableCompanion extends UpdateCompanion<PrefixTableData> {
  final Value<int> id;
  final Value<String> call;
  final Value<int> dxccId;
  const PrefixTableCompanion({
    this.id = const Value.absent(),
    this.call = const Value.absent(),
    this.dxccId = const Value.absent(),
  });
  PrefixTableCompanion.insert({
    this.id = const Value.absent(),
    required String call,
    required int dxccId,
  }) : call = Value(call),
       dxccId = Value(dxccId);
  static Insertable<PrefixTableData> custom({
    Expression<int>? id,
    Expression<String>? call,
    Expression<int>? dxccId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (call != null) 'call': call,
      if (dxccId != null) 'dxcc_id': dxccId,
    });
  }

  PrefixTableCompanion copyWith({
    Value<int>? id,
    Value<String>? call,
    Value<int>? dxccId,
  }) {
    return PrefixTableCompanion(
      id: id ?? this.id,
      call: call ?? this.call,
      dxccId: dxccId ?? this.dxccId,
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
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PrefixTableCompanion(')
          ..write('id: $id, ')
          ..write('call: $call, ')
          ..write('dxccId: $dxccId')
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
    });
typedef $$PrefixTableTableUpdateCompanionBuilder =
    PrefixTableCompanion Function({
      Value<int> id,
      Value<String> call,
      Value<int> dxccId,
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
              }) => PrefixTableCompanion(id: id, call: call, dxccId: dxccId),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String call,
                required int dxccId,
              }) => PrefixTableCompanion.insert(
                id: id,
                call: call,
                dxccId: dxccId,
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
