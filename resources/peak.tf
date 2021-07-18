
module "peak" {
  source              = "../modules/peak"
  name                = "${var.peak_name}"
  cidr                = "${var.peak_cidr}"
  public_subnets      = "${var.peak_public_subnets}"
  private_subnets     = "${var.peak_private_subnets}"
  tag_purpose         = "${var.peak_tag_purpose}"
  image               = "${var.peak_image}"
  root_volume_size    = "${var.peak_root_volume_size}"
  root_volume_type    = "${var.peak_root_volume_type}"
  type                = "${var.peak_type}"
  region              = "${var.peak_region}"
}