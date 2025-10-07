terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

provider "google" {
  project = "prime-bridge-455802-f4"
  region  = "us-central1"
}

###### Criando a VPC e Sub-rede ######
resource "google_compute_network" "vpc_network" {
  name                    = "gke-vpc"
  auto_create_subnetworks = false
}

# HABILITAMOS O ACESSO PRIVADO NA SUB-REDE PARA O NAT FUNCIONAR
resource "google_compute_subnetwork" "gke_subnet" {
  name                     = "gke-subnet"
  ip_cidr_range            = "10.10.1.0/24"
  region                   = "us-central1"
  network                  = google_compute_network.vpc_network.id
  private_ip_google_access = true # <-- ADIÇÃO IMPORTANTE
}

###### Criando o Cloud NAT para acesso à internet ######
resource "google_compute_router" "router" {
  name    = "gke-nat-router"
  network = google_compute_network.vpc_network.id
  region  = google_compute_subnetwork.gke_subnet.region
}

resource "google_compute_router_nat" "nat" {
  name                               = "gke-nat-gateway"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
  subnetwork {
    name                    = google_compute_subnetwork.gke_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

###### Criando o Artifact Registry #######
resource "google_artifact_registry_repository" "my_repo" {
  provider      = google
  location      = "us-central1"
  repository_id = "python-app" # <-- Este é o nome que o pipeline está esperando
  description   = "Repositório Docker para a aplicação python-app"
  format        = "DOCKER"
}

###### Criando o cluster GKE PRIVADO ######
resource "google_container_cluster" "primary_cluster" {
  name     = "primary-gke-cluster"
  location = "us-central1-f"
  network  = google_compute_network.vpc_network.name
  subnetwork = google_compute_subnetwork.gke_subnet.name

  # CONFIGURAÇÃO PARA CLUSTER PRIVADO
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # Mantemos o endpoint de controle público para facilitar o acesso com kubectl
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  node_pool {
    name       = "primary-node-pool"
    node_count = 2

    node_config {
      machine_type = "e2-medium"
      disk_size_gb = 30

      oauth_scopes = [
        "https://www.googleapis.com/auth/cloud-platform",
      ]
    }
  }
}