terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      version = "0.6.14"
    }
  }
}

provider "libvirt" {
    uri = "qemu+ssh://root@vms/system?keyfile=/home/mpetason/.ssh/id_ed25519"
}

# resource "libvirt_pool" "pf9vms" {
#   name = "pf9vms"
#   type = "dir"
#   path = "/data/pf9vms/"
# }

variable "amount" {
  type = number
  default = 1
}

resource "libvirt_volume" "pf9-vm" {
  count = var.amount
  name           = format("pf9-vm_%s", count.index)
  size           = 107374182400
  pool = "data"
  base_volume_id = libvirt_volume.ubuntu-img.id
}

resource "libvirt_volume" "ubuntu-img" {
  name   = "ubuntu-img"
  pool   = "data"
  # source = "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
  source = "focal-server-cloudimg-amd64.img"
  format = "qcow2"
}


data "template_file" "user_data" {
  template = file("${path.module}/cloud_init.cfg")
}

data "template_file" "network_config" {
  template = file("${path.module}/network.cfg")
}

# for more info about paramater check this out
# https://github.com/dmacvicar/terraform-provider-libvirt/blob/master/website/docs/r/cloudinit.html.markdown
# Use CloudInit to add our ssh-key to the instance
# you can add also meta_data field
resource "libvirt_cloudinit_disk" "commoninit" {
  name           = "commoninit.iso"
  user_data      = data.template_file.user_data.rendered
  network_config = data.template_file.network_config.rendered
  pool           = "data"
}

# Create the machine
resource "libvirt_domain" "pf9-vm" {
  count = var.amount
  name   = format("pf9-vm_%s", count.index)
  memory = "20000"
  vcpu   = 4
  qemu_agent = true

  cloudinit = libvirt_cloudinit_disk.commoninit.id

  network_interface {
    # network_name = "host-bridge"
    bridge = "br0"
    addresses = [format("192.168.86.7%s", count.index + 1)]
    wait_for_lease = "true"
  }

  # IMPORTANT: this is a known bug on cloud images, since they expect a console
  # we need to pass it
  # https://bugs.launchpad.net/cloud-images/+bug/1573095
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = libvirt_volume.pf9-vm[count.index].id
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

output "ip" {
    value = libvirt_domain.pf9-vm.*.network_interface.0.addresses
}
