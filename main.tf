data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "all" {
  vpc_id = data.aws_vpc.default.id
}

locals {
  ansible_ssh_suffix = " ansible_ssh_user=ec2-user ansible_connection=ssh ansible_ssh_private_key_file=server.key\n"
}

data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name = "name"

    values = [
      "amzn-ami-hvm-*-x86_64-gp2",
    ]
  }

  filter {
    name = "owner-alias"

    values = [
      "amazon",
    ]
  }
  owners = ["amazon"]
}

module "security_group" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "scrapy-cluster-sg"
  description = "Security group for cluster worker node."
  vpc_id      = data.aws_vpc.default.id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["ssh-tcp", "redis-tcp", "all-icmp"]
  egress_rules        = ["all-all"]
}

resource "tls_private_key" "this" {
  algorithm = "RSA"
}

module "key_pair" {
  source = "terraform-aws-modules/key-pair/aws"

  key_name   = "scrapy-cluster-key"
  public_key = tls_private_key.this.public_key_openssh
}

module "ec2" {
  source = "github.com/terraform-aws-modules/terraform-aws-ec2-instance"

  instance_count = var.instances_number

  name                        = "scrapy-cluster-node"
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = tolist(data.aws_subnet_ids.all.ids)[0]
  vpc_security_group_ids      = [module.security_group.this_security_group_id]
  associate_public_ip_address = true
  root_block_device           = [{ delete_on_termination = true, volume_size = 30 }]
  key_name                    = module.key_pair.this_key_pair_key_name

}

###################################
# Save ssh private and public key in file
###################################
resource "local_file" "private_key" {
  filename = "server.key"
  content  = tls_private_key.this.private_key_pem
  file_permission = "0400"

}
###################################
# Generate .hosts file for ansible
###################################
resource "local_file" "hosts" {
  content = "[workers]\n${join(local.ansible_ssh_suffix, module.ec2.public_ip)} ${local.ansible_ssh_suffix}\n"
  filename = "${path.root}/.hosts"
}


