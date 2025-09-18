# RDS Subnet Group
resource "aws_db_subnet_group" "db_group" {
  name       = "db-subnet-group"
  subnet_ids = [aws_subnet.private_db.id, aws_subnet.private_db_eu_central_1b.id]
  tags = {
    Name = "db-subnet-group"
  }
}

# Second Private DB Subnet in eu-central-1b
resource "aws_subnet" "private_db_eu_central_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "eu-central-1b"
  tags = {
    Name = "private-db-subnet-eu-central-1b"
  }
}

# RDS MySQL Instance
resource "aws_db_instance" "mysql" {
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "ticketdb"
  username               = "admin"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.db_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  publicly_accessible    = false
  tags = {
    Name = "ticket-db"
  }
}