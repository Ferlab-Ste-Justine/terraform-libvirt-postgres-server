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
  - **is_synchronous**: Boolean indicating whether synchronous synchronization should be used between the leader and the replicas.
  - **synchronous_settings**: Settings if the synchronization is synchronous. It has the following keys:
    - **strict**: Boolean indicating whether the synchronous synchronization is strict or not.
    - **synchronous_node_count**: Number of additional nodes a transaction commit should be writen to in addition to the leader to report a success.
  - **asynchronous_settings**: Settings if the synchronization is asynchronous. It has the following keys:
    - **maximum_lag_on_failover**: Maximum WAL lag in bytes a replica is allowed to have in order to be considered for leadership when cluster leadership is lost.
- **chrony**: Optional chrony configuration for when you need a more fine-grained ntp setup on your vm. It is an object with the following fields:
  - **enabled**: If set the false (the default), chrony will not be installed and the vm ntp settings will be left to default.
  - **servers**: List of ntp servers to sync from with each entry containing two properties, **url** and **options** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#server)
  - **pools**: A list of ntp server pools to sync from with each entry containing two properties, **url** and **options** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#pool)
  - **makestep**: An object containing remedial instructions if the clock of the vm is significantly out of sync at startup. It is an object containing two properties, **threshold** and **limit** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#makestep)
- **fluentbit**: Optional fluend configuration to securely route logs to a fluend/fluent-bit node using the forward plugin. Alternatively, configuration can be 100% dynamic by specifying the parameters of an etcd store to fetch the configuration from. It has the following keys:
  - **enabled**: If set the false (the default), fluent-bit will not be installed.
  - **patroni_tag**: Tag to assign to logs coming from patroni
  - **node_exporter_tag** Tag to assign to logs coming from the prometheus node exporter
  - **forward**: Configuration for the forward plugin that will talk to the external fluend/fluent-bit node. It has the following keys:
    - **domain**: Ip or domain name of the remote fluend node.
    - **port**: Port the remote fluend node listens on
    - **hostname**: Unique hostname identifier for the vm
    - **shared_key**: Secret shared key with the remote fluentd node to authentify the client
    - **ca_cert**: CA certificate that signed the remote fluentd node's server certificate (used to authentify it)
- **fluentbit_dynamic_config**: Optional configuration to update fluent-bit configuration dynamically either from an etcd key prefix or a path in a git repo.
  - **enabled**: Boolean flag to indicate whether dynamic configuration is enabled at all. If set to true, configurations will be set dynamically. The default configurations can still be referenced as needed by the dynamic configuration. They are at the following paths:
    - **Global Service Configs**: /etc/fluent-bit-customization/default-config/service.conf
    - **Default Variables**: /etc/fluent-bit-customization/default-config/default-variables.conf
    - **Systemd Inputs**: /etc/fluent-bit-customization/default-config/inputs.conf
    - **Forward Output For All Inputs**: /etc/fluent-bit-customization/default-config/output-all.conf
    - **Forward Output For Default Inputs Only**: /etc/fluent-bit-customization/default-config/output-default-sources.conf
  - **source**: Indicates the source of the dynamic config. Can be either **etcd** or **git**.
  - **etcd**: Parameters to fetch fluent-bit configurations dynamically from an etcd cluster. It has the following keys:
    - **key_prefix**: Etcd key prefix to search for fluent-bit configuration
    - **endpoints**: Endpoints of the etcd cluster. Endpoints should have the format `<ip>:<port>`
    - **ca_certificate**: CA certificate against which the server certificates of the etcd cluster will be verified for authenticity
    - **client**: Client authentication. It takes the following keys:
      - **certificate**: Client tls certificate to authentify with. To be used for certificate authentication.
      - **key**: Client private tls key to authentify with. To be used for certificate authentication.
      - **username**: Client's username. To be used for username/password authentication.
      - **password**: Client's password. To be used for username/password authentication.
    - **vault_agent_secret_path**: Optional vault secret path for an optional vault agent to renew the etcd client credentials. The secret in vault is expected to have the **certificate** and **key** keys if certificate authentication is used or the **username** and **password** keys if password authentication is used.
  - **git**: Parameters to fetch fluent-bit configurations dynamically from an git repo. It has the following keys:
    - **repo**: Url of the git repository. It should have the ssh format.
    - **ref**: Git reference (usually branch) to checkout in the repository
    - **path**: Path to sync from in the git repository. If the empty string is passed, syncing will happen from the root of the repository.
    - **trusted_gpg_keys**: List of trusted gpp keys to verify the signature of the top commit. If an empty list is passed, the commit signature will not be verified.
    - **auth**: Authentication to the git server. It should have the following keys:
      - **client_ssh_key** Private client ssh key to authentication to the server.
      - **server_ssh_fingerprint**: Public ssh fingerprint of the server that will be used to authentify it.
- **vault_agent**: Parameters for the optional vault agent that will be used to manage the dynamic secrets in the vm.
  - **enabled**: If set to true, a vault agent service will be setup and will run in the vm.
  - **auth_method**: Auth method the vault agent will use to authenticate with vault. Currently, only approle is supported.
    - **config**: Configuration parameters for the auth method.
      - **role_id**: Id of the app role to us.
      - **secret_id**: Authentication secret to use the app role.
  - **vault_address**: Endpoint to use to talk to vault.
  - **vault_ca_cert**: CA certificate to use to validate vault's certificate.
- **install_dependencies**: Whether cloud-init should install external dependencies (should be set to false if you already provide an image with the external dependencies built-in).

## Example

For an example of a patroni cluster that can be run locally with this module, see: https://github.com/Ferlab-Ste-Justine/kvm-dev-orchestrations/tree/main/postgres

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