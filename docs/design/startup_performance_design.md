# SSB Runner 启动性能优化设计方案（第 1 / 2 / 3 / 4 / 7 项）

> 状态：待评审
> 适用范围：桌面端启动路径（Windows / macOS / Linux）
> 不在范围：第 5 项（代码签名 / 公证）、第 6 项（数据库目录修复。已由其他改动完成：`db/database_bootstrap.dart` + `common/dirs.dart`）

---

## 1. 背景与实测数据

首次启动慢的主因是 DXCC 前缀词表首次入库。`dxcc_manager.dart` 把 4826 行**逐条 await 插入**，每条独立 commit/fsync；库为空时才会走这条路径。

| 场景 | `BOOT 08 dxcc_loaded` | 出处 |
| --- | --- | --- |
| 首次启动（空库） | **3842 ms** | `debug/crash-2.log`（macOS arm64） |
| 后续启动（命中缓存） | 23–95 ms | `debug/latest.log`、诊断包 |
| SoLoud 初始化 | 81–165 ms | 同上 |
| 其余步骤合计 | < 50 ms | 同上 |

同机复现（sqlite3 CLI，4826 行，`journal_mode=DELETE`）：

| 写法 | 耗时 |
| --- | --- |
| 每行一条自动提交 | **2.80 s** |
| 单事务批量写入 | **0.02 s** |

数据解析侧：

| 步骤 | 耗时 |
| --- | --- |
| gzip 解压 | 6 ms |
| `package:xml` 解析 685 KB + 过滤 | 150 ms |
| 解析生成的 TSV（81 KB / 4826 行） | 5 ms |

前缀查找侧（4826 行，JIT 复现）：

| 写法 | 20 000 次查找 | 单次最坏（未命中） |
| --- | --- | --- |
| `firstWhereOrNull` 线性扫描 | 1555 ms | 165 µs |
| `Map` 查找 | 3 ms | 1 µs |

结论：首次启动 3.8 s 中约 2.8 s 是逐条写库，约 0.15 s 是 XML 解析；后续启动的 23–95 ms 是整表读库；前缀查找的线性扫描会拖慢每一条 QSO 判分。

## 2. 目标与验收标准

| 指标 | 基线 | 目标 |
| --- | --- | --- |
| 首次启动 `dxcc_loaded` | 3842 ms | ≤ 60 ms |
| 首次启动 `application ready` | ≈ 3.9 s | ≤ 600 ms |
| 后续启动 `dxcc_loaded` | 23–95 ms | ≤ 100 ms（不回归） |
| 进程启动到 loading 画面可见 | 存在白窗/空窗 | ≤ 200 ms 且无白窗 |
| 单次前缀查找 | 最坏 165 µs | ≤ 5 µs |
| 回归 | — | `flutter analyze` / `flutter test` 全绿 |

验收以 AOT release 构建的 `BOOT` 日志为准，且必须包含一次**删除数据库目录后的冷启动**。

> 参考：若后续按 §5.6 升级到 B 方案，`dxcc_loaded` 目标为首次与后续均 ≤ 20 ms，且启动不再依赖数据库可用性。该指标不在本次验收范围。

## 3. 方案总览

| 项 | 改动 | 主要文件 | 预期收益 |
| --- | --- | --- | --- |
| 1 | 导入改为单事务 + batch | `lib/dxcc/dxcc_manager.dart` | 首次 −2.7 s 级 |
| 2 | 构建期生成前缀数据，运行时不再解 XML | 新增 `lib/dxcc/prefix_data.dart`、`lib/dxcc/generated/prefix_data.g.dart`、`tool/generate_prefix_data.dart`；改 `dxcc_manager.dart`、`pubspec.yaml` | 首次 −150 ms |
| 3 | SoLoud 初始化与其余启动步骤并行 | `lib/ui/main_app/main_app.dart` | −80〜165 ms |
| 4 | 首帧后再显示窗口，消除白窗 | `lib/main.dart`、`lib/ui/main_app/main_app.dart` | 观感；窗口出现即 loading |
| 7 | 前缀查表改 Map | `lib/dxcc/dxcc_manager.dart` | 单次查找 165 µs → 1 µs |

