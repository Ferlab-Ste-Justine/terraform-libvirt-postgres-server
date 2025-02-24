#cloud-config
%{ if admin_user_password != "" ~}
chpasswd:
  list: |
     ${ssh_admin_user}:${admin_user_password}
  expire: False
%{ endif ~}
preserve_hostname: false
hostname: ${node_name}
users:
  - default
  - name: node-exporter
    system: true
    lock_passwd: true
  - name: ${ssh_admin_user}
    ssh_authorized_keys:
      - "${ssh_admin_public_key}"
write_files:
  #Chrony config
%{ if chrony.enabled ~}
  - path: /opt/chrony.conf
    owner: root:root
    permissions: "0444"
    content: |
%{ for server in chrony.servers ~}
      server ${join(" ", concat([server.url], server.options))}
%{ endfor ~}
%{ for pool in chrony.pools ~}
      pool ${join(" ", concat([pool.url], pool.options))}
%{ endfor ~}
      driftfile /var/lib/chrony/drift
      makestep ${chrony.makestep.threshold} ${chrony.makestep.limit}
      rtcsync
%{ endif ~}
  #Postgres certs
  - path: /opt/postgres/pg.key
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, tls_pg_key)}
  - path: /opt/postgres/pg.pem
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, tls_pg_cert)}
  - path: /opt/postgres/patroni_client.key
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, tls_patroni_client_key)}
  - path: /opt/postgres/patroni_client.pem
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, tls_patroni_client_cert)}
  - path: /opt/postgres/pg_ca.pem
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, tls_pg_ca_cert)}
  #Etcd certs
  - path: /opt/etcd/ca.pem
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, tls_etcd_ca_cert)}
  #Prometheus node exporter systemd configuration
  - path: /etc/systemd/system/node-exporter.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Prometheus Node Exporter"
      Wants=network-online.target
      After=network-online.target

      [Service]
      User=node-exporter
      Group=node-exporter
      Type=simple
      ExecStart=/usr/local/bin/node_exporter

      [Install]
      WantedBy=multi-user.target
%{ if fluentd.enabled ~}
  #Fluentd config file
  - path: /opt/fluentd.conf
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, fluentd_conf)}
  #Fluentd systemd configuration
  - path: /etc/systemd/system/fluentd.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Fluentd"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      User=root
      Group=root
      Type=simple
      Restart=always
      RestartSec=1
      ExecStart=fluentd -c /opt/fluentd.conf

      [Install]
      WantedBy=multi-user.target
  #Fluentd forward server certificate
  - path: /opt/fluentd_ca.crt
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, fluentd.forward.ca_cert)}
%{ endif ~}
  #Patroni
  - path: /opt/patroni.yml
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, patroni_conf)}
  - path: /etc/systemd/system/patroni.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Postgres Patroni"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      User=postgres
      Group=postgres
      Type=simple
      Restart=always
      RestartSec=1
      ExecStart=patroni /opt/patroni.yml

      [Install]
      WantedBy=multi-user.target
packages:
  - python3
  - python3-pip
  - lsb-release
  - wget
  - gnupg-agent
  - libpq-dev
%{ if fluentd.enabled ~}
  - ruby-full
  - build-essential
%{ endif ~}
%{ if chrony.enabled ~}
  - chrony
%{ endif ~}
runcmd:
  #Finalize Chrony Setup
%{ if chrony.enabled ~}
  - cp /opt/chrony.conf /etc/chrony/chrony.conf
  - systemctl restart chrony.service 
%{ endif ~}
  #Install prometheus node exporter as a binary managed as a systemd service
  - wget -O /opt/node_exporter.tar.gz https://github.com/prometheus/node_exporter/releases/download/v1.3.0/node_exporter-1.3.0.linux-amd64.tar.gz
  - mkdir -p /opt/node_exporter
  - tar zxvf /opt/node_exporter.tar.gz -C /opt/node_exporter
  - cp /opt/node_exporter/node_exporter-1.3.0.linux-amd64/node_exporter /usr/local/bin/node_exporter
  - chown node-exporter:node-exporter /usr/local/bin/node_exporter
  - rm -r /opt/node_exporter && rm /opt/node_exporter.tar.gz
  - systemctl enable node-exporter
  - systemctl start node-exporter
  #Fluentd setup
%{ if fluentd.enabled ~}
  - mkdir -p /opt/fluentd-state
  - chown root:root /opt/fluentd-state
  - chmod 0700 /opt/fluentd-state
  - gem install fluentd
  - gem install fluent-plugin-systemd -v 1.0.5
  - systemctl enable fluentd.service
  - systemctl start fluentd.service
%{ endif ~}
  #Install postgres
  - echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
  - wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
  - apt-get update
  - apt-get install -y postgresql-14 postgresql-contrib-14
  - systemctl stop postgresql
  - systemctl disable postgresql
  - mkdir -p /var/lib/postgresql/14/data
  - chmod 0700 /var/lib/postgresql/14/data
  - chown postgres:postgres /var/lib/postgresql/14/data
  - rm /var/log/postgresql/*
  #Install patroni
  - modprobe softdog
  - chown postgres:postgres /dev/watchdog
  - chown postgres:postgres /opt/patroni.yml
  - mkdir -p /opt/patroni
  - chown postgres:postgres /opt/patroni
  - chown -R postgres:postgres /opt/postgres
  - chown -R postgres:postgres /opt/etcd
  - pip3 install --upgrade pip
  - pip3 install psycopg2>=2.5.4
%{ if patroni_version != "" ~}
  - pip3 install patroni[etcd3]==${patroni_version}
%{ else ~}
  - pip3 install patroni[etcd3]
%{ endif ~}
  - systemctl enable patroni.service
  - systemctl start patroni.service