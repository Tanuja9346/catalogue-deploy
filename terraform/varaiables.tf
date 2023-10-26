variable "project_name" {
  default = "roboshop"
}

variable "env" {
  default = "dev"
}

variable "common_tags" {
  default = {
    Project = "roboshop"
    Component = "catalogue"
    Environment = "DEV"
    Terraform = "true"
  }
}
variable "domain_name" {
  default = "joindevops.xyz"
}
variable "app_version" {
  #this is just test variable is flowing from terraform to shell and shell to ansible
  default = "100.100.100"
}