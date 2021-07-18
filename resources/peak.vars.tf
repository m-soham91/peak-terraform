############# Variable Def for peak ##################
variable "peak_cidr" {
  description = "The CIDR block for the VPC."
}
variable "peak_public_subnets" {
  description = "Comma separated list of public subnets"
}
variable "peak_private_subnets" {
  description = "Comma separated list of public subnets"
}
variable "peak_name" {
  description = "Name tag, e.g stack"
  default     = "peak"
}
variable "peak_tag_purpose" {
}
variable "peak_root_volume_size" {
}
variable "peak_root_volume_type" {
}
variable "peak_image" {
}
variable "peak_type" {
}
variable "peak_region" {
}