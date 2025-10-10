provider "aws" {
  region = var.region
  access_key = var.access_key
  secret_key = var.secret_key
}

# Security Group
resource "aws_security_group" "app_sg" {
  name        = "flask-express-sg"
  description = "Allow SSH, Flask (5000), Express (3000)"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#S3 bucket to store env files
resource "aws_s3_bucket" "env_bucket" {
  bucket = "my-app-env-bucket-1234"
  acl    = "private"

  tags = {
    Name = "AppEnvBucket"
  }
}

#Copy env files to s3
resource "aws_s3_object" "flask_env" {
  bucket = aws_s3_bucket.env_bucket.bucket
  key    = "flask.env"
  source = "${path.module}/../flask-backend/flask.env"   
}

# IAM Role + Instance Profile for EC2 to access S3
resource "aws_iam_role" "ec2_role" {
  name = "ec2-env-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "s3_read_policy" {
  name        = "s3-read-env-policy"
  description = "Allow EC2 to read .env files from S3"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.env_bucket.arn}/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_read_policy.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-env-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# EC2 Instance
resource "aws_instance" "flask_express" {
  ami = var.ami
  instance_type = "t3.micro"
  key_name = var.key_name
  security_groups = [aws_security_group.app_sg.name]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  
   user_data = templatefile("${path.module}/setup.sh", {
    S3_BUCKET = aws_s3_bucket.env_bucket.bucket
  })
  tags = {
    Name = "Flask-Express-Server"
  }
}