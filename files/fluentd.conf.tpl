<system>
  Log_Level info
</system>

<source>
  @type systemd
  tag ${fluentd.patroni_tag}
  path /var/log/journal
  matches [{ "_SYSTEMD_UNIT": "patroni.service" }]
  read_from_head true

  <storage>
    @type local
    path /opt/fluentd-state/patroni-cursor.json
  </storage>
</source>

<source>
  @type systemd
  tag ${fluentd.node_exporter_tag}
  path /var/log/journal
  matches [{ "_SYSTEMD_UNIT": "node-exporter.service" }]
  read_from_head true

  <storage>
    @type local
    path /opt/fluentd-state/node-exporter-cursor.json
  </storage>
</source>

<match *>
  @type forward
  transport tls
  tls_insecure_mode false
  tls_allow_self_signed_cert false
  tls_verify_hostname true
  tls_cert_path /opt/fluentd_ca.crt
  send_timeout 20
  connect_timeout 20
  hard_timeout 20
  recover_wait 10
  expire_dns_cache 5
  dns_round_robin true

  <server>
    host ${fluentd.forward.domain}
    port ${fluentd.forward.port}
  </server>

  <security>
    self_hostname ${fluentd.forward.hostname}
    shared_key ${fluentd.forward.shared_key}
  </security>

  <buffer tag>
    @type memory
    flush_at_shutdown true
    flush_mode interval
    flush_interval 10
    delayed_commit_timeout 10
    chunk_limit_records 20
    retry_type exponential_backoff
    retry_exponential_backoff_base 2
    retry_wait 1
    retry_max_interval 30
    retry_timeout 3600
  </buffer>
</match>