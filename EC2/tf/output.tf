output "AUTHOR" {
  value = var.AUTHOR
}

output "EC2_INSTANCE_ID" {
  value = aws_instance.minecraft.id
}

output "JAVA_VERSION" {
  value = var.JAVA_VERSION
}

output "MEMORY_SIZE" {
  value = var.MEMORY_SIZE
}

output "MINECRAFT_VERSION" {
  value = var.MINECRAFT_VERSION
}

output "PUBLIC_IP" {
  value = aws_instance.minecraft.public_ip
}

output "REGION" {
  value = var.REGION
}

output "SERVER_CONTAINER_NAME" {
  value = var.SERVER_CONTAINER_NAME
}

output "SERVER_NAME" {
  value = var.SERVER_NAME
}

output "SUB_DOMAIN_NAME" {
  value = aws_route53_record.subdomain_route.name
}

output "TIME_ZONE" {
  value = var.TIME_ZONE
}

output "WORLD_SEED" {
  value = var.WORLD_SEED
}