**决策记录（第 2 项形态）**：采用 **A 方案**——保留 SQLite 前缀快照表，构建期数据只作为首次种子与离线兜底。理由是可扩展性：后端热更新需要"运行时可替换的持久快照 + 原子替换"，现有表配合第 1 项的事务写入正好复用。B 方案（磁盘快照文件）不否决，作为后续升级保留，其对比、前置钩子与两阶段迁移路径见 §5.4–§5.6。

## 4. 分项设计

### 4.1 第 1 项：事务化批量导入

现状（`DxccManager._saveToDb`）：循环 `await insert(...)`，每条语句各自形成一个隐式事务，4826 次 commit/fsync。

目标实现（同时作为热更新接口，见 §5）：

```dart
/// 原子替换整张前缀表：失败则整体回滚，不会留下半张表。
Future<void> replacePrefixes(List<PrefixRow> prefixes) async {
  await database.transaction(() async {
    await delete(database.prefixTable).go();
    await database.batch((batch) {
      batch.insertAll(database.prefixTable, [
        for (final prefix in prefixes)
          PrefixTableCompanion.insert(
            call: prefix.call,
            dxccId: prefix.dxccId,
            continent: prefix.continent,
            cqz: Value(prefix.cqz),
            ituz: Value(prefix.ituz),
          ),
      ]);
    });
  });
}
```

要点：

- `delete` 与 `batch insert` 同事务，形成"替换"语义；首次安装时表为空，等价于插入。
- 空列表时直接返回，避免无意义事务。
- 失败（磁盘、约束、进程被杀）整体回滚；修复了现状"部分写入后 `prefixFromDb.isNotEmpty` 直接使用半张表"的隐患。
- 迁移中的 `delete(prefixTable)` 保持不变，与导入解耦。

可观测性：`dxcc_loaded` 步骤追加字段 `source`（`bundled` / `db`）、`rows`、`dataVersion`、`elapsed`。已有 `BootTrace` 会记录该步骤耗时。

测试：

- 内存数据库（`AppDatabase(NativeDatabase.memory())`）连续两次 `loadDxcc`：第一次 `source=bundled`，第二次 `source=db`，两次 `findCallsignDxccId('K1ABC')` 结果一致。
- 用不可写的执行器注入失败，断言表仍为空（事务回滚）。

预期：`_saveToDb` 由 ≈2.8 s 降到 ≈20–40 ms（含 0.02 s 写库 + 逐行对象构造）。

### 4.2 第 2 项：构建期预生成前缀数据

#### 4.2.1 数据格式

统一为带表头的 TSV（既是编译产物，也是将来热更新的载荷格式）：

```
#dxcc-tsv v1 rows=4826
1A|246|EU|15|28
1S|247|AS|26|50
...
```

- 字段顺序：`call|adif|cont|cqz|ituz`；`cqz` / `ituz` 为空表示 `null`。
- 行序与 `cty.xml.gz` 中 `<prefix record=...>` 顺序一致，保证生成结果可复现。
- 实测 4826 行 / 81 KB；gzip 后约 15–20 KB（热更新下载量）。

#### 4.2.2 模块拆分（为热更新预留）

| 文件 | 职责 | 依赖 |
| --- | --- | --- |
| `lib/dxcc/prefix_row.dart` | 纯数据 `PrefixRow` | 无 |
| `lib/dxcc/cty_xml.dart` | `parseDxccXml(String) -> List<PrefixRow>`（从 `dxcc_manager.dart` 迁出） | `xml`、`collection` |
| `lib/dxcc/prefix_data.dart` | `parsePrefixRows(String) -> List<PrefixRow>`、`const int dxccBundledDataVersion = 1` | 无 |
| `lib/dxcc/generated/prefix_data.g.dart` | `const String dxccPrefixTsv`（生成文件，入库） | 无 |
| `tool/generate_prefix_data.dart` | 读 `assets/dxcc/cty.xml.gz`，复用 `cty_xml.dart`，写生成文件 | `archive`、`xml` |

拆分后 `DxccManager` 不再依赖 XML / gzip / isolate；`PrefixRow` 与 `PrefixTableData`（drift 生成类）之间做一次显式映射。

#### 4.2.3 生成工具

