#!/bin/bash
# Langfuse EC2 セットアップスクリプト
# このスクリプトは .env ファイルを自動生成します

set -e

ENV_FILE=".env"

if [ -f "$ENV_FILE" ]; then
    echo "警告: $ENV_FILE は既に存在します"
    read -p "上書きしますか？ (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "中断しました"
        exit 1
    fi
fi

echo "セキュアなパスワードと秘密鍵を生成しています..."

# パスワード生成関数
generate_password() {
    openssl rand -base64 24 | tr -d '/+=' | head -c 32
}

# 秘密鍵生成
POSTGRES_PASSWORD=$(generate_password)
CLICKHOUSE_PASSWORD=$(generate_password)
REDIS_PASSWORD=$(generate_password)
S3_ROOT_PASSWORD=$(generate_password)
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
