#!/bin/bash
yum update -y
yum install -y amazon-ecr-credential-helper

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

# Get the provider_id
provider_id="$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)/$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"

# Get the internal hostname
internal_hostname="$(curl -s http://169.254.169.254/latest/meta-data/local-hostname | awk -F '.' '{print $1}').$(curl -s http://169.254.169.254/latest/meta-data/placement/region).compute.internal"

# This is to fix a conflict that can occur if the DHCP domain-name doesn't match what aws has on file
# The AWS Cloud Controller Manager uses the AWS private dns name and overrides what kubernetes has
# for each node when the cluster is setup.
hostnamectl set-hostname $internal_hostname

# Configure server
cat <<EOF > /etc/rancher/rke2/config.yaml
server: https://${control_plane_dns}:9345
token: ${rancher_token}
kubelet-arg:
  - "cloud-provider=external"
  - "provider-id=aws:///$provider_id"
# profile: "cis-1.5"
EOF

# Determine if we have any GPUs and set up required configuration for it
# This looks to see if the nvidia driver is installed (by checking if /proc/driver/nvidia/gpus exists)
# and making sure there are actually GPUs visible (in case the nvidia driver is installed with no physical GPUs)
if [ -d "/proc/driver/nvidia/gpus/" ] && [ $(ls -1 /proc/driver/nvidia/gpus/ | wc -l) -gt 0 ]; then
  echo "This is a GPU node, configuring containerd..."

  echo "reinstalling nvidia-container-toolkit to fix nvidia-container-runtime-hook broken link"
  # https://github.com/NVIDIA/nvidia-docker/issues/1017#issuecomment-673152551
  yum reinstall nvidia-container-toolkit -y

  # Configure RKE2 to use external containerd
  # Source: https://gist.github.com/bgulla/3b725f0eea54fdd49f4d7066e16b1d89
  echo "container-runtime-endpoint: unix:///run/containerd/containerd.sock" >> /etc/rancher/rke2/config.yaml

  # Configure containerd to use nvidia-container-runtime
  # https://github.com/NVIDIA/k8s-device-plugin/issues/182

  # Reset config to default as the default config has every line commented out
  containerd config default > /etc/containerd/config.toml

  # Replace/Add lines to use the nvidia-container-runtime
  sed -i 's/^      default_runtime_name = "runc"/      default_runtime_name = "nvidia-container-runtime"/' /etc/containerd/config.toml
  sed -i 's/^      \[plugins."io.containerd.grpc.v1.cri".containerd.runtimes\]/      \[plugins."io.containerd.grpc.v1.cri".containerd.runtimes\]\n        \[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia-container-runtime\]\n          runtime_type = "io.containerd.runtime.v1.linux"/' /etc/containerd/config.toml
  sed -i 's/^    runtime = "runc"/    runtime = "nvidia-container-runtime"/' /etc/containerd/config.toml

  systemctl restart containerd
  echo "Done configuring containerd"

  cat <<EOF >> /etc/rancher/rke2/config.yaml
node-label:
  - "nvidia-gpu=true"
EOF
fi

# Perform node installation
systemctl enable rke2-agent
systemctl start rke2-agent