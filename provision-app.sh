
#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================
# Sparta Tic Tac Toe - AWS EC2 Deployment
# ==========================================

APP_NAME="sparta-app-v2"
ZIP_FILE="/home/ubuntu/nodejs20-sparta-tictactoe-v1.zip"
DEPLOY_DIR="/home/ubuntu/sparta-deployment"

echo "Starting deployment: $APP_NAME"

# 1. Check ZIP file exists
if [[ ! -f "$ZIP_FILE" ]]; then
    echo "ERROR: ZIP file not found at $ZIP_FILE"
    exit 1
fi

# 2. Install system dependencies
sudo apt-get update -y
sudo apt-get install -y \
    curl ca-certificates unzip rsync

# 3. Install Node.js 20 if missing
if ! command -v node >/dev/null 2>&1; then
    curl -fsSL \
      https://deb.nodesource.com/setup_20.x \
      | sudo -E bash -
    sudo apt-get install -y nodejs
fi

# Verify Node.js version
NODE_MAJOR=$(node -p \
    "process.versions.node.split('.')[0]")

if [[ "$NODE_MAJOR" != "20" ]]; then
    echo "ERROR: Node.js 20 is required"
    exit 1
fi

# 4. Install PM2 if missing
if ! command -v pm2 >/dev/null 2>&1; then
    sudo npm install -g pm2
fi

# 5. Create deployment directory
mkdir -p "$DEPLOY_DIR/releases"

# 6. Create new release directory
RELEASE_DIR=$(mktemp -d \
    "$DEPLOY_DIR/releases/release-XXXXXX")

# 7. Extract application ZIP
unzip -q "$ZIP_FILE" -d "$RELEASE_DIR"

APP_SOURCE="$RELEASE_DIR/app"

if [[ ! -f "$APP_SOURCE/package.json" ]]; then
    echo "ERROR: package.json not found"
    exit 1
fi

# 8. Install application dependencies
cd "$APP_SOURCE"

# Prevent postinstall from resetting scoreboard
npm ci --ignore-scripts

# 9. Verify entry point
if [[ ! -f "index.js" ]]; then
    echo "ERROR: index.js not found"
    exit 1
fi

# 10. Update current application symlink
ln -sfn "$APP_SOURCE" "$DEPLOY_DIR/current.new"
mv -Tf "$DEPLOY_DIR/current.new" \
    "$DEPLOY_DIR/current"

# 11. Start or restart application with PM2
if pm2 describe "$APP_NAME" >/dev/null 2>&1; then
    echo "Stopping existing PM2 process..."
    pm2 delete "$APP_NAME"
fi

echo "Starting application with PM2..."

pm2 start "$DEPLOY_DIR/current/index.js" \
    --name "$APP_NAME" \
    --cwd "$DEPLOY_DIR/current"

# 12. Save PM2 configuration
pm2 save

echo "=================================="
echo "Deployment completed successfully!"
echo "=================================="

pm2 status