```dart
// tool/generate_prefix_data.dart
Future<void> main() async {
  final bytes = File('assets/dxcc/cty.xml.gz').readAsBytesSync();
  final rows = parseDxccXml(utf8.decode(GZipDecoder().decodeBytes(bytes)));
  final tsv = StringBuffer('#dxcc-tsv v1 rows=${rows.length}\n')
    ..writeAll(rows.map((r) => '${r.call}|${r.dxccId}|${r.continent}|'
        '${r.cqz ?? ''}|${r.ituz ?? ''}\n'));
  File('lib/dxcc/generated/prefix_data.g.dart').writeAsStringSync(
    "// GENERATED CODE - DO NOT MODIFY BY HAND.\n"
    "// Regenerate: dart run tool/generate_prefix_data.dart\n"
    "const String dxccPrefixTsv = r'''\n$tsv''';\n",
  );
}
```

生成文件写入主仓库（`lib/`），不写 `assets/` 子模块，避免跨仓库提交。

#### 4.2.4 运行时加载

```dart
Future<void> loadDxcc() async {
  final snapshot = await _loadSnapshot(); // 唯一读库入口，B 方案只替换这里
  if (snapshot.isNotEmpty) {
    _assign(snapshot);
    log.info('dxcc loaded', tag: 'dxcc',
        fields: {'source': 'db', 'rows': snapshot.length});
    return;
  }

  final bundled = parsePrefixRows(dxccPrefixTsv); // ≈5 ms
  await replacePrefixes(bundled);                 // 唯一写库入口
  _assign(bundled);
  log.info('dxcc loaded', tag: 'dxcc', fields: {
    'source': 'bundled',
    'rows': bundled.length,
    'dataVersion': dxccBundledDataVersion,
  });
}
```

`database.*` 只允许出现在 `_loadSnapshot()` 与 `replacePrefixes()` 内，其余逻辑只处理 `List<PrefixRow>`。这是 A→B 升级（§5.6）能只改这两处的前提。

- 去掉 `workerManager.execute`：解析 5 ms，远小于 isolate 启动成本（约 10–20 ms）。
- `worker_manager` 仍被 `wav_to_pcm.dart`、`concat_bytes.dart` 使用，依赖与 `worker_manager_init` 步骤保留。
- `pubspec.yaml` 移除 `assets/dxcc/`（运行时不再读；该目录下的 `generate_cty.py`、`cty.xml.gz` 目前会被打进包，顺带省 51 KB 与 2 个文件）。`xml` / `archive` 仍被 `lib` 其他模块使用，依赖保留。

#### 4.2.5 一致性保障

`test/dxcc_loader_test.dart` 扩展为对拍：

```dart
final xmlRows = parseDxccXml(xmlString);
final bundledRows = parsePrefixRows(dxccPrefixTsv);
expect(bundledRows.length, xmlRows.length);
for (var i = 0; i < xmlRows.length; i++) {
  expect(bundledRows[i].call, xmlRows[i].call);
  expect(bundledRows[i].dxccId, xmlRows[i].dxccId);
  expect(bundledRows[i].continent, xmlRows[i].continent);
  expect(bundledRows[i].cqz, xmlRows[i].cqz);
  expect(bundledRows[i].ituz, xmlRows[i].ituz);
}
```

资产更新后若忘记重新生成，CI 的 `flutter test` 直接失败。这是唯一需要人工记住的流程点，写进生成文件头部注释。

预期：首次 `dxcc_loaded` ≈ 5 ms（解析）+ 20–40 ms（事务写入）≈ 25–45 ms；后续不变（整表读库 23–95 ms）。

### 4.3 第 3 项：SoLoud 初始化并行

现状：`soloud_init` 与 `window_ready` 串行，音频 81–165 ms 完全落在关键路径上。

目标：

```dart
// _MainAppCubit.load
final audioReady = boot.step('soloud_init', _initAudio); // 先启动，不 await
await boot.step('prefs_ready', ...);
...
await boot.step('dxcc_loaded', dxccManager.loadDxcc);
await boot.step('callsign_loaded', callsignLoader.loadCallsigns);
await audioReady;                                        // 仍以音频就绪为 Ready 前提
emit(_Ready(...));
```

