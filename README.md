# About

This is a terraform module that provisions a postgres server that is part of a patroni high availability cluster. The settings are configured for synchronous replication with the emphasis placed on data consistency and durability above availability when the two goals are at odds.

Given a certificate authority, it will generate its server-side certificate and key to server traffic over tls.

Given that it is the common denominator for all the clients we are using, only password authentication is supported for now. The module will take a password as an argument for its superuser account.

# Libvirt Networking Support

This module supports both libvirt networks and direct macvtap connection (bridge mode).

# Usage

## Variables

This module takes the following variables as input:

- **name**: Name to give to the vm. Will be the hostname as well.
- **vcpus**: Number of vcpus to assign to the vm. Defaults to 2.
- **memory**: Amount of memory in MiB to assign to the vm. Defaults to 8192.
- **volume_id**: Id of the image volume to attach to the vm. A recent version of ubuntu is recommended as this is what this module has been validated against.
- **data_volume_id**: Id for an optional separate disk volume to attach to the vm on postgres' data path
- **libvirt_network**: Parameters to connect to libvirt networks. Note that only the first interface in the list (libvirt network and macvtap) will be used to advertise the patroni rest api. Each entry has the following keys:
  - **network_id**: Id (ie, uuid) of the libvirt network to connect to (in which case **network_name** should be an empty string).
  - **network_name**: Name of the libvirt network to connect to (in which case **network_id** should be an empty string).
  - **ip**: Ip of interface connecting to the libvirt network.
  - **mac**: Mac address of interface connecting to the libvirt network.
  - **prefix_length**:  Length of the network prefix for the network the interface will be connected to. For a **192.168.1.0/24** for example, this would be **24**.
  - **gateway**: Ip of the network's gateway. Usually the gateway the first assignable address of a libvirt's network.
  - **dns_servers**: Dns servers to use. Usually the dns server is first assignable address of a libvirt's network.
- **macvtap_interfaces**: List of macvtap interfaces to connect the vm to if you opt for macvtap interfaces. Note that only the first interface in the list (libvirt network and macvtap) will be used to advertise the patroni rest api. Each entry in the list is a map with the following keys:
  - **interface**: Host network interface that you plan to connect your macvtap interface with.
  - **prefix_length**: Length of the network prefix for the network the interface will be connected to. For a **192.168.1.0/24** for example, this would be 24.
  - **ip**: Ip associated with the macvtap interface. 
  - **mac**: Mac address associated with the macvtap interface
  - **gateway**: Ip of the network's gateway for the network the interface will be connected to.
  - **dns_servers**: Dns servers for the network the interface will be connected to. If there aren't dns servers setup for the network your vm will connect to, the ip of external dns servers accessible accessible from the network will work as well.
- **cloud_init_volume_pool**: Name of the volume pool that will contain the cloud-init volume of the vm.
- **cloud_init_volume_name**: Name of the cloud-init volume that will be generated by the module for your vm. If left empty, it will default to **<name>-cloud-init.iso**.
- **ssh_admin_user**: Username of the default sudo user in the image. Defaults to **ubuntu**.
- **admin_user_password**: Optional password for the default sudo user of the image. Note that this will not enable ssh password connections, but it will allow you to log into the vm from the host using the **virsh console** command.
- **ssh_admin_public_key**: Public part of the ssh key the admin will be able to login as
- **postgres**: Postgres configurations. It has the following keys:
  - **params**: List of postgres parameters represented by **key** and **value** keys for each entry. Note that the master will set those values in etcd and it will be shared by all members. Given that which node will be elected the leader is random, it should be set the same in all members.
  - **replicator_password**: Password for the replicator user.
  - **superuser_password**: Password for the postgres superuser
  - **ca**: Pre-existing internal ca that will sign the postgres server certificates. It has the following keys:
    - **key**: Private key of the ca
    - **key_algorithmn**: Algorithm of the ca's private key
    - **certificate**: Public certificate of the ca
  - **certificate**: Parameters of the generated certificate for the server. It has the following keys:
    - **domains**: Domains the service certificate is for
    - **extra_ips**: Extra ips that will also be included in the certificate
    - **organization**: Organization for the certificate
    - **validity_period**: Certificate's validity period in hours
    - **early_renewal_period**: Time before the certificate's expiry when terraform will try to reprovision the certificate
- **etcd**: Patroni etcd backend configuration. Note that the etcd server needs to have the grpc gateway enabled with username/password authentication. It has the following keys:
  - **endpoints**: List of etcd hosts, each entry having the ```<ip>:<port>``` format.
  - **ca_cert**: Ca certificate for the etcd servers
  - **username**: User of the etcd user that patroni will use to connect to etcd.
  - **password**: Password of the etcd user that patroni will use to connect to etcd.
