variable "AUTHOR" {

}

variable "DOCKER_COMPOSE_VERSION" {
  default = "2.19.0"
}

variable "DOMAIN_NAME" {

}

variable "EC2_VOLUME_IMAGE" {
  default = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

variable "INSTANCE_TYPE" {
  default = "m6a.large"
}

variable "JAVA_VERSION" {
  default = "java20"
}

variable "MEMORY_SIZE" {
  default = "6G"
}

variable "MINECRAFT_VERSION" {
  default = "1.20.1"
}

variable "REGION" {
  default = "ap-northeast-1"
}

variable "SERVER_CONTAINER_NAME" {
  default = "mc_server"
}

variable "BACKUP_CONTAINER_NAME" {
  default = "mc_backupper"
}

variable "SERVER_NAME" {
  default = "minecraft"
}

variable "TIME_ZONE" {
  default = "Asia/Tokyo"
}

variable "WORLD_SEED" {
  default = "0"
}
