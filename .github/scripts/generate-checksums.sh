#!/usr/bin/env bash
# 为 release 目录下的安装包生成 SHA-256 指纹。
#
# 一次运行产出两份内容，二者必须来自同一次计算，否则正文与清单会漂移：
#   1. <release>/SHA256SUMS.txt —— 随包发布的资产，格式兼容 `sha256sum -c`
#   2. <notes>                  —— Release 正文稿，由 action-gh-release 的
#                                  body_path 前置到自动生成的变更列表之前
#
# 用法：generate-checksums.sh [release 目录] [正文稿路径]
set -euo pipefail

release_dir=${1:-release}
notes_path=${2:-notes/checksums.md}

[[ -d "$release_dir" ]] || { echo "::error::$release_dir 不存在" >&2; exit 1; }

manifest="$release_dir/SHA256SUMS.txt"
manifest_name=$(basename "$manifest")

# 本地（macOS）用 shasum，CI（Linux）用 sha256sum；两者输出格式一致。
if command -v sha256sum >/dev/null 2>&1; then
  hash_of() { sha256sum -- "$1" | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  hash_of() { shasum -a 256 -- "$1" | awk '{print $1}'; }
else
  echo "::error::既没有 sha256sum 也没有 shasum" >&2
  exit 1
fi

# 上一轮运行残留的清单必须清掉：它既不能被计入条目数，也不能参与自身的校验。
rm -f "$manifest"

files=()
while IFS= read -r name; do
  files+=("$name")
done < <(
  cd "$release_dir"
  for f in *; do
    if [[ -f "$f" && "$f" != "$manifest_name" ]]; then
      printf '%s\n' "$f"
    fi
  done | LC_ALL=C sort
)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "::error::$release_dir 下没有任何资产" >&2
  exit 1
fi

for name in "${files[@]}"; do
  printf '%s  %s\n' "$(hash_of "$release_dir/$name")" "$name" >> "$manifest"
done

# 回验一：清单条目数与目录内资产数一致（脚本自身已排除清单文件）。
lines=$(wc -l < "$manifest" | tr -d ' ')
[[ "$lines" -eq "${#files[@]}" ]] || {
  echo "::error::清单条目数 $lines 与资产数 ${#files[@]} 不一致" >&2
  exit 1
}

# 回验二：真正按清单重新计算一遍，防止写入过程中出现空哈希或串行。
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$release_dir" && sha256sum -c "$manifest_name" >/dev/null)
else
  (cd "$release_dir" && shasum -a 256 -c "$manifest_name" >/dev/null)
fi

# 正文稿放在发布目录之外，避免被 action-gh-release 当作资产上传。
mkdir -p "$(dirname "$notes_path")"
{
  cat <<'EOF'
# Installer File Fingerprints (SHA-256)

Each installer package comes with a SHA-256 fingerprint. After downloading, please verify it to confirm that the file is complete and has not been tampered with. The fingerprint only proves that the downloaded bytes match those at release time; it is not equivalent to a code signature.

- **Linux** — In the download directory, run `sha256sum -c SHA256SUMS.txt`
- **macOS** — In the download directory, run `shasum -a 256 -c SHA256SUMS.txt`
- **Windows** — Run `Get-FileHash -Algorithm SHA256 <filename>` (or `certutil -hashfile <filename> SHA256`), and compare the result with the corresponding value below

<details>
<summary>Expand to view all SHA-256 fingerprints</summary>

```
EOF
  cat "$manifest"
  cat <<'EOF'
```

</details>
EOF
} > "$notes_path"

# 回验三：正文稿中的每一行都必须与清单完全一致。
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  grep -qF -- "$line" "$notes_path" || {
    echo "::error::正文稿缺少清单条目：$line" >&2
    exit 1
  }
done < "$manifest"

echo "已生成 $manifest（$lines 条）与 $notes_path"