- `_initAudio` 内部已有 try/catch，音频失败不阻断启动，行为不变。
- `SSB_RUNNER_DISABLE_AUDIO=1` 的 CI 分支不变。
- **必须等 `audioReady` 再进 `_Ready`**：`AudioPlayer._startSegment` 在引擎未初始化时直接丢弃片段（`audio_player.dart`），提前可交互会吞掉第一句语音。
- `BootTrace.step` 在开始时分配序号，因此会看到 `BOOT 04 soloud_init start`、`BOOT 05 prefs_ready start` 交错，`ok` 行不保证按序号出现。这是预期行为；如需严格顺序，可给每条记录增加 `label` 而不改序号机制（本次不做）。

预期：音频初始化与后续约 50–200 ms 的工作重叠，关键路径减少 80–165 ms。

### 4.4 第 4 项：首帧优先、消除白窗

现状链路：

1. `main()` 依次 `await bootstrapLogging()`（`path_provider` 两次 + `PackageInfo` + 目录探测）和 `initErrorHandling()`，之后才 `runApp`；
2. macOS 的 `MainFlutterWindow` 来自 XIB，窗口启动即可见；`window_manager` 在 macOS 上 `waitUntilReadyToShow` 是**空实现**（已核对 `window_manager-0.5.1` 源码）；
3. Windows runner 在**首帧回调里**才 `ShowWindow`（`windows/runner/flutter_window.cpp`）。

所以白窗只出现在 macOS / Linux：窗口先可见，内容要等 `runApp` + 首帧，而 `runApp` 又被启动日志的插件调用推迟了数十毫秒。

目标实现：

```dart
// main.dart
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await bootstrapLogging();
    await _hideWindowUntilFirstFrame();
    final (debugOptions, releaseOptions) = await initErrorHandling();
    Catcher2(rootWidget: const MainApp(), ...);
  }, ...);
}

Future<void> _hideWindowUntilFirstFrame() async {
  try {
    await windowManager.ensureInitialized();
    await windowManager.hide();
  } catch (error, stackTrace) {
    log.warn('window hide failed', tag: 'boot',
        error: error, stackTrace: stackTrace);
  }
}
```

```dart
// _MainAppState.initState
WidgetsBinding.instance.addPostFrameCallback((_) => _revealWindow());

Future<void> _revealWindow() async {
  try {
    await windowManager.setSize(const Size(1280, 720));
    await windowManager.center();
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(1024, 650));
  } catch (error, stackTrace) {
    log.warn('window configure failed', tag: 'boot',
        error: error, stackTrace: stackTrace);
  }
  try {
    await windowManager.show();
    await windowManager.focus();
  } catch (error, stackTrace) {
    log.error('window show failed', tag: 'boot',
        error: error, stackTrace: stackTrace);
  }
}
```

- 删除 `_MainAppCubit._initWindow` 与 `window_ready` 步骤；窗口尺寸/最小尺寸挪到首帧回调，**先配置再 show**，避免可见后再 resize 闪动。
- 首帧内容仍是现有的 `_Loading`（surface 底色 + 进度圈），因此窗口出现的第一眼就是 loading。
- 失败态 `_StartupFailure` 同样在首帧之后，不依赖 cubit 状态，窗口一定会显示。
- Windows/Linux 上 `hide()` 与 runner 的自动 show 不冲突（重复 show 无害）；即使 `hide()` 抛错也只是退回现状。

> **实现说明（macOS 实测，2026-10-29）**：`windowManager.hide()` 会让进程退出——runner 的
> `AppDelegate.applicationShouldTerminateAfterLastWindowClosed` 返回 `true`，窗口被 `orderOut`
> 后应用收到退出请求，`AppLifecycleListener.onExitRequested` 随即 `deinit()` 打断 SoLoud 初始化并终止进程。
> 因此改为「透明度隐藏」：`main()` 中 `ensureInitialized()` + `setOpacity(0)`，首帧回调里配置尺寸后
> `setOpacity(1)` + `show/focus`。窗口始终保持 visible，既不触发退出也不显示白窗。
> 另外 macOS 的 `windowManager` 只有在 `ensureInitialized()` 时才会绑定原生窗口（否则 Swift 侧强制解包 nil
> 直接崩溃），所以 `_revealWindow` 也必须先调用一次。

