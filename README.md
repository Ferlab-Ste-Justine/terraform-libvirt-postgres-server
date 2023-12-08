# About

This Terraform module provisions a PostgreSQL server as part of a Patroni high availability cluster. It is configured for synchronous replication, with a focus on data consistency and durability over availability. The module generates server-side certificates for TLS-secured traffic from a given certificate authority. Currently, it supports only password authentication, accepting a password for its superuser account.

# Libvirt Networking Support

The module supports both libvirt networks and direct macvtap connections (in bridge mode).

# Usage

## Variables

The module requires the following variables:

- **name**: The name for the VM, also used as the hostname.
- **vcpus**: The number of virtual CPUs for the VM. Defaults to 2.
- **memory**: The amount of memory in MiB for the VM. Defaults to 8192.
- **volume_id**: ID of the image volume to attach to the VM. A recent version of Ubuntu is recommended.
- **data_volume_id**: ID for an optional separate disk volume for PostgreSQL's data path.
- **libvirt_networks**: Parameters for connecting to libvirt networks. Includes network ID or name, IP, MAC, prefix length, gateway, and DNS servers.
- **macvtap_interfaces**: List of macvtap interfaces for bridge mode connection. Includes interface, prefix length, IP, MAC, gateway, and DNS servers.
- **cloud_init_volume_pool**: Name of the volume pool containing the cloud-init volume.
- **cloud_init_volume_name**: Name of the cloud-init volume; defaults to `<name>-cloud-init.iso`.
- **ssh_admin_user**: Username for the default sudo user in the image; defaults to "ubuntu".
- **admin_user_password**: Optional password for the sudo user.
- **ssh_admin_public_key**: Public SSH key for admin login.
- **postgres**: PostgreSQL configuration including parameters, replicator and superuser passwords, CA details, and server certificate parameters.
- **etcd**: Configuration for the Patroni etcd backend.
- **patroni**: Configuration settings for Patroni.
- **chrony**: Optional Chrony configuration for NTP setup.
- **fluentbit**: Optional Fluent Bit configuration for log routing and metrics collection.
- **fluentbit_dynamic_config**: Configuration for Fluent Bit dynamic config if enabled.
- **install_dependencies**: Whether cloud-init should install external dependencies.

## Example

An example orchestration for local module testing is provided.

## Gotchas

### Macvtap and Host Traffic

Traffic from the host to guest VMs is not possible with macvtap in bridge mode, though traffic from other guest VMs or network hosts works fine.

### Volume Pools, Ubuntu, and Apparmor

Libvirt may not set Apparmor permissions correctly on recent Ubuntu versions, affecting volume attachment to VMs. Manual setup of permissions is required.

### Requisite Outgoing Traffic

Working DNS and internet connectivity are required for cloud-init to install external dependencies.
