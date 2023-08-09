#!/bin/bash
yum update -y

# Download rancher files
cd /tmp
curl -fSsLO ${rancher_binary_url}
curl -fSsLO ${rancher_images_url}

# Decompress rancher images
mkdir -p /var/lib/rancher/rke2/agent/images
gunzip rke2-images.linux-amd64.tar.gz
mv rke2-images.linux-amd64.tar /var/lib/rancher/rke2/agent/images/

# Install rancher tarball
mkdir -p /usr/local
tar xzf rke2.linux-amd64.tar.gz -C /usr/local

# Configure Kernel parameters
cp -f /usr/local/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf
sysctl fs.inotify.max_user_watches=524288
sysctl fs.inotify.max_user_instances=512
echo "fs.inotify.max_user_watches=524288" >> /etc/sysctl.conf
echo "fs.inotify.max_user_instances=512" >> /etc/sysctl.conf
systemctl restart systemd-sysctl

# Create etcd user
useradd -r -c "etcd user" -s /sbin/nologin -M etcd

# Create config directory
mkdir -p /etc/rancher/rke2

# Setup to get to kubectl
echo "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml" >> ~/.bashrc
echo "export PATH=\$PATH:/var/lib/rancher/rke2/bin" >> ~/.bashrc

# Identify if we are the first server to launch
AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

# See if a control-plane server is listening on the control plane endpoint
if [[ "$AVAILABILITY_ZONE" == *"1a"* ]]; then
    echo "This is likely the first control-plane node to come online"

    if timeout 1 bash -c "true <>/dev/tcp/${control_plane_dns}/9345" 2>/dev/null
    then
      echo "Supervisor port is available, this is NOT the first node to come online"
      echo "server: https://${control_plane_dns}:9345" > /etc/rancher/rke2/config.yaml
    else
      echo "Supervisor port is NOT available, this is the first node to come online"
      NODE_TYPE="leader"
    fi
else
  echo "This is likely NOT the first control-plane node to come online due to not being in the first az"
  echo "server: https://${control_plane_dns}:9345" > /etc/rancher/rke2/config.yaml
fi

# Get the provider_id
provider_id="$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)/$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"

# Get the internal hostname
internal_hostname="$(curl -s http://169.254.169.254/latest/meta-data/local-hostname | awk -F '.' '{print $1}').$(curl -s http://169.254.169.254/latest/meta-data/placement/region).compute.internal"

# This is to fix a conflict that can occur if the DHCP domain-name doesn't match what aws has on file
# The AWS Cloud Controller Manager uses the AWS private dns name and overrides what kubernetes has
# for each node when the cluster is setup.
hostnamectl set-hostname $internal_hostname

# Configure server
region=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
cat <<EOF >> /etc/rancher/rke2/config.yaml
token: "${rancher_token}"
kubelet-arg:
  - "provider-id=aws:///$provider_id"
kube-apiserver-arg:
  - "api-audiences=https://kubernetes.default.svc.cluster.local,rke2,sts.amazonaws.com"
  - "service-account-issuer=https://kubernetes.default.svc.cluster.local"
  - "service-account-issuer=https://${project}-${environment}-oidc.s3.$region.amazonaws.com"
node-taint:
  - "CriticalAddonsOnly=true:NoExecute"
tls-san:
  - "${control_plane_dns}"
disable:
  - "rke2-ingress-nginx"
etcd-s3: "true"
etcd-s3-bucket: "${etcd_backup_bucket}"
etcd-s3-region: "$region"
EOF

if [[ "$NODE_TYPE" == "leader" ]]; then
  # Perform control-plane installation
  echo "Enabling and starting RKE2"
  systemctl enable rke2-server
  systemctl start rke2-server

else
  while true; do
    if timeout 1 bash -c "true <>/dev/tcp/${control_plane_dns}/6443" 2>/dev/null; then
      echo "Cluster is ready"

      # TODO: Fix this - if the cluster just initialized it typically takes a few extra seconds to register other nodes
      sleep 30
      # Perform control-plane installation
      systemctl enable rke2-server
      systemctl start rke2-server
      break
    fi
    echo "Waiting for cluster to be ready..."
    sleep 10
  done
fi