不做（收益过小）：把 `bootstrapLogging` 拆成"装文件 sink"和"记录 PackageInfo/环境探测"两段。后者仅 ~10–20 ms，且提前安装文件 sink 是崩溃可观测性的前提。

### 4.5 第 7 项：前缀查找 O(1)

现状：`_findMatchPrefixData` 对 4826 条做 `firstWhereOrNull`，并按前缀逐字符回退，单次查找放大 3–6 倍。

目标：

```dart
late final Map<String, PrefixRow> _prefixByCall;

void _assign(List<PrefixRow> prefixes) {
  _prefixByCall = <String, PrefixRow>{};
  for (final prefix in prefixes) {
    final existing = _prefixByCall[prefix.call];
    if (existing != null) {
      log.warn('duplicate dxcc prefix', tag: 'dxcc',
          fields: {'call': prefix.call});
      continue;
    }
    _prefixByCall[prefix.call] = prefix;
  }
}

PrefixRow? _findMatchPrefixData(String prefix) {
  var checked = prefix;
  while (checked.isNotEmpty) {
    final match = _prefixByCall[checked];
    if (match != null) {
      return match;
    }
    checked = checked.substring(0, checked.length - 1);
  }
  return null;
}
```

- 现有 `cty.xml.gz` 的 4826 条 `call` 已验证无重复；热更新数据若出现重复，按先到先得并告警。
- 大小写行为保持不变（与现状一致，均为大小写敏感），不在本项做归一化，避免行为变化。
- `findCallsignDxccId` 继续使用 `_prefixToDxccMap`；也可直接复用 `_prefixByCall` 的 `dxccId`，减少一份映射。
- **不加数据库索引、不升 schema**：查找已在内存完成，索引没有收益。

预期：单次查找 165 µs → 1 µs；一场比赛数千次判分从秒级抖动降到可忽略。

## 5. 数据快照形态：A 方案（已决策）与 B 方案（后续升级）

### 5.1 问题

编译期生成的数据是只读的，不能远程替换。因此"预生成数据"本身不提供热更新能力；是否方便做后端热更新，取决于**运行时可变快照**放在哪里。

三种可选形态：

| 形态 | 首次启动 | 后续启动 | 热更新 | 离线兜底 | 复杂度 |
| --- | --- | --- | --- | --- | --- |
| 仅编译内数据 | ≈5 ms | ≈5 ms | **不支持**，必须发版 | 支持 | 低 |
| **A：编译内种子 + DB 快照（本次采用）** | 25–45 ms | 23–95 ms | 支持：下载 → 单事务替换 | 支持（种子回灌） | 中 |
| B：编译内种子 + 磁盘快照文件 | 5–10 ms | 5–10 ms | 支持：下载 → 临时文件 + 原子 rename | 支持 | 中（需自建原子写 / 校验，并升 v6 删表） |

**决策：本次实现 A；B 作为后续升级保留，前置钩子与升级路径见 §5.5、§5.6。**

### 5.2 形态 A：DB 快照（本次实现）

```
启动
  compile-time dxccPrefixTsv ──(仅首次)──> 单事务 replacePrefixes ──> SQLite prefix_table
                                                                          │
                                                  每次启动 select 4826 行 <┘
                                                                          │
                                                              内存 Map（判分用）

热更新（阶段二）
  后端 manifest ──> 下载 gzip TSV ──> 校验 ──> 单事务替换 prefix_table ──> reload 内存 Map
```

- 只有 2 个存储入口：`_loadSnapshot()`（读库）与 `replacePrefixes()`（写库），其余逻辑与存储无关。
- 版本号放 `SharedPreferences`（`dxccDataVersion`），不额外升 schema。
- 首次与热更新共用同一个写入原语，第 1 项的实现直接复用。

### 5.3 形态 B：磁盘快照文件（后续升级，本次不实现）

