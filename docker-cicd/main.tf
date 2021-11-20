###########------ docker Server -----########
resource "aws_instance" "dockerserver" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.main-public-1.id
  key_name               = aws_key_pair.mykeypair.key_name
  vpc_security_group_ids = [aws_security_group.main-docker.id]
#   user_data              = file(templates/install.sh)
  tags = merge(local.common_tags,
    { Name = "docker-server"
  Application = "public" })
}