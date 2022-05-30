scope: ${patroni.scope}
namespace: ${patroni.namespace}
name: ${patroni.name}

restapi:
  listen: 0.0.0.0:4443
  connect_address: ${advertised_ip}:4443
  certfile: /opt/postgres/pg.pem
  keyfile: /opt/postgres/pg.key
  cafile: /opt/postgres/pg_ca.pem
  verify_client: required

ctl:
  insecure: false
  certfile: /opt/postgres/patroni_client.pem
  keyfile: /opt/postgres/patroni_client.key
  cacert: /opt/postgres/pg_ca.pem

etcd3:
  protocol: https
  cacert: /opt/etcd/ca.pem
  username: ${etcd.username}
  password: ${etcd.password}
  hosts:
%{ for etcd_host in etcd.hosts ~}
    - ${etcd_host}
%{ endfor ~}

bootstrap:
  dcs:
    ttl: ${patroni.ttl}
    loop_wait: ${patroni.loop_wait}
    retry_timeout: ${patroni.retry_timeout}
    master_start_timeout: ${patroni.master_start_timeout}
    master_stop_timeout: ${patroni.master_stop_timeout}
    synchronous_mode: true
    synchronous_mode_strict: true
    synchronous_node_count: ${patroni.synchronous_node_count}
    postgresql:
      use_pg_rewind: false
      use_slots: true
      parameters:
        ssl: on
        ssl_cert_file: /opt/postgres/pg.pem
        ssl_key_file: /opt/postgres/pg.key
        log_directory: /var/log/postgresql
%{ for param in postgres.params ~}
        ${param.key}:${param.value}
%{ endfor ~}

  initdb:
    - encoding: UTF8
    - data-checksums
    - locale: C

postgresql:
  listen: 0.0.0.0:5432
  connect_address: ${advertised_ip}:5432
  data_dir: /var/lib/postgresql/14/data
  bin_dir: /usr/lib/postgresql/14/bin
  pgpass: /opt/patroni/.pgpass
  pg_hba:
    - hostssl all all 0.0.0.0/0 scram-sha-256
    - hostssl replication replicator 0.0.0.0/0 scram-sha-256
  authentication:
    replication:
      username: replicator
      password: ${postgres.replicator_password}
      sslmode: verify-full
      sslrootcert: /opt/postgres/pg_ca.pem
    superuser:
      username: postgres
      password: ${postgres.superuser_password}
      sslmode: verify-full
      sslrootcert: /opt/postgres/pg_ca.pem

watchdog:
  mode: required
  device: /dev/watchdog
  safety_margin: ${patroni.watchdog_safety_margin}

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false