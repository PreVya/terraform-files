provider "aws" {
  region = var.region
  access_key = var.access_key
  secret_key = var.secret_key
}

data "aws_availability_zones" "available" {}
data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

#VPC
resource "aws_vpc" "main_vpc" {
    cidr_block = "10.0.0.0/16"
    tags = { Name = "main-vpc" }
}

#Subnets
resource "aws_subnet" "public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.main_vpc.cidr_block, 4, count.index)
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = { Name = "Public-subnet-${count.index}" }
}

resource "aws_subnet" "private_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.main_vpc.cidr_block, 4, count.index + 2)
  map_public_ip_on_launch = false
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = { Name = "Private-subnet-${count.index}" }
}

#IGW
resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.main_vpc.id
    tags = { Name = "IGW" }
}

#EIP and NAT
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = {
    Name = "nat-eip"
  }
}
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet[0].id

  tags = {
    Name = "nat-gateway"
  }
}

#Route and route table
resource "aws_route_table" "public_route" {
  vpc_id = aws_vpc.main_vpc.id
  tags   = { Name = "Public-Route" }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public_route.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route.id
}

# Private route table
resource "aws_route_table" "private_route" {
  vpc_id = aws_vpc.main_vpc.id
  tags   = { Name = "Private-Route" }
}

resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private_route.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private_subnet)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route.id
}

#Security group
resource "aws_security_group" "security_grp" {
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "ecs-sg"}
}

#ECS cluster
resource "aws_ecs_cluster" "main_cluster" {
  name = "ecs-cluster"
  tags = { Name = "ecs-cluster" } 
}

locals {
  flask_backend_url = "http://${aws_lb.main_lb.dns_name}:5000"
}

#Task definitions
resource "aws_ecs_task_definition" "flask" {
  family                   = "flask-task"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn = data.aws_iam_role.ecs_task_execution_role.arn


  container_definitions = jsonencode([
    {
      name      = "flask-backend"
      image     = "${aws_ecr_repository.flask_repo.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/flask-task"
          awslogs-region        = "ap-south-1"
          awslogs-stream-prefix = "ecs"
        }
      }
      environment = [
        {
          name  = "PORT"
          value = "5000"
        },
        {
          name  = "MONGO_URL"
          value = var.db_url
        }
      ]
    }
  ])
}


resource "aws_ecs_task_definition" "express" {
  family                   = "express-task"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn = data.aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "express-frontend"
      image     = "${aws_ecr_repository.express_repo.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
        }
      ]
      environment = [
        {
          name  = "PORT"
          value = "3000"
        },
        {
          name  = "BACKEND_URL"
          value = "http://${aws_lb.main_lb.dns_name}:5000"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/express-task"
          awslogs-region        = "ap-south-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}


#ALB
resource "aws_lb" "main_lb" {
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.security_grp.id]
  subnets            = aws_subnet.public_subnet[*].id
  tags = { Name = "main-alb"}
}

resource "aws_lb_target_group" "flask_lb" {
  name     = "flask-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main_vpc.id
  target_type = "ip" 
  health_check {
  path                = "/health"
  interval            = 30
  timeout             = 5
  healthy_threshold   = 2
  unhealthy_threshold = 5
  matcher             = "200-499"
}
}

resource "aws_lb_listener" "flask_listener" {
  load_balancer_arn = aws_lb.main_lb.arn
  port              = 5000
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.flask_lb.arn
  }
}

resource "aws_lb_target_group" "express_lb" {
  name        = "express-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main_vpc.id
  target_type = "ip"
  health_check {
  path                = "/health"
  interval            = 30
  timeout             = 5
  healthy_threshold   = 2
  unhealthy_threshold = 5
  matcher             = "200-499"
}
}

resource "aws_lb_listener" "express_listener" {
  load_balancer_arn = aws_lb.main_lb.arn
  port              = 3000
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.express_lb.arn
  }
}

#ECR Repositories
resource "aws_ecr_repository" "flask_repo" {
  name = "flask-repo"
  tags = { Name = "Flask-ECR" }
}

resource "aws_ecr_repository" "express_repo" {
  name = "express-repo"
  tags = { Name = "Express-ECR" }
}


#ECS
resource "aws_ecs_service" "flask_ecs" {
  name = "Flask_ecs"
  cluster         = aws_ecs_cluster.main_cluster.id
  task_definition = aws_ecs_task_definition.flask.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.private_subnet[*].id
    assign_public_ip = false
    security_groups = [aws_security_group.security_grp.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.flask_lb.arn
    container_name   = "flask-backend"
    container_port   = 5000
  }
  tags = { Name = "flask-service" }
  depends_on = [aws_lb_listener.flask_listener]  
}

resource "aws_ecs_service" "express_ecs" {
  name            = "Express_ecs"
  cluster         = aws_ecs_cluster.main_cluster.id
  task_definition = aws_ecs_task_definition.express.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private_subnet[*].id
    assign_public_ip = false
    security_groups  = [aws_security_group.security_grp.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.express_lb.arn
    container_name   = "express-frontend"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.express_listener]
  tags       = { Name = "express-service" }
}

resource "aws_cloudwatch_log_group" "flask_logs" {
  name              = "/ecs/flask-task"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "express_logs" {
  name              = "/ecs/express-task"
  retention_in_days = 7
}