```
启动
  compile-time dxccPrefixTsv ──(首次/兜底)──┐
                                            ├──> 内存 Map（判分用）
  磁盘 dxcc_tsv.gz（含版本头）── 解压 + 解析 ┘
            ▲
            └── 热更新：下载 → 校验 → 临时文件 → 同卷 rename

热更新流程
  1. 下载 gzip TSV，sha256 校验
  2. File('.../dxcc_tsv.gz.tmp').writeAsBytes(payload, flush: true)
  3. tmp.rename('.../dxcc_tsv.gz')            // 同卷 rename 原子
  4. reload(parsePrefixRows(gunzip(payload)))
```

- 版本写在文件头（`#dxcc-tsv v1 version=12 rows=4826`），与数据自洽，不需要额外元数据表。
- 启动完全不依赖 SQLite，`db_ready` 可移出关键路径（历史库延后到 `ContestDataManager` 首次读库时打开）。
- 参考数据（DXCC）与用户数据（QSO / 训练日志）彻底分离，清空历史、备份、导出都不会牵连前缀表。

### 5.4 A / B 详细对比

#### 5.4.1 启动成本

| 阶段 | A | B |
| --- | --- | --- |
| 首次启动（无快照） | 解析种子 5 ms + 事务写库 20–40 ms ≈ **25–45 ms** | 解析种子 5–10 ms ≈ **5–10 ms** |
| 后续启动 | drift 打开库 + `select` 4826 行 + 对象映射 ≈ **23–95 ms** | 读文件 1–3 ms + 解压 1–5 ms + 解析 5–10 ms + 建 Map ≈ **10–20 ms** |
| 是否依赖 DB 可用 | 是；库打不开则前缀不可用 | 否；库不可用不影响判分 |
| DB 打开时机 | 启动关键路径内 | 首帧之后（历史库按需打开） |

后续启动的差距来自 drift 的全表读取与行对象映射，不在解析本身。

#### 5.4.2 热更新机制

| | A | B |
| --- | --- | --- |
| 写入方式 | `delete + batch insert` 单事务 | 临时文件 + 同卷 `rename` |
| 原子性来源 | SQLite 事务 | 文件系统 rename 语义 |
| 版本一致性 | 版本号在 prefs，与事务非原子（极端情况只会重复下载） | 版本号在文件头，天然原子 |
| 校验责任 | SQLite 页校验兜住大部分损坏 | 必须自己校验 sha256 / 结构 / 行数 |
| 回滚到上一版 | 需要保留旧行或重新下发旧版 | 保留 `.bak` 文件，一步回滚 |
| 失败处理面 | 数据库锁、磁盘、约束 | 文件不存在、权限、磁盘满、半写、格式升级 |

#### 5.4.3 代码、迁移与测试影响

| | A | B |
| --- | --- | --- |
| schema | 保持 v5 | 升 v6：`deleteTable('prefix_table')` |
| `DxccManager` 构造 | 保持 `DxccManager(database: ...)` | 去掉 `AppDatabase` 依赖 |
| Provider / 测试签名 | 不变 | `main_app.dart` + 4 处测试同步修改 |
| 第 1 项（事务导入） | 需要，且是热更新写入口 | 不再需要（无写库路径） |
| 新增基础设施 | 无 | 文件位置、gzip 读写、临时文件清理、`.bak` 策略 |
| 新增依赖 | 无 | 无（`archive` 已在依赖中） |
| 包体 / 存储 | DB 增长约 200 KB+ | 81 KB 原始 / 15–20 KB gzip，种子仍编译在包内 |
| 新增测试 | 内存库两次加载、事务回滚 | 临时目录读写、损坏文件回落、原子替换 |

#### 5.4.4 长期维护

- **A 的优势**：前缀可进 SQL，将来若要做按 DXCC 统计、前缀编辑等查询有现成载体；事务语义免维护。
- **A 的代价**：只读参考数据放进用户库，生命周期与 QSO/日志不同，备份、清空历史时要小心；历史上 v3/v4/v5 都靠"清空前缀表"来换数据，schema 演进与数据缓存耦合。
- **B 的优势**：参考数据独立、可自描述版本、可原子替换与单步回滚；启动不受 DB 故障影响；每次启动少 15–85 ms。
- **B 的代价**：多一套文件生命周期管理，需要自己做校验与原子写；`DxccManager` 与 DB 解耦会牵动测试。

### 5.5 本次需要预留的钩子（成本低）

