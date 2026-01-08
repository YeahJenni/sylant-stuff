#!/usr/bin/env bash
set -e

echo "v1.3-public-ip"

PUBLIC_IP=$(
  curl -s https://api.ipify.org || \
  curl -s https://ifconfig.me || \
  curl -s https://checkip.amazonaws.com
)

if [ -z "$PUBLIC_IP" ]; then
  echo "ould not detect public IP address."
  exit 1
fi

sudo mkdir -p /etc/prometheus
sudo mkdir -p /var/lib/prometheus

cd /tmp

PROM_VERSION=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep tag_name | cut -d '"' -f4)
PROM_VERSION_CLEAN="${PROM_VERSION#v}"

echo "Downloading Prometheus $PROM_VERSION"

curl -sSL -O "https://github.com/prometheus/prometheus/releases/download/${PROM_VERSION}/prometheus-${PROM_VERSION_CLEAN}.linux-amd64.tar.gz"

tar -xzf "prometheus-${PROM_VERSION_CLEAN}.linux-amd64.tar.gz"

PROM_DIR=$(find . -maxdepth 1 -type d -name "prometheus-*.linux-amd64" | head -n1)

if [[ ! -d "$PROM_DIR" ]]; then
  echo "ERROR: Extracted Prometheus directory not found."
  exit 1
fi

cd "$PROM_DIR"

sudo cp prometheus promtool /usr/local/bin/

sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ['$PUBLIC_IP:9090']

  - job_name: node_exporter
    static_configs:
      - targets: ['$PUBLIC_IP:9100']
EOF

echo "Prometheus config installed"

sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/prometheus \\
  --config.file=/etc/prometheus/prometheus.yml \\
  --storage.tsdb.path=/var/lib/prometheus \\
  --web.listen-address=$PUBLIC_IP:9090
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cd /tmp

NODE_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep tag_name | cut -d '"' -f4)
NODE_VERSION_CLEAN="${NODE_VERSION#v}"

echo "Downloading node_exporter $NODE_VERSION"

curl -sSL -O "https://github.com/prometheus/node_exporter/releases/download/${NODE_VERSION}/node_exporter-${NODE_VERSION_CLEAN}.linux-amd64.tar.gz"

tar -xzf "node_exporter-${NODE_VERSION_CLEAN}.linux-amd64.tar.gz"

NODE_DIR=$(find . -maxdepth 1 -type d -name "node_exporter-*.linux-amd64" | head -n1)

if [[ ! -d "$NODE_DIR" ]]; then
  echo  "Extracted node_exporter directory not found."
  exit 1
fi

cd "$NODE_DIR"

sudo cp node_exporter /usr/local/bin/

sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/node_exporter \\
  --web.listen-address=$PUBLIC_IP:9100
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now prometheus
sudo systemctl enable --now node_exporter

echo ""
echo "──────────────────────────────────────────────"
echo "Prometheus UI: http://$PUBLIC_IP:9090"
echo "Node Exporter: http://$PUBLIC_IP:9100/metrics"
echo "──────────────────────────────────────────────"
echo "Done!"
