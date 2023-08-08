Installing RKE2 Server on Ubuntu using Ansible

This documentation outlines the steps to install RKE2 server (Rancher Kubernetes Engine 2) on Ubuntu using Ansible. RKE2 is a lightweight Kubernetes distribution developed by Rancher Labs.
Prerequisites

Before proceeding, ensure that you have the following prerequisites in place:

    Ansible: Make sure Ansible is installed on your local machine.
    SSH Access: Ensure you have SSH access to the target hosts where you want to install RKE2.
    Sudo or Root Access: Make sure you have sudo or root access on the target hosts.

Step 1: Create an Ansible Playbook

Create a new Ansible playbook (e.g., rke-server) with the following content:

yaml

---
- name: Install RKE2 server on Ubuntu
  hosts: rke2_master
  become: true
  tasks:
    - name: Add RKE2 repository GPG key
      apt_key:
        url: https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/xUbuntu_{{ ansible_distribution_release }}/Release.key
        state: present

    - name: Add RKE2 APT repository
      apt_repository:
        repo: deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_{{ ansible_distribution_release }}/
        state: present
        filename: rke2

    - name: Update APT cache
      apt:
        update_cache: yes

    - name: Install RKE2 server package
      apt:
        name: rke2-server
        state: latest

    - name: Start RKE2 service
      service:
        name: rke2-server
        state: started

    - name: Enable RKE2 service on boot
      service:
        name: rke2-server
        enabled: yes

Step 2: Create an Inventory File

Create an Ansible inventory file (e.g., inventory.ini) containing the target hosts' information:

ini

[rke2_master]
192.168.1.70
[rke2_master:vars]
ansible_user='admin'
ansible_password='password'
ansible_become_password='password'
# Add more hosts if needed

Replace your_target_host1, your_target_host2, etc., in the inventory file with the actual IP addresses or hostnames of the target hosts where you want to install RKE2 server.
Step 3: Run the Ansible Playbook

Execute the Ansible playbook to install RKE2 server:

bash

ansible-playbook -i inventory.ini rke-server

The playbook will add the RKE2 repository's GPG key, add the RKE2 APT repository, update the APT cache, install the RKE2 server package, start the RKE2 service, and enable it to start on boot on the target hosts specified in the inventory file.
Conclusion

After completing the above steps, you should have RKE2 server installed and running on your Ubuntu target hosts. You can now use RKE2 to manage Kubernetes clusters and deploy containerized applications.

Always ensure to review the playbook and customize it based on your specific requirements and environment. Additionally, make sure you have proper SSH access and permissions to execute the tasks on the target hosts.