| 钩子 | 位置 | 作用 |
| --- | --- | --- |
| `const int dxccBundledDataVersion = 1` | `lib/dxcc/prefix_data.dart` | 与后端 manifest 版本比较 |
| `_loadSnapshot()`（唯一读库入口） | `DxccManager` | A→B 时只替换这一处 |
| `replacePrefixes(List<PrefixRow>)`（唯一写库入口） | `DxccManager` | 首次播种与热更新共用 |
| `_assign(List<PrefixRow>)` / `reload(List<PrefixRow>)` | `DxccManager` | 与存储无关，B 直接复用 |
| `parsePrefixRows(String)` | `lib/dxcc/prefix_data.dart` | 种子、下载载荷、A→B 导出共用解析器 |
| `source` / `rows` / `dataVersion` 日志字段 | `dxcc_loaded` | 线上可判断数据来源与版本 |

额外约束：`DxccManager` 中**除 `_loadSnapshot()` 与 `replacePrefixes()` 外，不得出现 `database.*` 调用**。这条约束是 A→B 低成本迁移的前提。

### 5.6 A → B 升级路径（后续执行，本次只保证可行）

采用两阶段迁移，避免在 drift `onUpgrade` 内做文件 IO，也避免数据丢失。

**阶段 1（schema 仍为 v5）**：加入文件快照读取，DB 作为一次性导出源。

```text
// loadDxcc 内，按优先级读取
1) 文件快照存在且解析成功      -> source=file
2) DB 快照非空                -> source=db，并把行导出成文件（仅一次）
3) 编译内种子                 -> source=bundled，写文件
```

导出使用运行时编码器 `encodePrefixTsv(List<PrefixRow>, version)`（与生成工具同一格式，新增约 20 行）。这一版可独立发版、独立回滚。

**阶段 2（schema v6）**：确认阶段 1 稳定后进行。

1. `onUpgrade(from < 6)` 执行 `deleteTable('prefix_table')`；
2. 删除 `PrefixTable`、`_loadSnapshot()`、`replacePrefixes()` 与全部 DB 相关代码；
3. `DxccManager` 去掉 `AppDatabase` 依赖，修改 `main_app.dart` 的 Provider 与 4 处测试构造；
4. `db_ready` 从启动关键路径移除，历史库改为按需打开；
5. 删除 `replacePrefixes` 相关事务测试，改为文件快照测试。

**数据安全**：阶段 1 已把现存 DB 行导出为文件，阶段 2 删表不会丢数据；文件保留 `.bak` 以便回滚。

**收益**：升级后首次与后续启动的 `dxcc_loaded` 均 ≤ 20 ms，且启动不再依赖数据库可用性。

**回滚**：阶段 1 可直接 revert；阶段 2 回滚需同时回退 schema（`prefix_table` 已删，回滚版本会在 `onCreate` 重建空表并回落到种子，热更新数据仍可从文件恢复），因此阶段 2 只在阶段 1 观察一个版本后再执行。

### 5.7 约束与风险

- **赛事期间不换数据**：`cqz` / `ituz` / `dxccId` 会影响 CQ WW、JIDX 等默认交换与判分，只允许在两场比赛之间应用，且必须记录版本。
- 数据格式必须版本化（表头 `#dxcc-tsv v1`）；后续新增字段用 `v2` 并保持旧解析器可读，避免老客户端直接崩。
- 降级安装不会回滚数据（DB 里仍是新数据），这是期望行为；编译内种子只作兜底。
- 热更新引入网络后，需要超时、重试与"仅手动检查/静默失败"策略，不影响启动（阶段二单独设计）。

## 6. 实施后的启动时序

```
进程启动
  ├─ bootstrapLogging            ~10–30 ms   文件日志就绪（崩溃可观测）
  ├─ window hide                 ~5 ms       macOS/Linux 不再白窗
  ├─ initErrorHandling           ~1 ms
  └─ runApp → 首帧（loading）
       ├─ post-frame: 配置窗口 + show/focus   ~5–15 ms
       ├─ soloud_init  ┐ 并行启动            80–165 ms
       ├─ prefs_ready  │                     ~1–3 ms
       ├─ worker_manager_init                  ~4 ms
       ├─ db_ready                             ~5–20 ms
       ├─ dxcc_loaded  │ bundled 首次 25–45 ms / db 后续 23–95 ms
       ├─ callsign_loaded                     7–16 ms
       └─ await soloud_init                   与上面重叠
  └─ application ready
```

