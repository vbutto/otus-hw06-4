# Роли сервисного аккаунта для terraform
# iam.serviceAccounts.admin - для создания сервисных аккаунтов
# container-registry.admin - для создания реестра и назначения прав
# vpc.publicAdmin - для создания VPC-сети и подсети
# vpc.privateAdmin - для создания VPC-сети и подсети
# vpc.user
# vpc.securityGroups.admin - для создания security group
# compute.admin - для создания группы ВМ
# k8s.admin - для создания кластера k8s


# ---------------------- Поиск существующего реестра YCR --------------------
data "yandex_container_registry" "cr" {
  name      = "hw06-cr-demo"
  folder_id = var.folder_id
}

# ---------------------- Сеть и подсети --------------------
resource "yandex_vpc_network" "hw06_mk8s_vpc" {
  name = "hw06-mk8s-vpc"
}

resource "yandex_vpc_subnet" "hw06_mk8s_subnet_a" {
  name           = "hw06-mk8s-subnet-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.hw06_mk8s_vpc.id
  v4_cidr_blocks = ["10.90.1.0/24"]
}

resource "yandex_vpc_subnet" "hw06_mk8s_subnet_b" {
  name           = "hw06-mk8s-subnet-b"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.hw06_mk8s_vpc.id
  v4_cidr_blocks = ["10.90.2.0/24"]
}

# ---------------------- Сервисные аккаунты --------------------
resource "yandex_iam_service_account" "hw06_mk8s_sa_master" {
  name = "hw06-mk8s-master-sa"
}

resource "yandex_iam_service_account" "hw06_mk8s_sa_nodes" {
  name = "hw06-mk8s-nodes-sa"
}

# ---------------------- Роли для мастер-SA --------------------
resource "yandex_resourcemanager_folder_iam_member" "hw06_mk8s_sa_master_k8s_agent" {
  folder_id = var.folder_id
  role      = "k8s.clusters.agent"
  member    = "serviceAccount:${yandex_iam_service_account.hw06_mk8s_sa_master.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "hw06_mk8s_sa_master_vpc_public_admin" {
  folder_id = var.folder_id
  role      = "vpc.publicAdmin"
  member    = "serviceAccount:${yandex_iam_service_account.hw06_mk8s_sa_master.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "hw06_mk8s_sa_master_lb_admin" {
  folder_id = var.folder_id
  role      = "load-balancer.admin"
  member    = "serviceAccount:${yandex_iam_service_account.hw06_mk8s_sa_master.id}"
}

# ---------------------- Роли для node-SA --------------------
resource "yandex_container_registry_iam_binding" "hw06_mk8s_nodes_puller_on_registry" {
  registry_id = data.yandex_container_registry.cr.id
  role        = "container-registry.images.puller"
  members     = ["serviceAccount:${yandex_iam_service_account.hw06_mk8s_sa_nodes.id}"]
}

# ---------------------- Кластер Kubernetes --------------------
resource "yandex_kubernetes_cluster" "hw06_mk8s_cluster" {
  name       = "hw06-mk8s-cluster"
  folder_id  = var.folder_id
  network_id = yandex_vpc_network.hw06_mk8s_vpc.id

  master {
    version = "1.32"

    zonal {
      zone      = var.zone
      subnet_id = yandex_vpc_subnet.hw06_mk8s_subnet_a.id
    }

    public_ip = true
  }

  service_account_id      = yandex_iam_service_account.hw06_mk8s_sa_master.id
  node_service_account_id = yandex_iam_service_account.hw06_mk8s_sa_nodes.id

  release_channel         = "REGULAR"
  network_policy_provider = "CALICO"

  cluster_ipv4_range = "10.96.0.0/16"
  service_ipv4_range = "10.97.0.0/16"

  labels = {
    env   = "demo"
    owner = "terraform"
  }

  depends_on = [
    yandex_resourcemanager_folder_iam_member.hw06_mk8s_sa_master_k8s_agent,
    yandex_resourcemanager_folder_iam_member.hw06_mk8s_sa_master_vpc_public_admin,
    yandex_resourcemanager_folder_iam_member.hw06_mk8s_sa_master_lb_admin,
    yandex_container_registry_iam_binding.hw06_mk8s_nodes_puller_on_registry,
  ]
}

# ---------------------- Группа узлов --------------------
resource "yandex_kubernetes_node_group" "hw06_mk8s_nodes" {
  name       = "hw06-mk8s-nodes"
  cluster_id = yandex_kubernetes_cluster.hw06_mk8s_cluster.id

  scale_policy {
    fixed_scale {
      size = 2
    }
  }

  allocation_policy {
    location { zone = var.zone }
  }

  instance_template {
    platform_id = "standard-v2"

    resources {
      cores         = 2
      memory        = 2
      core_fraction = 20
    }

    boot_disk {
      type = "network-hdd"
      size = 20
    }

    network_interface {
      subnet_ids = [yandex_vpc_subnet.hw06_mk8s_subnet_a.id]
      nat        = true
    }

    scheduling_policy {
      preemptible = true
    }

    metadata = {
      "ssh-keys" = "ubuntu:ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEIwAhe9IhThZ8Ed/bZ6h/3CPfX4hhh3DppnRFCadA6L slava.butyrkin@gmail.com"
    }
  }

  maintenance_policy {
    auto_repair  = true
    auto_upgrade = true
  }

  labels = {
    role  = "app"
    infra = "yc"
  }

  node_taints = []
}

# ---------------------- Outputs --------------------
output "cluster_id" {
  value = yandex_kubernetes_cluster.hw06_mk8s_cluster.id
}

output "cluster_name" {
  value = yandex_kubernetes_cluster.hw06_mk8s_cluster.name
}

output "node_group_id" {
  value = yandex_kubernetes_node_group.hw06_mk8s_nodes.id
}

output "kubeconfig_hint" {
  description = "Команда для получения kubeconfig"
  value       = "yc managed-kubernetes cluster get-credentials ${yandex_kubernetes_cluster.hw06_mk8s_cluster.name} --external --force"
}
