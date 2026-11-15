# CI run 43677974432 失败分析：Windows COM 析构 `override` 与 AppImage 重打包静默失败

> 分析时间：2026-11-15
> 关联 CI run：[43677974432](https://github.com/SSBContestRunner/ssb_runner/actions/runs/43677974432)（`workflow_dispatch`，分支 `fix/v0.3.0-bugs`，2026-11-15 04:49Z 起）
> 被验证提交：`67103b9 fix(platform): declare macOS 13 and enforce the Linux glibc 2.35 floor`（父提交 `15bbc85` / #72）
> 实施状态：**决策已定（2026-11-15）：§5 技术方案全部实施，无删减、无延后**（逐项决策见 §5.0，落地顺序见 §7）。§5 已落地到 `windows/runner/audio_output_probe.h`、`.github/scripts/trim-appimage-libjvm.sh` 与 `.github/workflows/ci.yml`；CI 侧的逐项确认仍待一次 `workflow_dispatch`（§6）。
> 结论置信度：Windows 侧为编译器诊断直证；Linux 侧为 CI 日志与本次上传产物（`7z -slt` 实测）互证。

---

## 0. 结论

本轮是**两个彼此独立的故障**，外加一个让它们没能提前暴露的**流程缺口**。

| # | 失败作业 | 直接原因 | 根因 |
|---|---|---|---|
| 1 | `Package (windows)` | MSVC `error C3668` | [audio_output_probe.h#L21-L29](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/windows/runner/audio_output_probe.h#L21-L29) 给析构函数加了 `override`，而 COM 接口不声明析构函数 |
| 2 | `Smoke test (Debian 12)` | AppImage 仍含 `usr/lib/libjvm.so` | 重打包被新版 appimagetool 的目录权限校验拒绝（提取后目录全为 0700）；[trim-appimage-libjvm.sh](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/scripts/trim-appimage-libjvm.sh#L54-L59) 又把该失败吞掉并返回 0 |
| 3 | （放大因素） | 均未在 PR 暴露 | `package-*` 只在 tag / `workflow_dispatch` 运行，PR 与主干 push 只跑 analyze + test |

**影响面**：无产物被错误发布。`Package (linux)` 虽显示绿色，但其 AppImage 大小前后完全一致（35625464 → 35625464 bytes），说明 libjvm.so 从未被裁掉；是 [smoke-test-debian.sh#L133-L137](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/scripts/smoke-test-debian.sh#L133-L137) 的断言兜住了它，进而阻断 release。冒烟测试的设计是有效的，问题是失败定位被推迟到了另一个作业。

**不受影响**：`deb`、`zip`、macOS 全部正常；libjvm.so 只存在于 AppImage（见脚本头注释的成因说明）。

**决策（2026-11-15）**：§5 的 8 项修复（A、B1–B4、C1–C3）**全部实施**，逐项确认见 §5.0，落地顺序见 §7。

---

## 1. 本轮作业结果

| 作业 | 结果 | 耗时 |
|---|---|---|
| Analyze & Test | 通过 | 4m42s |
| Resolve build matrix | 通过 | 2s |
| Package (windows) | **失败** | 12m21s |
| Package (linux) | 通过（但见 §3.4） | 3m44s |
| Package (macos) | 通过 | 11m38s |
| Smoke test (Debian 12) | **失败** | 27s |
| Smoke test (macOS) | 通过 | 1m4s |
| Smoke test (Windows) / (Windows installer) / Draft GitHub Release | 跳过（依赖 Windows 打包） | 0s |

---

## 2. Windows：`error C3668`

### 2.1 现象

`Build & package` 阶段 `fastforge package` 失败，三次重试报同一个编译错误（确定性错误，重试无意义）：

```text
D:\a\ssb_runner\ssb_runner\windows\runner\audio_output_probe.h(29,4): error C3668:
'AudioOutputProbe::~AudioOutputProbe': method with override specifier 'override'
did not override any base class methods
[D:\a\ssb_runner\ssb_runner\build\windows\x64\runner\ssb_runner.vcxproj]

BuildError: ... error C3668 ... 
Build process failed.
```

三次尝试分别在 04:49:44 / 04:53:56 / 04:57:09 启动，05:00:08 判定失败——一个 3 行就能定位的编译错误消耗了约 12 分钟。

### 2.2 代码与诊断

[audio_output_probe.h#L21-L29](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/windows/runner/audio_output_probe.h#L21-L29)：

```cpp
class AudioOutputProbe : public IMMNotificationClient,
                         public IAudioEndpointVolumeCallback {
 public:
  ...
  ~AudioOutputProbe() override;   // ← C3668
```

`IMMNotificationClient` 与 `IAudioEndpointVolumeCallback` 是 `mmdeviceapi.h` / `endpointvolume.h` 里由 MIDL 生成的 **COM 接口**。COM 接口只有纯虚方法，**没有析构函数**，因此不存在可被 `override` 覆盖的基类析构：

- 该 `override` 在语法层面非法，MSVC 报 C3668；
- 工程使用 `/W4 /WX`（[windows/CMakeLists.txt#L40-L46](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/windows/CMakeLists.txt#L40-L46)），所以它是硬错误而非警告。

语义上也没有问题：实例由 `FlutterWindow` 以 `std::unique_ptr<AudioOutputProbe>` 持有（[flutter_window.h#L39](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/windows/runner/flutter_window.h#L39)），从不经接口指针 `delete`。析构函数体（[audio_output_probe.cpp#L90-L92](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/windows/runner/audio_output_probe.cpp#L90-L92)）只调用 `Unsubscribe()`，与虚析构无关。

### 2.3 引入点

该文件由 #72（`15bbc85 feat(audio): warn when the output cannot be heard`）引入，本轮是它第一次在 Windows 上编译。

### 2.4 为什么 PR 没拦住

[ci.yml#L231-L236](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/workflows/ci.yml#L231-L236)：

```yaml
package-windows:
  needs: [analyze, setup]
  if: >-
    startsWith(github.ref, 'refs/tags/v') ||
    (github.event_name == 'workflow_dispatch' && contains(needs.setup.outputs.matrix, '"platform":"windows"'))
```

- PR 的 `Package (windows)` 被跳过（同一 PR 的 run `43677971964` 结论为 success，但其中没有任何 Windows 编译）；
- 主干 push 同理；
- `Analyze & Test` 跑在 `ubuntu-latest` 上，只做 `flutter analyze` + `flutter test`，不触碰 `windows/runner/*.cpp`。

结论：**native 侧代码在 PR 阶段完全无门禁**，任何 Windows/macOS/Linux C++ 改动都要等到 tag 打包或手工 dispatch 才会被编译。

---

## 3. Linux：AppImage 重打包静默失败

### 3.1 现象

`Package (linux)` 的 `Trim libjvm.so copied into the AppImage` 步骤看起来成功，但末尾有两行互相矛盾的输出：

```text
mv: cannot stat '/tmp/tmp.R4DpkD7UNq/trimmed.AppImage': No such file or directory
ssb_runner-0.3.0+300006-linux.AppImage: dropped usr/lib/libjvm.so, 35625464 -> 35625464 bytes
```

大小前后完全相同，等于没做任何裁减。随后 `Smoke test (Debian 12)` 在静态检查阶段报：

```text
##[error]AppImage still bundles usr/lib/libjvm.so (trim-appimage-libjvm.sh did not run)
```

### 3.2 失败链条

1. 脚本 `cp` 出 AppImage 后执行 `./app.AppImage --appimage-extract`，得到 `squashfs-root`；
2. **提取出的目录全部是 `0700`**（详见 §3.3），包括 `mktemp -d` 建的 AppDir 根目录本身；
3. 本次 CI 从 `continuous` 下载的 appimagetool 是 **build 370（2026-11-06）**，它对"其他用户不可读/不可执行"的目录执行**致命校验**：

   ```text
   ##[error]/tmp/tmp.R4DpkD7UNq/squashfs-root
          this directory has mode 0700 (rwx------) ...
   appimagetool: found 1 ERROR(S) in the AppDir, nothing was changed and no AppImage was created.
   ```

   其余 60 条同类问题以 `::warning::Problem n/60` 形式打印，全部是目录；
4. 因为没有产出，`mv "$work/trimmed.AppImage"` 失败；
5. 但该失败没有中断脚本（§3.4），最终仍打印"dropped ... 35625464 -> 35625464 bytes"并以 0 退出；
6. 失败被推迟到 Debian 冒烟测试才暴露。

### 3.3 关键证据：镜像本身是 0755，0700 来自提取

下载本次运行的产物 `ssb-runner-linux`（即 packager 的原始 AppImage，未经成功裁减），直接读取其 squashfs 条目权限：

```text
Type = SquashFS            Offset = 944632            File System = SquashFS 4.0
Method = ZSTD              Big-endian = -

$ 7z l -slt ssb_runner-0.3.0+300006-linux.AppImage | grep "Mode = d" | sort | uniq -c
  60 Mode = drwxr-xr-x
```

即：**镜像内 60 个目录无一例外是 0755**。而 appimagetool 报告的正是"60 条目录警告 + 1 条根目录错误" = 61 个目录，与镜像目录数（60 + AppDir 根）**一一对应**。

据此可以排除两种猜测：

- 不是 packager 产出了坏权限（镜像内权限正确，且 packager 用同一个 appimagetool 成功完成了首次打包）；
- 不是 runner 的 umask 问题（umask 会同时影响普通文件，而镜像内文件权限是 0644 / 0755，appimagetool 也只对目录报警）。

结论：**`--appimage-extract` 这一步没有把 squashfs 里记录的目录权限写回，所有目录被建成 0700**。这与脚本"提取后直接重打包"的假设冲突。

### 3.4 为什么失败被吞掉

[trim-appimage-libjvm.sh#L54-L59](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/scripts/trim-appimage-libjvm.sh#L54-L59)：

```bash
for appimage in "${appimages[@]}"; do
  work=$(mktemp -d)
  if ! trim_one "$appimage" "$work"; then
    rm -rf "$work"
    exit 1
  fi
  rm -rf "$work"
done
```

Bash 的 `errexit` 在"命令的返回值被测试"的上下文（这里是 `if !`）中会被**整个函数体**忽略——即便函数内部重新 `set -e` 也不生效。因此 `trim_one` 内的 `appimagetool` 非零退出、`mv` 失败都被静默跳过，脚本继续走到 `echo` 并返回 0。

这也是为什么 `Package (linux)` 显示绿色：失败只在日志文本里，没有体现为退出码。

### 3.5 次要因素：appimagetool 是移动靶

[ci.yml#L186-L192](file:///Users/wafer-li/FlutterProjects/ssb_contest_runner/.github/workflows/ci.yml#L186-L192) 每次从 `releases/download/continuous/` 拉取，无版本约束。本次拿到的 build 370 把目录权限问题从"警告"升级成了"致命错误"，行为变化不受本仓库控制。

注意：**仅固定工具版本不足以修复本问题**——脚本对"提取后目录权限"的错误假设仍然存在，任何启用该校验的版本都会失败；而 `--no-check-permissions` 这类新参数在旧版本上不存在，不能作为兼容方案。

---

## 4. 系统性缺口

1. **native 代码无 PR 门禁**：`package-*` 只覆盖 tag 与手工 dispatch，Windows/macOS/Linux 的 C++ 改动在合并前完全没编译过（本轮 C3668 即由此漏出）。
2. **打包失败重试策略不加区分**：确定性的编译错误仍重试 3 次，单次 Windows 打包成本 ×3。
3. **外部工具未固定版本**：appimagetool 走 `continuous`。
4. **脚本错误传播设计脆弱**：`if ! func` 削弱 `errexit`，且"成功"仅凭一行文本断言，没有产物存在性/体积校验。

---

## 5. 技术方案

> **决策（2026-11-15）：全部实施。** 本节 8 项（§5.1 一项、§5.2 四项、§5.3 三项）全部采纳，不保留、不降级、不延后；实施顺序与验收口径见 §7。

### 5.0 决策记录

| 编号 | 项 | 决策 | 验收依据 |
|---|---|---|---|
| A | Windows 析构声明改为 `virtual ~AudioOutputProbe();` | **实施** | `Package (windows)` 与两项 Windows 冒烟通过（§6-1） |
| B1 | 提取后执行 `chmod -R a+rX "$appdir"` | **实施** | appimagetool 不再报权限 ERROR；产物目录保持 0755（§6-3） |
| B2 | 取消 `if !` 对 `errexit` 的抑制，补 `trap` 清理 | **实施** | 注入失败时 trim 步骤自身报红（§6-5） |
| B3 | 产物存在性断言 + 体积必须变小断言 | **实施** | 打印 `after < before`，否则步骤失败（§6-2） |
| B4 | 固定 appimagetool 版本 | **实施** | CI 不再跟随 `continuous` 漂移；固定方式见 §7-3 |
| C1 | PR 阶段增加 Windows 编译门禁 | **实施** | PR 上出现编译作业，故意引入编译错误时变红（§6-6） |
| C2 | 编译错误短路打包重试 | **实施** | 日志出现 `error C####` 时不再重试三次 |
| C3 | 产物脚本统一"存在性 + 预期变化"自检模式 | **实施** | 本次 trim 脚本为首个适用对象，后续产物脚本沿用 |

### 5.1 Windows（一处声明）

```cpp
// windows/runner/audio_output_probe.h
-  ~AudioOutputProbe() override;
+  virtual ~AudioOutputProbe();
```

- 去掉 `override` 是必需的（COM 接口无析构可覆盖）；
- 同时补 `virtual`：类本身带虚函数而析构非虚，在 `/W4 /WX` 下可能触发 C4265，声明为虚析构可一并规避，且语义上更符合"多继承自接口"的类；
- `.cpp` 中的析构实现无需改动；
- 备选（**未采纳**）：只写 `~AudioOutputProbe();` 也能消除 C3668，但不满足"不动对象布局"以外的其它要求，且需承担 C4265 在 `/WX` 下成为新错误的风险；决策直接采用 `virtual` 一步到位。

### 5.2 Linux 重打包脚本

**（1）提取后规范目录权限**（版本无关，优于 `--no-check-permissions`）：

```bash
( cd "$work" && ./app.AppImage --appimage-extract > /dev/null )

local appdir="$work/squashfs-root"
chmod -R a+rX "$appdir"    # 目录补 0755；已可执行文件保持 exec，普通文件补读权限
```

`a+rX` 的 `X` 只对目录和已经可执行的文件生效，不会把普通数据文件误标为可执行，也不改变镜像内原本的语义。

**（2）让失败必现**——取消条件上下文对 `errexit` 的抑制：

```bash
for appimage in "${appimages[@]}"; do
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  trim_one "$appimage" "$work"     # 直接调用，函数体内 set -e 生效
  rm -rf "$work"
  trap - EXIT
done
```

**（3）加产物断言**，杜绝"0 字节变化"被当成成功：

```bash
[[ -s "$work/trimmed.AppImage" ]] ||
  { echo "::error::appimagetool produced no AppImage"; exit 1; }

after=$(stat -c %s "$appimage")
[[ "$after" -lt "$before" ]] ||
  { echo "::error::repack did not shrink the AppImage ($before -> $after)"; exit 1; }
```

**（4）固定 appimagetool 版本（决策：实施）**：改为使用固定版本的发布物（或按 sha256 锁定当前已验证的 build 370 / `git 11d54c9` 产物），避免下次 `continuous` 再次改变行为；升级版本时必须显式修改锁定值。固定版本后 `chmod -R a+rX` 仍应保留——权限规范化解决的是提取结果，固定版本解决的是工具行为漂移，两者不可互相替代。

### 5.3 防回归（决策：三项全部实施；本轮漏出正是缺此项所致）

1. **Windows 编译门禁**：在 PR 上增加 `flutter build windows --release`（或只编译 runner 目标），不出包、不跑 Inno Setup。成本远低于完整打包，可拦住 C3668 这类错误。
2. **重试短路**：日志里出现 `error C\d{4}:`（编译器诊断）时不重试，直接失败。只匹配编译器诊断：通用收尾行 `Build process failed.` 在偶发 native assets 失败时也会出现，纳入匹配会把重试关掉，故排除（2026-11-15 决定：保留偶发重试）。
3. **打包步骤自检**：所有"转换/裁剪产物"的脚本统一遵循"断言产物存在 + 断言预期变化"的模式，避免再次出现绿色步骤携带失败。

---

## 6. 验证清单

修复后重跑 `workflow_dispatch`（`platform=all`），逐项确认：

1. `Package (windows)`、`Smoke test (Windows)`、`Smoke test (Windows installer)` 全绿；
2. `Trim libjvm.so copied into the AppImage` 打印的 `before -> after` 中 `after < before`（预期减少约 34 MB）；
3. 下载新 `ssb-runner-linux` 产物复核：

   ```text
   7z l -slt <AppImage> | grep "Mode = d" | sort | uniq -c   → 全部 drwxr-xr-x
   AppImage 内不再存在 usr/lib/libjvm.so
   ```
4. `Smoke test (Debian 12)` 通过（libjvm 断言、glibc/GLIBCXX 下限、Xvfb 启动与关窗退出）；
5. 反向验证：临时让 `mv` 失败，确认 trim 步骤**自身**报红，而不是把问题推给冒烟测试；
6. PR 门禁自检：在一个临时 PR 中故意写坏 `windows/runner` 的一个 C++ 文件，确认新增的编译作业变红；恢复后变绿。

---

## 7. 决策后的实施顺序与遗留说明

实施顺序（每一步都能独立验证，前一步不绿不进入下一步）：

1. **A（Windows 析构声明）**——先落地，可立即用 `platform=windows` 单平台 dispatch 验证，解锁 Windows 冒烟与发布链路。
2. **B1–B3（重打包脚本：权限规范化、失败传播、产物断言）**——一起改，跑 `platform=linux` + Debian 冒烟，按 §6-2/3/5 验收。
3. **B4（固定 appimagetool）**——与 B1–B3 同一批落地：锁定已验证的 build 370（`git 11d54c9`）产物（版本号或 sha256），升级需显式改锁定值；`chmod -R a+rX` 保留。
4. **C2（重试短路）**——与 A 同批，避免下次确定性编译错误再消耗约 12 分钟。
5. **C1（PR Windows 编译门禁）**——单独一条改动，只编译不出包、不跑 Inno Setup；验收以 §6-6 的"故意写坏必红"为准。
6. **C3（脚本自检模式）**——B1–B3 落地后固化为通用约定，后续所有"转换/裁剪产物"脚本沿用。

遗留说明（不作为未决项）：

- `virtual ~AudioOutputProbe();` 已覆盖 C4265 风险，无需再单独验证"仅删 `override`"的路径。
- `--appimage-extract` 不还原目录权限属于 AppImage runtime 的行为，本仓库只能做脚本侧适配（B1）；该适配是确定的修复，不是临时规避。
- C1 会增加 PR 阶段的 Windows runner 占用，这是"全部实施"决策已接受的成本；若未来需缩减成本，可改为仅当 `windows/**` 有改动时触发（不影响本次决策与验收口径）。

