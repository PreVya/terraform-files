provider "aws" {
  region = var.region
  access_key = var.access_key
  secret_key = var.secret_key
}

#Security group for frontend
resource aws_security_group "sg_fe" {
    name = "Frontend_security_group"
    description = "Allow SSH, Express (3000)"

    ingress{
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress{
        from_port = 3000
        to_port = 3000
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

#Security group for backend
resource aws_security_group "sg_be" {
    name = "Backend_security_group"
    description = "Allow SSH, Flask (5000)"

    ingress{
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress{
        from_port = 5000
        to_port = 5000
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

#S3bucket for storing backend env
resource "aws_s3_bucket" "backend_env_bucket"{
    bucket = "my-s3-bucker-for-backend-env-12345"
    tags = {
        Name = "ENVBUCKET"
    }

}
#Copy env file to the bucket
resource "aws_s3_object" "env_file"{
    bucket = aws_s3_bucket.backend_env_bucket.bucket
    key = "flask.env"
    source = "${path.module}/../../terraform1/flask-backend/flask.env"
}

#new role and policy
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
      Resource = "${aws_s3_bucket.backend_env_bucket.arn}/*"
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

#EC2 instance for backend
resource "aws_instance" "flask_backend" {
  ami = var.ami
  instance_type = "t3.micro"
  key_name = var.key_name
  security_groups = [aws_security_group.sg_be.name]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  
   user_data = templatefile("${path.module}/setup_be.sh", {
    S3_BUCKET = aws_s3_bucket.backend_env_bucket.bucket
  })
  tags = {
    Name = "Flask-Server"
  }
}

#EC2 instance for frontend
resource "aws_instance" "express_frontend" {
  ami = var.ami
  instance_type = "t3.micro"
  key_name = var.key_name
  security_groups = [aws_security_group.sg_fe.name]
  depends_on = [aws_instance.flask_backend]
  
   user_data = templatefile("${path.module}/setup_fe.sh", {
  BACKEND_IP = aws_instance.flask_backend.public_ip
})
  tags = {
    Name = "Express-Server"
  }
}