# Create network
resource "google_compute_network" "my_network" {
  name                    = "portfolio-network"
  auto_create_subnetworks = false
}

# Create subnet
resource "google_compute_subnetwork" "subnet_us" {
  name          = "subnet-usa"
  ip_cidr_range = "10.0.0.0/28"
  network       = google_compute_network.my_network.self_link
  region        = "us-central1"

}
resource "google_compute_subnetwork" "subnet_asia" {
  name          = "subnet-asia"
  ip_cidr_range = "192.168.0.0/28"
  network       = google_compute_network.my_network.self_link
  region        = "asia-south2"

}
# creating the nat routers
#creating the nat routers
resource "google_compute_router" "router-us" {
  name    = "router-us"
  region  = google_compute_subnetwork.subnet_us.region
  network = google_compute_network.my_network.id

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "nat-us" {
  name                               = "router-nat-us"
  router                             = google_compute_router.router-us.name
  region                             = google_compute_router.router-us.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_PRIMARY_IP_RANGES"

  log_config {
    enable = true
    filter = "ALL"
  }
}
resource "google_compute_router" "router-asia" {
  name    = "router-asia"
  region  = google_compute_subnetwork.subnet_asia.region
  network = google_compute_network.my_network.id

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "nat-asia" {
  name                               = "router-nat-asia"
  router                             = google_compute_router.router-asia.name
  region                             = google_compute_router.router-asia.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_PRIMARY_IP_RANGES"

  log_config {
    enable = true
    filter = "ALL"
  }
}

# CREATING FIREWALL-RULES 
resource "google_compute_firewall" "allow-lb-check" {
  name     = "allow-lb-health-check"
  network=google_compute_network.my_network.self_link
  priority = 1000
  allow {
    protocol = "tcp"
    ports    = [80, 8080, 443]
  }
  target_tags   = ["allow-lb-health-check"]
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
}
resource "google_compute_firewall" "allow-ssh" {
  name     = "allow-ssh"
  network=google_compute_network.my_network.self_link
  priority = 1000
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]

}
#ubuntu disk image
data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}
# service account
resource "google_service_account" "compute-sa" {
  account_id   = "compute-sa"
  display_name = "My Service Account"
}
resource "google_project_iam_binding" "storage_admin_binding" {
  project= "${var.PROJECT_ID}"
  role    = "roles/storage.admin"

  members = [
    "serviceAccount:${google_service_account.compute-sa.email}"
  ]
}


#instance template 
resource "google_compute_instance_template" "template-portfolio-us" {
 
  tags         = ["http-server", "allow-lb-health-check"]
  name         = "template-us"
  machine_type = "e2-standard-2"
  region       = "us-central1"
  disk {
    source_image = data.google_compute_image.ubuntu.self_link
    auto_delete  = true
    boot         = true
    disk_type    = "pd-standard"
    disk_size_gb = 30

  }
   service_account {
    email  = google_service_account.compute-sa.email
  scopes = ["cloud-platform"]
  }
  network_interface {
    network = google_compute_network.my_network.id

    subnetwork = google_compute_subnetwork.subnet_us.self_link
  }
  metadata_startup_script = file("${path.cwd}/../scripts/startup-script.sh")

}
resource "google_compute_instance_template" "template-portfolio-asia" {
 
  tags         = ["http-server", "allow-lb-health-check"]
  name         = "template-asia"
  machine_type = "e2-standard-2"
  region       = "asia-south2"
  disk {
    source_image = data.google_compute_image.ubuntu.self_link
    auto_delete  = true
    boot         = true
    disk_type    = "pd-standard"
    disk_size_gb = 30

  }
  service_account {
    email  = google_service_account.compute-sa.email
       scopes = ["cloud-platform"]
  }
  network_interface {
    network = google_compute_network.my_network.id

    subnetwork = google_compute_subnetwork.subnet_asia.self_link
  }
  metadata_startup_script = file("${path.cwd}/../scripts/startup-script.sh")

}
resource "google_compute_health_check" "autohealing-us" {
  name                = "autohealing-health-check-us"
 
  timeout_sec        = 1
  check_interval_sec = 1

  tcp_health_check {
    port = "80"
  }
}
resource "google_compute_health_check" "autohealing-asia" {
  name                = "autohealing-health-check-asia"
   timeout_sec        = 1
  check_interval_sec = 1

  tcp_health_check {
    port = "80"
  }
}

resource "google_compute_health_check" "autohealing-backend-service" {
  name                = "autohealing-health-check-bs"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 10 # 50 seconds
tcp_health_check {
    port = "80"
  }
  
}
resource "google_compute_region_instance_group_manager" "mig-us" {
  name                      = "mig-backend-us"
  region="us-central1"
  base_instance_name        = "portfolio-us"
  distribution_policy_zones = ["us-central1-a", "us-central1-f"]
  version {
    instance_template = google_compute_instance_template.template-portfolio-us.self_link_unique
  }
  target_size = 2

  named_port {
    name = "http"
    port = 80
  }
  auto_healing_policies {
    health_check      = google_compute_health_check.autohealing-us.id
    initial_delay_sec = 300
  }
  wait_for_instances = true

}
resource "google_compute_region_instance_group_manager" "mig-asia" {
  name                      = "mig-backend-asia"
  region="asia-south2"
  base_instance_name        = "portfolio-asia"
  distribution_policy_zones = ["asia-south2-a", "asia-south2-b"]
  version {
    instance_template = google_compute_instance_template.template-portfolio-asia.self_link_unique
  }
  target_size = 2

  named_port {
    name = "http"
    port = 80
  }
  auto_healing_policies {
    health_check      = google_compute_health_check.autohealing-asia.id
    initial_delay_sec = 300
  }
  wait_for_instances = true

}
# backend-services
resource "google_compute_backend_service" "backend-service" {
  name               = "backend-service"
  description        = "GLOBAL BACKEND SERVICE TO MANAGE BACKEND MIGS IN US"

  port_name="http"
  backend {
    group = google_compute_region_instance_group_manager.mig-us.instance_group
  }
  backend {
    group= google_compute_region_instance_group_manager.mig-asia.instance_group
  }
  health_checks = [google_compute_health_check.autohealing-backend-service.id]
}
#url-maps
resource "google_compute_url_map" "default" {
  name            = "urlmap"
  description     = "default  url map"
  default_service = google_compute_backend_service.backend-service.id
}
# target-http-proxy
resource "google_compute_target_http_proxy" "default" {
  name    = "target-proxy-portfolio"
  url_map = google_compute_url_map.default.id
}
# forwarding rules
resource "google_compute_global_forwarding_rule" "frontend-lb-portfolio" {
  name       = "frontend-global"
  target     = google_compute_target_http_proxy.default.id
  port_range = "80"
}
output "lb-ip"{
    value="${google_compute_global_forwarding_rule.frontend-lb-portfolio.ip_address}"
}
