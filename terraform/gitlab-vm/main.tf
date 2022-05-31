data "sops_file" "secrets" {
  source_file = "secret.sops.yaml"
}

data "local_file" "public_key" {
  filename = data.sops_file.secrets.data["gitlab_vm_ssh_pub_key_file"]
}

#################
#   Resources   #
#################
# Terraform docs: https://www.terraform.io/cli
# Proxmox docs: https://registry.terraform.io/providers/Telmate/proxmox/latest/docs
# Proxmox docs qemu: https://registry.terraform.io/providers/Telmate/proxmox/latest/docs/resources/vm_qemu
# Useful article: https://austinsnerdythings.com/2021/09/01/how-to-deploy-vms-in-proxmox-with-terraform/

terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.9.10"
    }
    sops = {
      source  = "carlpett/sops"
      version = "0.7.1"
    }
  }
}

# Providers are what we are provisioning to. This can be something AWS, Azure,
# ect. In our case we're using Proxmox installed by the above provider plugin.
provider "proxmox" {
  pm_api_url          = data.sops_file.secrets.data["gitlab_vm_proxmox_url"]
  pm_api_token_id     = data.sops_file.secrets.data["gitlab_vm_proxmox_api_token_id"]
  pm_api_token_secret = data.sops_file.secrets.data["gitlab_vm_proxmox_api_token_secret"]
  pm_parallel         = 2
  pm_timeout          = 600
  pm_tls_insecure     = true
#  pm_debug            = true
#  pm_log_enable       = true
#  pm_log_file         = "terraform-plugin-proxmox.log"
#  pm_log_levels = {
#    _default    = "debug"
#    _capturelog = ""
#  }
}
 # Resources are the actual machines we're spinning up. It's in a format of
# <resource-type> <entity>. In our case we're using the type of
# "proxmox_vm_qemu" from the proxmox provider and naming it "k3s_masters"

resource "proxmox_vm_qemu" "gitlab" {
  count       = data.sops_file.secrets.data["gitlab_vm_node_count"]
  name        = "${data.sops_file.secrets.data["gitlab_vm_node_name_prefix"]}${count.index + 1}"
  vmid        = "${data.sops_file.secrets.data["gitlab_vm_node_vmid_prefix"]}${count.index + 1}"
  target_node = data.sops_file.secrets.data["gitlab_vm_proxmox_node"]
  clone       = data.sops_file.secrets.data["gitlab_vm_clone_template_name"]
  full_clone  = false

  # basic VM settings here. agent refers to guest agent
  agent      = 1
  os_type    = "cloud-init"
  ci_wait    = 300
  ciuser     = data.sops_file.secrets.data["gitlab_vm_proxmox_vm_user"]
  cipassword = data.sops_file.secrets.data["gitlab_vm_proxmox_vm_password"]
  cores      = 4
  sockets    = 1
  cpu        = "kvm64"
  memory     = 16384
  scsihw     = "virtio-scsi-pci"
  onboot     = true
  bootdisk   = "virtio0"

  disk {
    slot = 0
    # set disk size here. leave it small for testing because expanding the disk takes time.
    size     = "102400M"
    type     = "virtio"
    storage  = data.sops_file.secrets.data["gitlab_vm_node_storage"]
    iothread = 1
  }

  # if you want two NICs, just copy this whole network section and duplicate it
  network {
    model  = "virtio"
    bridge = "vmbr1"
  }

  # not sure exactly what this is for. presumably something about MAC addresses and ignore network changes during the life of
  lifecycle {
    ignore_changes = [
      network,
    ]
  }

  # the ${count.index + 1} thing appends text to the end of the ip address
  # in this case, since we are only adding a single VM, the IP will
  # be 10.98.1.91 since count.index starts at 0. this is how you can create
  # multiple VMs and have an IP assigned to each (.91, .92, .93, etc.)
  ipconfig0 = "ip=${data.sops_file.secrets.data["gitlab_vm_node_ip"]}${count.index +1}${data.sops_file.secrets.data["gitlab_vm_node_subnet_mask"]},gw=${data.sops_file.secrets.data["gitlab_vm_node_gateway"]}"

  # sshkeys set using variables. the variable contains the text of the key.
  sshkeys = <<EOF
    ${data.local_file.public_key.content}
  EOF
}
