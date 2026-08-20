data "oci_core_vnic_attachments" "sql1" {
  compartment_id = var.compartment_id
  instance_id    = oci_core_instance.sql1.id

  depends_on = [oci_core_instance.sql1]
}

data "oci_core_vnic_attachments" "sql2" {
  compartment_id = var.compartment_id
  instance_id    = oci_core_instance.sql2.id

  depends_on = [oci_core_instance.sql2]
}

locals {
  sql1_primary_vnic_id = one(data.oci_core_vnic_attachments.sql1.vnic_attachments[*].vnic_id)
  sql2_primary_vnic_id = one(data.oci_core_vnic_attachments.sql2.vnic_attachments[*].vnic_id)
}

resource "oci_core_private_ip" "sql1_wsfc" {
  display_name = "sqlag-wsfc-sql1"
  ip_address   = var.wsfc_cluster_ip_sql1
  vnic_id      = local.sql1_primary_vnic_id

  lifecycle {
    replace_triggered_by = [oci_core_instance.sql1]
  }
}

resource "oci_core_private_ip" "sql2_wsfc" {
  display_name = "sqlag-wsfc-sql2"
  ip_address   = var.wsfc_cluster_ip_sql2
  vnic_id      = local.sql2_primary_vnic_id

  lifecycle {
    replace_triggered_by = [oci_core_instance.sql2]
  }
}

resource "oci_core_private_ip" "sql1_agdemodb1" {
  display_name = "sqlag-agdemodb1-sql1"
  ip_address   = var.aoag_listener_ip_sql1
  vnic_id      = local.sql1_primary_vnic_id

  lifecycle {
    replace_triggered_by = [oci_core_instance.sql1]
  }
}

resource "oci_core_private_ip" "sql2_agdemodb1" {
  display_name = "sqlag-agdemodb1-sql2"
  ip_address   = var.aoag_listener_ip_sql2
  vnic_id      = local.sql2_primary_vnic_id

  lifecycle {
    replace_triggered_by = [oci_core_instance.sql2]
  }
}

resource "oci_core_private_ip" "sql1_agdemodb2" {
  display_name = "sqlag-agdemodb2-sql1"
  ip_address   = cidrhost(var.sql1_subnet_cidr, 31)
  vnic_id      = local.sql1_primary_vnic_id

  lifecycle {
    replace_triggered_by = [oci_core_instance.sql1]
  }
}

resource "oci_core_private_ip" "sql2_agdemodb2" {
  display_name = "sqlag-agdemodb2-sql2"
  ip_address   = cidrhost(var.sql2_subnet_cidr, 31)
  vnic_id      = local.sql2_primary_vnic_id

  lifecycle {
    replace_triggered_by = [oci_core_instance.sql2]
  }
}
