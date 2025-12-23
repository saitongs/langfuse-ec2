#!/bin/bash
# Langfuse EC2 セットアップスクリプト
# このスクリプトは .env ファイルを自動生成します

set -e

ENV_FILE=".env"

# パスワード生成関数
generate_password() {
    openssl rand -base64 24 | tr -d '/+=' | head -c 32
}

# 既存の.envから値を取得する関数
get_existing_value() {
    local key=$1
    if [ -f "$ENV_FILE" ]; then
        grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | head -1
    fi
}

# 既存の.envがある場合の処理
if [ -f "$ENV_FILE" ]; then
    echo "既存の $ENV_FILE を検出しました"
    echo ""
    echo "選択してください:"
    echo "  1) 完全に新規作成（全パスワード再生成、要ボリューム削除）"
    echo "  2) データベースパスワードを引き継いで更新（推奨）"
    echo "  3) 中断"
    echo ""
    read -p "選択 [1-3]: " choice

    case $choice in
        1)
            echo ""
            echo "⚠️  警告: 全パスワードが再生成されます"
            echo "   既存のボリュームを削除してください:"
            echo "   docker compose down -v"
            echo ""
            read -p "続行しますか？ (y/N): " confirm
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                echo "中断しました"
                exit 1
            fi
            # 新規生成
            POSTGRES_PASSWORD=$(generate_password)
            CLICKHOUSE_PASSWORD=$(generate_password)
            REDIS_PASSWORD=$(generate_password)
            S3_ROOT_PASSWORD=$(generate_password)
            ;;
        2)
            echo "既存のデータベースパスワードを引き継ぎます..."
            # 既存値を取得、なければ新規生成
            POSTGRES_PASSWORD=$(get_existing_value "POSTGRES_PASSWORD")
            CLICKHOUSE_PASSWORD=$(get_existing_value "CLICKHOUSE_PASSWORD")
            REDIS_PASSWORD=$(get_existing_value "REDIS_PASSWORD")
            S3_ROOT_PASSWORD=$(get_existing_value "S3_ROOT_PASSWORD")

            # 空の場合は新規生成
            [ -z "$POSTGRES_PASSWORD" ] && POSTGRES_PASSWORD=$(generate_password)
            [ -z "$CLICKHOUSE_PASSWORD" ] && CLICKHOUSE_PASSWORD=$(generate_password)
            [ -z "$REDIS_PASSWORD" ] && REDIS_PASSWORD=$(generate_password)
            [ -z "$S3_ROOT_PASSWORD" ] && S3_ROOT_PASSWORD=$(generate_password)
            ;;
        *)
            echo "中断しました"
            exit 1
            ;;
    esac
else
    echo "セキュアなパスワードと秘密鍵を生成しています..."
    POSTGRES_PASSWORD=$(generate_password)
    CLICKHOUSE_PASSWORD=$(generate_password)
    REDIS_PASSWORD=$(generate_password)
    S3_ROOT_PASSWORD=$(generate_password)
fi

# 認証キーは常に新規生成可能（ボリュームに依存しない）
NEXTAUTH_SECRET=$(openssl rand -base64 32)
SALT=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -hex 32)

# EC2のパブリックIPを取得（EC2上で実行時のみ）
PUBLIC_IP=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")

cat > "$ENV_FILE" << EOF
# ===================
# Langfuse EC2 環境変数設定
# 自動生成: $(date)
# ===================

# ===================
# PostgreSQL
# ===================
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# ===================
# ClickHouse
# ===================
CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}

# ===================
# Redis
# ===================
REDIS_PASSWORD=${REDIS_PASSWORD}

# ===================
# RustFS (S3互換ストレージ)
# ===================
S3_ROOT_USER=langfuse
S3_ROOT_PASSWORD=${S3_ROOT_PASSWORD}

# ===================
# Langfuse Auth
# ===================
# 外部からアクセスするURL（EC2のパブリックIP/ドメインに変更してください）
NEXTAUTH_URL=http://${PUBLIC_IP}:3000

NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
SALT=${SALT}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
EOF

chmod 600 "$ENV_FILE"

echo ""
echo "✓ $ENV_FILE を生成しました"
echo ""
echo "次のステップ:"
echo "  1. NEXTAUTH_URL を確認・修正してください"
echo "     現在の値: http://${PUBLIC_IP}:3000"
echo ""
echo "  2. Langfuseを起動:"
echo "     docker compose up -d"
echo ""
echo "  3. ブラウザでアクセス:"
echo "     http://${PUBLIC_IP}:3000"
echo ""
