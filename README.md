# Langfuse EC2 セルフホスティング

LangfuseをEC2 1台構成でDocker Composeを使って運用するための設定です。

## 構成図

```
                    ┌─────────────────────┐
                    │   External Access   │
                    │    (Port 3000)      │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │    langfuse-web     │
                    │     (Next.js)       │
                    └──────────┬──────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
┌───────▼───────┐    ┌────────▼────────┐    ┌───────▼───────┐
│  PostgreSQL   │    │     Redis       │    │  ClickHouse   │
│   (5432)      │    │    (6379)       │    │ (8123/9000)   │
└───────────────┘    └─────────────────┘    └───────────────┘
                               │
                    ┌──────────▼──────────┐
                    │   langfuse-worker   │
                    │    (Express)        │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │       RustFS        │
                    │   (S3互換storage)   │
                    └─────────────────────┘
```

## EC2 推奨スペック

| 項目 | 最小構成 | 推奨構成 |
|------|---------|---------|
| インスタンスタイプ | t3.xlarge | t3.2xlarge / m5.xlarge |
| vCPU | 4コア | 8コア |
| メモリ | 16GB | 32GB |
| ストレージ | 100GB gp3 | 200GB+ gp3 |
| OS | Ubuntu 22.04 / 24.04 | 同左 |

> **注意**: ClickHouseがメモリを多く消費するため、16GB未満は非推奨です。

## クイックスタート

### 1. Docker + Compose V2 インストール（Ubuntu）

```bash
# snapでインストール（推奨）
sudo snap install docker

# dockerグループ設定
sudo groupadd docker
sudo usermod -aG docker $USER
sudo chown root:docker /var/run/docker.sock

# 再ログイン
exit
# → 再度SSH接続

# 確認
docker --version
docker compose version
```

### 2. リポジトリをクローン

```bash
git clone https://github.com/saitongs/langfuse-ec2.git
cd langfuse-ec2
```

### 3. 環境変数を生成

```bash
./setup.sh
```

セキュアなパスワードと秘密鍵が自動生成されます。

### 4. 起動

```bash
docker compose up -d

# ログ確認（2-3分で起動完了）
docker compose logs -f langfuse-web
```

### 5. アクセス

ブラウザで `http://<EC2のパブリックIP>:3000` にアクセス

## ファイル構成

```
langfuse-ec2/
├── compose.yaml                # メイン設定
├── compose.override.yaml       # ローカルMac用設定（自動適用）
├── .env.example                # 環境変数テンプレート
├── .env                        # 実際の環境変数（git管理外）
├── setup.sh                    # セットアップスクリプト
└── README.md                   # このファイル
```

## EC2 セキュリティグループ設定

| ポート | 用途 | ソース |
|-------|------|-------|
| 22 | SSH | 自分のIP |
| 3000 | Langfuse UI | 利用者のIP範囲 |

他のポート（5432, 6379, 8123, 9000）は `127.0.0.1` にバインドされているため外部公開不要です。

## ローカル（Mac）での起動

`compose.override.yaml` が自動で適用されます。

```bash
./setup.sh
docker compose up -d
```

アクセス: http://localhost:3000

### override.yml での調整内容

| 設定 | ベース（EC2用） | override（Mac用） |
|------|----------------|-------------------|
| PostgreSQLポート | 5432 | 5433（競合回避） |
| メモリ制限 | なし | 各コンテナに設定 |
| ClickHouse ulimits | 262144 | 無効（Mac互換） |

## 運用コマンド

```bash
# 起動
docker compose up -d

# 停止
docker compose down

# ログ確認
docker compose logs -f langfuse-web
docker compose logs -f langfuse-worker

# アップグレード
docker compose pull
docker compose up -d

# 完全リセット（データ削除）
docker compose down -v
```

## 公式との差分

| 項目 | 公式 | 本リポジトリ | 変更理由 |
|------|------|-------------|----------|
| 環境変数管理 | ハードコード（CHANGEME） | `.env`ファイルで外部化 | セキュリティ向上・管理容易化 |
| S3互換ストレージ | MinIO | RustFS | MinIOのDockerイメージ更新停止・ライセンス問題 |
| S3 APIポート | 9090 | 9010 | ClickHouseの9000と競合回避 |
| S3 Consoleポート | 9091 | 9011 | 連番で統一 |
| PostgreSQLユーザー | postgres | langfuse | 専用ユーザーで権限分離 |
| ボリューム名 | `langfuse_`プレフィックス | プレフィックスなし | シンプル化 |
| バケット初期化 | なし | `rustfs-init`で自動作成 | 手動作業不要 |
| テレメトリ | 有効 | 無効 | プライバシー配慮 |
| Redis永続化 | なし | `appendonly yes` | データ保護 |
| イメージ | 標準 | alpine版 | イメージサイズ削減 |
| CLICKHOUSE_CLUSTER_ENABLED | 記載なし | `false`明示 | シングルノードでのエラー回避 |

### 変更理由の詳細

#### 環境変数の外部化
公式は `CHANGEME` をそのまま置き換える方式ですが、`.env` ファイルに分離することで：
- 機密情報をgit管理から除外
- 環境ごとの設定切り替えが容易
- `setup.sh` による自動生成が可能

#### CLICKHOUSE_CLUSTER_ENABLED=false
公式では暗黙的に設定されていますが、明示しないと以下のエラーが発生する場合があります：
```
error: There is no Zookeeper configuration in server config
```
シングルノード構成では Zookeeper/クラスター機能が不要なため明示的に無効化。

#### RustFS（MinIOの代替）
MinIOは2025年にDockerイメージの更新を停止し、既知のCVEが放置された状態になりました。
また、コミュニティ版の機能制限も進んでいます。

RustFSを採用した理由：
- Apache 2.0ライセンス（AGPLの制約なし）
- 100% S3互換
- 軽量で高速（MinIOより2.3倍高速との報告あり）
- 積極的にメンテナンスされている

#### rustfs-init サービス追加
公式では手動でバケット作成が必要ですが、初回起動時にAWS CLIで自動作成することで：
- 手順の簡略化
- 起動直後からすぐ使える状態に

#### alpine イメージ採用
PostgreSQL、Redis を alpine 版に変更：
- イメージサイズが約1/3に削減
- 機能は同等

## トラブルシューティング

### ClickHouse: get_mempolicy: Operation not permitted

```
langfuse-clickhouse | get_mempolicy: Operation not permitted
```

**問題なし**。DockerコンテナではNUMA最適化の権限がないための警告で、動作に影響しません。

### RustFS: バケット作成失敗

バケット作成に失敗する場合は、環境変数が正しく渡されていない可能性があります：
```bash
docker compose logs rustfs-init
```

RustFSが起動するまで時間がかかる場合があるため、手動で再実行：
```bash
docker compose rm -sf rustfs-init
docker compose up -d rustfs-init
```

### メモリ不足

ClickHouse がメモリを多く消費します。16GB未満の環境では：
```bash
# スワップを追加（応急処置）
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

## 参考リンク

- [Langfuse公式ドキュメント](https://langfuse.com/docs)
- [Langfuse セルフホストガイド](https://langfuse.com/self-hosting)
- [Langfuse GitHub](https://github.com/langfuse/langfuse)