预期首次 `application ready` ≈ 300–500 ms（基线 ≈3.9 s）。

## 7. 改动清单与实施顺序

按依赖顺序分四批，每批可独立提交、独立回滚。

| 批次 | 内容 | 文件 |
| --- | --- | --- |
| 1 | 前缀查找改 Map（无行为变化） | `lib/dxcc/dxcc_manager.dart`；新增查表测试 |
| 2 | `PrefixRow` / `cty_xml.dart` / `prefix_data.dart` 拆分 + 生成工具 + 生成文件 + 事务化 `replacePrefixes` + `loadDxcc` 改走种子 | `lib/dxcc/`（新增 4 个文件）、`test/dxcc_loader_test.dart`、`test/dxcc_manager_test.dart`（新增）、`pubspec.yaml` |
| 3 | SoLoud 并行 | `lib/ui/main_app/main_app.dart` |
| 4 | 首帧优先与窗口显示 | `lib/main.dart`、`lib/ui/main_app/main_app.dart` |

批次 2 的注意点：

- 生成文件（约 84 KB）必须提交；`assets/` 是子模块，不把生成物写进去。
- `pubspec.yaml` 删除 `- assets/dxcc/`；`tool/generate_prefix_data.dart` 与测试从磁盘读 `assets/dxcc/cty.xml.gz`。
- `xml`、`archive`、`worker_manager` 依赖保留（`lib` 其他模块仍在使用）。

## 8. 测试与验收

自动化：

- `test/dxcc_loader_test.dart`：XML 与生成数据逐行对拍（§4.2.5）。
- `test/dxcc_manager_test.dart`：内存库两次 `loadDxcc` 的 `source`、行数、`findCallsignDxccId` / `findCallsignCqZone` / `findCallsignContinent` 结果；前缀回退（如 `K1ABC` → `K`）与未命中（`null` / `-1`）。
- 事务回滚：注入失败后断言表为空。
- 现有 UI 测试使用 `DxccManager(database: ...)`；A 方案保持构造签名不变，这些测试无需改动（B 方案才需要批量调整，见 §5.6）。

手工（release 构建）：

1. 删除数据库目录（`<app support>/db`）后冷启动，检查 `BOOT` 日志：`dxcc_loaded` ≤ 60 ms、`source=bundled`、无白窗。
2. 再次启动：`source=db`，耗时 ≤ 100 ms。
3. 观察 `soloud_init` 与 `prefs_ready` 交错的 `start` 记录，`application ready` ≤ 600 ms。
4. 拔掉音频设备 / `SSB_RUNNER_DISABLE_AUDIO=1` 各启动一次，确认不阻塞、不崩溃。

## 9. 风险与回滚

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 生成数据与 XML 不一致 | 判分错误 | 对拍测试；生成文件头写明重生成命令 |
| 事务写入失败 | 前缀不可用 | 回滚保持空表，启动警告（现有 `dxcc_loaded` 失败降级逻辑） |
| 并行音频时序 | 首句语音被丢弃 | `_Ready` 仍等待 `audioReady` |
| 窗口 hide/show 异常 | 无窗口 | 每步 try/catch + 固定 show 兜底；失败回退现状 |
| `BootTrace` 序号交错 | 日志阅读困惑 | 文档说明；不改序号机制 |

回滚粒度：四个批次各自独立，任一批次异常可单独 revert，不影响其他批次。

## 10. 后续可选（不在本次范围）

- **B 方案升级**：按 §5.6 的两阶段迁移，把前缀快照从 SQLite 移到磁盘文件（首次与后续启动均 ≤ 20 ms，schema v6）。本次已按 §5.5 预留 `_loadSnapshot()` / `replacePrefixes()` 两个存储入口，升级时只替换这两处。
- 第 5 项：macOS Developer ID + 公证、Windows 代码签名。
- 语音资源打包为单归档，减少首次启动的系统级文件扫描数量。