- **patroni**: Patroni configuration. It has the following keys:
  - **scope**: Name of the patroni cluster.
  - **namespace**: Key prefix for all patroni keys in etcd 
  - **name**: Name of the member (should be unique for each node in the cluster)
  - **ttl**: TTL time (in seconds) the leader has to renew the lock before replicas conclude the leader is no longer available and trigger the election of a new leader.
  - **loop_wait**: Amount of time (in seconds) the patroni process will sleep between iterations.
  - **retry_timeout**: Timetout for etcd and postgres operation retries. If it takes longer than this, patroni will demote the leader.
  - **master_start_timeout**: Amount of time (in seconds) a failing master has to recover before patroni demotes it as leader.
  - **master_stop_timeout**: Amount of time (in seconds) patroni will wait after a shutdown trigger before sending SIGKILL to the postgres server it manages.
  - **watchdog_safety_margin**: Safety margin before leader lock ttl expire where watchdown will force master shutdown to prevent split brain. See documentation for usager: https://patroni.readthedocs.io/en/latest/watchdog.html
  - **synchronous_node_count**: Number of additional nodes a transaction commit should be writen to in addition to the master to report a success.
- **chrony**: Optional chrony configuration for when you need a more fine-grained ntp setup on your vm. It is an object with the following fields:
  - **enabled**: If set the false (the default), chrony will not be installed and the vm ntp settings will be left to default.
  - **servers**: List of ntp servers to sync from with each entry containing two properties, **url** and **options** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#server)
  - **pools**: A list of ntp server pools to sync from with each entry containing two properties, **url** and **options** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#pool)
  - **makestep**: An object containing remedial instructions if the clock of the vm is significantly out of sync at startup. It is an object containing two properties, **threshold** and **limit** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#makestep)
- **fluentbit**: Fluent Bit configuration for log routing and metrics collection. This includes:
  - **enabled**: If set to false (the default), Fluent Bit will not be installed.
  - **patroni_tag**: Tag to assign to logs coming from Patroni.
  - **node_exporter_tag**: Tag for logs from the Prometheus node exporter.
  - **metrics**: Configuration for metrics collection.
  - **forward**: Configuration for the forward plugin to communicate with a remote Fluentbit node. Includes domain, port, hostname, shared key, and CA certificate.
- **fluentbit_dynamic_config**: Configuration for dynamic Fluent Bit setup. Includes:
  - **enabled**: Whether dynamic config is enabled.
  - **source**: The source of dynamic configuration (e.g., 'etcd', 'git').
  - **etcd**: Configuration for etcd as a source.
  - **git**: Configuration for Git as a source.
- **install_dependencies**: Whether cloud-init should install external dependencies (should be set to false if you already provide an image with the external dependencies built-in).

## Example

Below is an orchestration I ran locally to troubleshoot the module.

