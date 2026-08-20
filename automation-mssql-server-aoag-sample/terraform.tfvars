compartment_id     = "ocid1.compartment.oc1..aaaaaaaac7ixtdbw32dnr55p4mjsjdmtbfcy5pa5rasdvuw57eup5w7xbu3q"
oci_config_profile = "DEFAULT"
region             = "us-sanjose-1"
windows_image_ocid = "ocid1.image.oc1.us-sanjose-1.aaaaaaaak2hpkzblpxpmdezybtadyswgbkp7dus5yki55pv5uu4gfutupefa"
# Leave ADs empty to select AD-1 for DC/SQL1 and AD-2 for SQL2 when available.
dc_availability_domain   = ""
sql1_availability_domain = ""
sql2_availability_domain = ""

# Current San Jose lab shape.
shape                       = "VM.Standard.E5.Flex"
ocpus                       = 6
memory_in_gbs               = 16
sql_ocpus                   = 8
sql_memory_in_gbs           = 32
boot_volume_size_in_gbs     = 100
sql_data_volume_size_in_gbs = 100
sql_data_drive_letter       = "F"

# Current lab public access posture.
dc_rdp_source_cidr  = "0.0.0.0/0"
sql_rdp_source_cidr = "0.0.0.0/0"

domain_name         = "mssqlaoag.demo"
domain_netbios_name = "MSSQLAOAG"
domain_admin_user   = "domainadmin"

# Keep the password out of this file for testing:
# export TF_VAR_domain_admin_password='<domainadmin password>'
auto_configure_domain_controller = true
