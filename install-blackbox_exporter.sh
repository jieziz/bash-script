#!/bin/bash
set -e
COLOR="echo -e \\E[1;32m"
COLOR1="echo -e \\E[1;31m"
END="\\E[0m"

if [[ $EUID -ne 0 ]]; then
  echo "请切换到 root 用户后再运行脚本"
  exit 1
fi

if [[ "$(uname -m)" == "x86_64" ]]; then
  type=amd64
elif [[ "$(uname -m)" == "aarch64" ]]; then
  type=arm64
else
  echo "$(uname -m) 架构不支持"
  exit 1
fi

latest_version=$(curl -m 10 -sL "https://api.github.com/repos/prometheus/blackbox_exporter/releases/latest" | awk -F'"' '/tag_name/{gsub(/v/, "", $4); print $4}')

install() {
  if ss -tuln | grep -q ":9115"; then
    echo "端口 9115 已被占用"
    exit 1
  fi

  wget https://github.com/prometheus/blackbox_exporter/releases/download/v${latest_version}/blackbox_exporter-${latest_version}.linux-${type}.tar.gz
  tar zxvf blackbox_exporter-${latest_version}.linux-${type}.tar.gz
  mkdir -p /etc/blackbox_exporter
  mv blackbox_exporter-${latest_version}.linux-${type}/blackbox_exporter /usr/local/bin/blackbox_exporter
  chmod +x /usr/local/bin/blackbox_exporter

  # 将配置写入 blackbox.yml 文件
  cat > /etc/blackbox_exporter/blackbox.yml <<EOF
modules:
  http_2xx:
    prober: http
    http:
      valid_status_codes: [200,204]
      no_follow_redirects: false
      preferred_ip_protocol: ip4
      ip_protocol_fallback: false

  httpNoRedirect4ssl:
    prober: http
    http:
      valid_status_codes: [200,204,301,302,303]
      no_follow_redirects: true
      preferred_ip_protocol: ip4
      ip_protocol_fallback: false

  http200igssl:
    prober: http
    http:
      valid_status_codes:
      - 200
      tls_config:
        insecure_skip_verify: true

  http_4xx:
    prober: http
    http:
      valid_status_codes: [401,403,404]
      preferred_ip_protocol: ip4
      ip_protocol_fallback: false

  http_5xx:
    prober: http
    http:
      valid_status_codes: [500,502]
      preferred_ip_protocol: ip4
      ip_protocol_fallback: false

  http_post_2xx:
    prober: http
    http:
      method: POST

  icmp:
    prober: icmp

  tcp_connect:
    prober: tcp

  ssh_banner:
    prober: tcp
    tcp:
      query_response:
      - expect: "^SSH-2.0-"
      - send: "SSH-2.0-blackbox-ssh-check"
EOF

  rm -rf blackbox_exporter-${latest_version}.linux-${type}
  rm -rf blackbox_exporter-${latest_version}.linux-${type}.tar.gz

  cat > /etc/systemd/system/blackbox-exporter.service <<EOF
[Unit]
Description=This is prometheus blackbox exporter

[Service]
Type=simple
ExecStart=/usr/local/bin/blackbox_exporter --config.file="/etc/blackbox_exporter/blackbox.yml" --web.listen-address=":9115"
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl start blackbox-exporter.service
  systemctl enable blackbox-exporter.service
}

uninstall() {
  systemctl stop blackbox-exporter.service
  systemctl disable blackbox-exporter.service
  rm -rf /etc/systemd/system/blackbox-exporter.service
  rm -rf /etc/blackbox_exporter
  rm -rf /usr/local/bin/blackbox_exporter
  echo "blackbox-exporter 卸载成功"
}

update() {
  rm -rf /usr/local/bin/blackbox_exporter
  rm -rf /etc/blackbox_exporter/blackbox_exporter
  wget https://github.com/prometheus/blackbox_exporter/releases/download/v${latest_version}/blackbox_exporter-${latest_version}.linux-${type}.tar.gz
  tar zxvf blackbox_exporter-${latest_version}.linux-${type}.tar.gz
  mv blackbox_exporter-${latest_version}.linux-${type}/blackbox_exporter /usr/local/bin/blackbox_exporter
  chmod +x /usr/local/bin/blackbox_exporter

  # 更新 blackbox.yml 文件
  cat > /etc/blackbox_exporter/blackbox.yml <<EOF
modules:
  http_2xx:
    prober: http
    http:
      valid_status_codes: [200,204]
      no_follow_redirects: false
      preferred_ip_protocol: ip4
      ip_protocol_fallback: false

  httpNoRedirect4ssl:
    prober: http
    http:
      valid_status_codes: [200,204,301,302,303]
      no_follow_redirects: true
      preferred_ip_protocol: ip4
      ip_protocol_fallback: false

  http200igssl:
    prober: http
    http:
      valid_status_codes:
      - 200
      tls_config:
        insecure_skip_verify: true

  http_4xx:
    prober: http
    http:
      valid_status_codes: [401,403,404]
      preferred_ip_protocol: ip4
      ip_protocol_fallback: false

  http_5xx:
    prober: http
    http:
      valid_status_codes: [500,502]
      preferred_ip_protocol: ip4
      ip_protocol_fallback: false

  http_post_2xx:
    prober: http
    http:
      method: POST

  icmp:
    prober: icmp

  tcp_connect:
    prober: tcp

  ssh_banner:
    prober: tcp
    tcp:
      query_response:
      - expect: "^SSH-2.0-"
      - send: "SSH-2.0-blackbox-ssh-check"
EOF

  rm -rf blackbox_exporter-${latest_version}.linux-${type}
  rm -rf blackbox_exporter-${latest_version}.linux-${type}.tar.gz

  systemctl daemon-reload
  systemctl restart blackbox-exporter.service
  echo "blackbox-exporter 更新成功"
}

if [[ $1 == "uninstall" ]]; then
  uninstall
  exit 0
fi

if [[ $1 == "update" ]]; then
  update
  exit 0
fi

install

blackbox_exporter_port=$(ss -ntlp | grep -o 9115)
if [ "$blackbox_exporter_port" == "9115" ]; then
  ${COLOR}blackbox-exporter 安装成功${END}
else
  ${COLOR1}blackbox-exporter 安装失败${END}
fi
