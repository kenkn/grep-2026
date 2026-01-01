# mygrep Benchmark Suite

このディレクトリには、mygrep の性能ベンチマーク基盤が含まれています。
[hyperfine](https://github.com/sharkdp/hyperfine) を使用して mygrep、ripgrep、GNU grep を比較します。

## セットアップ

### 必要なツール

```bash
# hyperfine (ベンチマークツール) - 必須
brew install hyperfine       # macOS
apt install hyperfine        # Debian/Ubuntu

# ripgrep (比較対象) - 推奨
brew install ripgrep         # macOS
apt install ripgrep          # Debian/Ubuntu

# GNU grep (比較対象) - macOS では別途インストールが必要
brew install grep            # macOS (ggrep としてインストールされる)
# Linux では標準で /usr/bin/grep が GNU grep
```

### mygrep のビルド

```bash
# リポジトリルートで実行
go build -o bin/mygrep ./cmd/grep
```

### コーパス (テストデータ) の生成

```bash
# すべてのコーパスを生成
./bench/gen_corpus.sh --all

# 個別に生成することも可能
./bench/gen_corpus.sh --code    # コードツリー (タイプA)
./bench/gen_corpus.sh --log     # ログファイル (タイプB)
./bench/gen_corpus.sh --binary  # バイナリファイル (タイプC)

# クリーンアップ
./bench/gen_corpus.sh --clean
```

## 使い方

### 基本的な実行

```bash
# すべてのベンチマークを warm モードで実行
./bench/run.sh

# 特定のコーパスのみ
./bench/run.sh --corpus code    # コードツリーのみ
./bench/run.sh --corpus log     # ログファイルのみ

# 検索パターンを指定
./bench/run.sh --pattern common    # "TODO" を検索 (デフォルト)
./bench/run.sh --pattern frequent  # "the" を検索 (高頻度)
./bench/run.sh --pattern rare      # まれなパターンを検索
./bench/run.sh --pattern "CUSTOM"  # カスタム文字列を検索
```

### Cold モードでの実行

```bash
# cold モード: 各実行前にページキャッシュをクリア
./bench/run.sh --cold

# 注意: cold モードには sudo 権限が必要
# macOS: sudo purge
# Linux: sync && echo 3 | sudo tee /proc/sys/vm/drop_caches
```

### レポートの生成

```bash
# テキストレポートを生成
python3 ./bench/report.py

# 最新の結果のみを使用
python3 ./bench/report.py --latest

# CSV 形式で出力
python3 ./bench/report.py --csv > results.csv

# JSON 形式で出力
python3 ./bench/report.py --json > results.json
```

## Warm vs Cold ベンチマーク

### Warm (デフォルト)

- **OS ページキャッシュが有効な状態** で測定
- 2回目以降のファイルアクセスを模した状況
- CPU バウンドな性能特性を測定しやすい
- 再現性が高く、ノイズが少ない
- **推奨**: 日常的な性能回帰検知に使用

### Cold

- **各実行前にページキャッシュをクリア**
- 初回ファイルアクセスを模した状況
- I/O バウンドな性能特性を測定
- より実際の体感速度に近い
- ノイズが多く、再現性が低い
- **用途**: I/O 最適化の効果測定、リアルワールドシナリオの評価

## コーパスタイプ

### タイプ A: コードツリー (code_tree)

- 多数の小〜中サイズファイル (デフォルト: 1000 ファイル)
- Go ソースコード風のテキスト
- ディレクトリ階層を持つ
- **測定対象**: ファイル走査オーバーヘッド、並列処理効率

### タイプ B: ログファイル (log)

- 単一の大きなファイル (デフォルト: 100 万行)
- JSON 形式のログエントリ
- 様々なマッチ頻度のパターンを含む
- **測定対象**: 大ファイルのストリーミング処理性能

### タイプ C: バイナリファイル (binary)

- バイナリデータ + 埋め込みテキスト
- デフォルト: 50 MB
- **測定対象**: バイナリ検出/スキップの挙動と性能

## 注意点

### I/O 支配について

ベンチマーク結果は以下の要因に大きく影響されます:

1. **ストレージ種別**: SSD vs HDD で大幅に異なる
2. **ファイルシステム**: APFS, ext4, ZFS など
3. **キャッシュ状態**: warm/cold で数倍〜数十倍の差
4. **他プロセスの I/O**: バックグラウンド処理の影響

### ツール間の公平性

各ツールには以下のオプションを使用して条件を揃えています:

| ツール | オプション | 意味 |
|--------|-----------|------|
| mygrep | (なし) | 固定文字列検索がデフォルト |
| ripgrep | `--fixed-strings` | 正規表現を無効化 |
| GNU grep | `--fixed-strings` | 正規表現を無効化 |

出力は `/dev/null` にリダイレクトして、出力処理の差異を排除しています。

### バイナリファイルの扱い

- **ripgrep**: デフォルトでバイナリファイルをスキップ
- **GNU grep**: バイナリ検出時に "Binary file matches" と出力
- **mygrep**: 現在の実装ではバイナリ判定なし

バイナリベンチマークの結果解釈には注意が必要です。

### mygrep の制限事項

現在の mygrep 実装:
- 単一ファイルのみ対応 (`mygrep <pattern> <file>`)
- 再帰検索オプション (`-r`) なし

ベンチマークでは `find ... -exec mygrep` で回避していますが、
これはプロセス起動オーバーヘッドが含まれるため不利になります。

## ディレクトリ構成

```
bench/
├── README.md         # このファイル
├── config.sh         # 設定変数
├── gen_corpus.sh     # コーパス生成スクリプト
├── run.sh            # メインベンチマークスクリプト
├── report.py         # レポート生成スクリプト
├── corpus/           # 生成されたテストデータ
│   ├── code_tree/    # タイプ A
│   ├── log/          # タイプ B
│   └── binary/       # タイプ C
└── results/          # ベンチマーク結果 (JSON)
```

## 設定のカスタマイズ

`bench/config.sh` を編集して各種設定を変更できます:

```bash
# mygrep バイナリの場所
MYGREP_BIN="./bin/mygrep"

# コーパスサイズ
CODE_TREE_NUM_FILES=1000    # コードツリーのファイル数
LOG_FILE_NUM_LINES=1000000  # ログファイルの行数

# hyperfine 設定
WARMUP_RUNS=3   # ウォームアップ回数
BENCH_RUNS=10   # 計測回数
```

## CI/CD での使用

GitHub Actions などでの使用例:

```yaml
- name: Build mygrep
  run: go build -o bin/mygrep ./cmd/grep

- name: Setup benchmark
  run: |
    brew install hyperfine ripgrep grep
    ./bench/gen_corpus.sh --code --log

- name: Run benchmark
  run: ./bench/run.sh --corpus code --pattern common

- name: Generate report
  run: python3 ./bench/report.py --json > bench-results.json

- name: Upload results
  uses: actions/upload-artifact@v4
  with:
    name: benchmark-results
    path: bench/results/*.json
```

## トラブルシューティング

### "mygrep binary not found"

```bash
# mygrep をビルド
go build -o bin/mygrep ./cmd/grep

# または環境変数で指定
MYGREP_BIN=/path/to/mygrep ./bench/run.sh
```

### "GNU grep not found" (macOS)

```bash
# Homebrew で GNU grep をインストール
brew install grep

# ggrep として利用可能になる
# config.sh で GREP_BIN="ggrep" が設定済み
```

### "Failed to clear cache"

cold モードでキャッシュクリアに失敗する場合:

```bash
# macOS: 手動で purge を実行
sudo purge

# Linux: 手動でキャッシュクリア
sync && echo 3 | sudo tee /proc/sys/vm/drop_caches

# または warm モードのみ使用
./bench/run.sh --warm
```

### 結果のばらつきが大きい

1. 他のプロセスを終了させる
2. `--runs` を増やす: `./bench/run.sh --runs 20`
3. `--warmup` を増やす: `./bench/run.sh --warmup 5`
4. 電源に接続 (ノートPC の場合)