```

locals {
  etcd_conf = {
    endpoints = ["192.168.122.155:2379", "192.168.122.156:2379", "192.168.122.157:2379"]
    ca_cert = file("${path.module}/../shared/etcd-ca.pem")
    username = etcd_user.patroni.username
    password = etcd_user.patroni.password
  }
}

resource "libvirt_volume" "postgres_1" {
  name             = "postgres-1"
  pool             = "default"
  // 50 GiB
  size             = 10 * 1024 * 1024 * 1024
  base_volume_pool = "os"
  base_volume_name = "ubuntu-focal-2021-04-29"
  format           = "qcow2"
}

module "postgres_1" {
  source = "git::https://github.com/Ferlab-Ste-Justine/kvm-postgres-server.git"
  name = "postgres-1"
  vcpus = 1
  memory = 4096
  volume_id = libvirt_volume.postgres_1.id
  libvirt_networks = [{
    network_id = "b10c1bda-f608-4780-9cfb-574c2271a193"
    ip = "192.168.122.158"
    mac = "52:54:00:DE:E3:67"
    gateway = local.params.network.gateway
    dns_servers = [local.params.network.dns]
    prefix_length = split("/", local.params.network.addresses).1
  }]
  cloud_init_volume_pool = "default"
  ssh_admin_public_key = tls_private_key.admin_ssh.public_key_openssh
  admin_user_password = "mockpass"
  postgres = {
    params = []
    replicator_password = random_password.postgres_root_password.result
    superuser_password = random_password.postgres_root_password.result
    ca = module.postgres_ca
    certificate = {
      domains = ["server.postgres.local", "load-balancer.postgres.local", "192.168.122.162"]
      extra_ips = ["192.168.122.162"]
      organization = "Ferlab"
      validity_period = 100*365*24
      early_renewal_period = 365*24
    }
  }
  etcd = local.etcd_conf
  patroni = {
    scope = "patroni"
    namespace = "/patroni/"
    name = "postgres-1"
    ttl = 60
    loop_wait = 5
    retry_timeout = 10
    master_start_timeout = 300
    master_stop_timeout = 300
    watchdog_safety_margin = -1
    synchronous_node_count = 1
  }
}

resource "libvirt_volume" "postgres_2" {
  name             = "postgres-2"
  pool             = "default"
  // 50 GiB
  size             = 10 * 1024 * 1024 * 1024
  base_volume_pool = "os"
  base_volume_name = "ubuntu-focal-2021-04-29"
  format           = "qcow2"
}

module "postgres_2" {
  source = "git::https://github.com/Ferlab-Ste-Justine/kvm-postgres-server.git"
  name = "postgres-2"
  vcpus = 1
  memory = 4096
  volume_id = libvirt_volume.postgres_2.id
  libvirt_networks = [{
    network_id = "b10c1bda-f608-4780-9cfb-574c2271a193"
    ip = "192.168.122.159"
    mac = "52:54:00:DE:E3:68"
    gateway = local.params.network.gateway
    dns_servers = [local.params.network.dns]
    prefix_length = split("/", local.params.network.addresses).1
  }]
  cloud_init_volume_pool = "default"
  ssh_admin_public_key = tls_private_key.admin_ssh.public_key_openssh
  admin_user_password = "mockpass"
  postgres = {
    params = []
    replicator_password = random_password.postgres_root_password.result
    superuser_password = random_password.postgres_root_password.result
    ca = module.postgres_ca
    certificate = {
      domains = ["server.postgres.local", "load-balancer.postgres.local", "192.168.122.162"]
      extra_ips = ["192.168.122.162"]
      organization = "Ferlab"
      validity_period = 100*365*24
      early_renewal_period = 365*24
    }
  }
  etcd = local.etcd_conf
  patroni = {
    scope = "patroni"
    namespace = "/patroni/"
    name = "postgres-2"
    ttl = 60
    loop_wait = 5
    retry_timeout = 10
    master_start_timeout = 300
    master_stop_timeout = 300
    watchdog_safety_margin = -1
    synchronous_node_count = 1
  }
}

resource "libvirt_volume" "postgres_3" {
  name             = "postgres-3"
  pool             = "default"
  // 50 GiB
  size             = 10 * 1024 * 1024 * 1024
  base_volume_pool = "os"
  base_volume_name = "ubuntu-focal-2021-04-29"
  format           = "qcow2"
}

module "postgres_3" {
  source = "git::https://github.com/Ferlab-Ste-Justine/kvm-postgres-server.git"
  name = "postgres-3"
  vcpus = 1
  memory = 4096
  volume_id = libvirt_volume.postgres_3.id
  libvirt_networks = [{
    network_id = "b10c1bda-f608-4780-9cfb-574c2271a193"
    ip = "192.168.122.160"
    mac = "52:54:00:DE:E3:69"
    gateway = local.params.network.gateway
    dns_servers = [local.params.network.dns]
    prefix_length = split("/", local.params.network.addresses).1
  }]
  cloud_init_volume_pool = "default"
  ssh_admin_public_key = tls_private_key.admin_ssh.public_key_openssh
  admin_user_password = "mockpass"
  postgres = {
    params = []
    replicator_password = random_password.postgres_root_password.result
    superuser_password = random_password.postgres_root_password.result
    ca = module.postgres_ca
    certificate = {
      domains = ["server.postgres.local", "load-balancer.postgres.local", "192.168.122.162"]
      extra_ips = ["192.168.122.162"]
      organization = "Ferlab"
      validity_period = 100*365*24
      early_renewal_period = 365*24
    }
  }
  etcd = local.etcd_conf
  patroni = {
    scope = "patroni"
    namespace = "/patroni/"
    name = "postgres-3"
    ttl = 60
    loop_wait = 5
    retry_timeout = 10
    master_start_timeout = 300
    master_stop_timeout = 300
    watchdog_safety_margin = -1
    synchronous_node_count = 1
  }
}
```

## Gotchas

### Macvtap and Host Traffic

Because of the way macvtap is setup in bridge mode, traffic from the host to the guest vm is not possible. However, traffic from other guest vms on the host or from other physical hosts on the network will work fine.

### Volume Pools, Ubuntu and Apparmor

At the time of this writing, libvirt will not set the apparmor permission of volume pools properly on recent versions of ubuntu. This will result in volumes that cannot be attached to your vms (you will get a permission error).

You need to setup the permissions in apparmor yourself for it to work.

See the following links for the bug and workaround:

- https://bugs.launchpad.net/ubuntu/+source/libvirt/+bug/1677398
- https://bugs.launchpad.net/ubuntu/+source/libvirt/+bug/1677398/comments/43

### Requisite Outgoing Traffic

Note that because cloud-init installs external dependencies, you will need working dns that can resolve names on the internet and outside connectivity for the vm.