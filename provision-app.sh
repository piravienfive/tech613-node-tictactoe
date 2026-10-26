
#!/usr/bin/env bash
set -Eeuo pipefail

# Sparta Tic Tac Toe deployment configuration
APP_NAME="sparta-app-v2"
REPO_URL="https://github.com/piravienfive/tech613-node-tictactoe.git"
DEPLOY_DIR="/home/ubuntu/sparta-deployment"
APP_PORT=3000

echo "Starting deployment of $APP_NAME"

# 1. Install system dependencies
sudo apt-get update -y
sudo apt-get install -y \
  git curl ca-certificates nginx

# 2. Install Node.js 20 if missing
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x \
    | sudo -E bash -
  sudo apt-get install -y nodejs
fi

NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]")

if [[ "$NODE_MAJOR" != "20" ]]; then
  echo "ERROR: Node.js 20 required"
  exit 1
fi

# 3. Install PM2 if missing
if ! command -v pm2 >/dev/null 2>&1; then
  sudo npm install -g pm2
fi

# 4. Clone or update application source
mkdir -p "$DEPLOY_DIR"

if [[ ! -d "$DEPLOY_DIR/repository/.git" ]]; then
  git clone "$REPO_URL" "$DEPLOY_DIR/repository"
else
  git -C "$DEPLOY_DIR/repository" fetch origin
  BRANCH=$(git -C "$DEPLOY_DIR/repository" \
    symbolic-ref --quiet --short refs/remotes/origin/HEAD)
  BRANCH=${BRANCH#origin/}
  git -C "$DEPLOY_DIR/repository" reset --hard "origin/$BRANCH"
fi

# 5. Locate Node.js application
if [[ -f "$DEPLOY_DIR/repository/app/package.json" ]]; then
  APP_DIR="$DEPLOY_DIR/repository/app"
elif [[ -f "$DEPLOY_DIR/repository/package.json" ]]; then
  APP_DIR="$DEPLOY_DIR/repository"
else
  echo "ERROR: package.json not found"
  exit 1
fi

# 6. Install dependencies without running seeds
cd "$APP_DIR"
npm ci --ignore-scripts

# 7. Start or restart app using PM2
if pm2 describe "$APP_NAME" >/dev/null 2>&1; then
  pm2 delete "$APP_NAME"
fi

pm2 start "$APP_DIR/index.js" \
  --name "$APP_NAME" \
  --cwd "$APP_DIR"

pm2 save

# 8. Configure Nginx reverse proxy
sudo tee /etc/nginx/sites-available/sparta-app \
  >/dev/null <<EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# 9. Enable Nginx configuration
sudo ln -sfn \
  /etc/nginx/sites-available/sparta-app \
  /etc/nginx/sites-enabled/sparta-app

# Disable default site to avoid conflicts
sudo rm -f /etc/nginx/sites-enabled/default

# 10. Validate and reload Nginx
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl reload nginx

echo "Deployment completed successfully!"
pm2 status
