output "AUTHOR" {
  value = var.AUTHOR
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

output "BACKUP_CONTAINER_NAME" {
  value = var.BACKUP_CONTAINER_NAME
}

output "SERVER_NAME" {
  value = var.SERVER_NAME
}

output "SUB_DOMAIN_NAME" {
  value = "${var.SERVER_NAME}.${var.DOMAIN_NAME}"
}

output "TIME_ZONE" {
  value = var.TIME_ZONE
}

output "WORLD_SEED" {
  value = var.WORLD_SEED
}
