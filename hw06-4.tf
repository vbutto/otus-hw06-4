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
  name        = "hw06-mk8s-vpc"
  description = "VPC for Managed Kubernetes cluster"
  folder_id   = var.folder_id

  labels = {
    project    = "hw06"
    managed_by = "terraform"
  }
}

resource "yandex_vpc_subnet" "hw06_mk8s_subnet_a" {
  name           = "hw06-mk8s-subnet-a"
  description    = "Subnet in zone A"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.hw06_mk8s_vpc.id
  v4_cidr_blocks = ["10.90.1.0/24"]

  labels = {
    project    = "hw06"
    managed_by = "terraform"
    zone       = "ru-central1-a"
  }
}

resource "yandex_vpc_subnet" "hw06_mk8s_subnet_b" {
  name           = "hw06-mk8s-subnet-b"
  description    = "Subnet in zone B"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.hw06_mk8s_vpc.id
  v4_cidr_blocks = ["10.90.2.0/24"]

  labels = {
    project    = "hw06"
    managed_by = "terraform"
    zone       = "ru-central1-b"
  }
}

# ---------------------- Сервисные аккаунты --------------------
resource "yandex_iam_service_account" "hw06_mk8s_sa_master" {
  name        = "hw06-mk8s-master-sa"
  description = "Service account for Kubernetes master"
  folder_id   = var.folder_id
}

resource "yandex_iam_service_account" "hw06_mk8s_sa_nodes" {
  name        = "hw06-mk8s-nodes-sa"
  description = "Service account for Kubernetes nodes"
  folder_id   = var.folder_id
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

resource "yandex_resourcemanager_folder_iam_member" "hw06_mk8s_sa_master_logging_writer" {
  folder_id = var.folder_id
  role      = "logging.writer"
  member    = "serviceAccount:${yandex_iam_service_account.hw06_mk8s_sa_master.id}"
}

# ---------------------- Роли для node-SA --------------------
resource "yandex_container_registry_iam_binding" "hw06_mk8s_nodes_puller_on_registry" {
  registry_id = data.yandex_container_registry.cr.id
  role        = "container-registry.images.puller"
  members     = ["serviceAccount:${yandex_iam_service_account.hw06_mk8s_sa_nodes.id}"]
}

# ---------------------- Security Group --------------------
resource "yandex_vpc_security_group" "hw06_mk8s_sg" {
  name        = "hw06-mk8s-sg"
  description = "Security Group for Managed K8s cluster"
  network_id  = yandex_vpc_network.hw06_mk8s_vpc.id
  folder_id   = var.folder_id

  labels = {
    project    = "hw06"
    managed_by = "terraform"
  }

  # Исходящий трафик - разрешаем всё
  egress {
    protocol       = "ANY"
    description    = "Allow all outbound traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = -1
  }

  # Внутренний трафик VPC
  ingress {
    protocol       = "ANY"
    description    = "Intra-VPC traffic"
    v4_cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
    port           = -1
  }

  # NodePort диапазон для LoadBalancer сервисов
  ingress {
    protocol       = "TCP"
    description    = "NodePort range for LoadBalancer services"
    from_port      = 30000
    to_port        = 32767
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Health checks от Yandex Load Balancer
  ingress {
    protocol       = "TCP"
    description    = "YC LoadBalancer health checks"
    from_port      = 30000
    to_port        = 32767
    v4_cidr_blocks = ["198.18.235.0/24", "198.18.248.0/24"]
  }

  ingress {
    protocol       = "TCP"
    description    = "YC LoadBalancer health checks to kube-proxy"
    port           = 10256
    v4_cidr_blocks = ["198.18.235.0/24", "198.18.248.0/24"]
  }

  # SSH доступ (если указан my_ip)
  dynamic "ingress" {
    for_each = var.my_ip != "" ? [1] : []
    content {
      protocol       = "TCP"
      description    = "SSH access from admin IP"
      port           = 22
      v4_cidr_blocks = [var.my_ip]
    }
  }

  # HTTP/HTTPS трафик
  ingress {
    protocol       = "TCP"
    description    = "HTTP traffic"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    description    = "HTTPS traffic"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # ICMP для диагностики
  ingress {
    protocol       = "ICMP"
    description    = "ICMP for network diagnostics"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------- Группа логов --------------------
resource "yandex_logging_group" "hw06_mk8s_logs" {
  name             = "hw06-mk8s-logs"
  description      = "Log group for Kubernetes cluster"
  folder_id        = var.folder_id
  retention_period = "168h" # 7 дней

  labels = {
    project    = "hw06"
    managed_by = "terraform"
  }
}

# ---------------------- Кластер Kubernetes --------------------
resource "yandex_kubernetes_cluster" "hw06_mk8s_cluster" {
  name        = "hw06-mk8s-cluster"
  description = "Managed Kubernetes cluster"
  folder_id   = var.folder_id
  network_id  = yandex_vpc_network.hw06_mk8s_vpc.id

  master {
    version = "1.30" # Стабильная версия

    zonal {
      zone      = var.zone
      subnet_id = yandex_vpc_subnet.hw06_mk8s_subnet_a.id
    }

    public_ip          = true
    security_group_ids = [yandex_vpc_security_group.hw06_mk8s_sg.id]

    maintenance_policy {
      auto_upgrade = true

      maintenance_window {
        start_time = "03:00" # UTC
        duration   = "3h"
        day        = "monday"
      }
    }

    # Включение логирования
    master_logging {
      enabled                    = true
      log_group_id               = yandex_logging_group.hw06_mk8s_logs.id
      kube_apiserver_enabled     = true
      cluster_autoscaler_enabled = true
      events_enabled             = true
      audit_enabled              = true
    }
  }

  service_account_id      = yandex_iam_service_account.hw06_mk8s_sa_master.id
  node_service_account_id = yandex_iam_service_account.hw06_mk8s_sa_nodes.id

  release_channel         = "REGULAR"
  network_policy_provider = "CALICO"

  cluster_ipv4_range = "10.96.0.0/16"
  service_ipv4_range = "10.97.0.0/16"

  labels = {
    project    = "hw06"
    managed_by = "terraform"
    version    = "1_30"
  }

  depends_on = [
    yandex_resourcemanager_folder_iam_member.hw06_mk8s_sa_master_k8s_agent,
    yandex_resourcemanager_folder_iam_member.hw06_mk8s_sa_master_vpc_public_admin,
    yandex_resourcemanager_folder_iam_member.hw06_mk8s_sa_master_lb_admin,
    yandex_resourcemanager_folder_iam_member.hw06_mk8s_sa_master_logging_writer,
    yandex_container_registry_iam_binding.hw06_mk8s_nodes_puller_on_registry,
  ]
}

# ---------------------- Группа узлов --------------------
resource "yandex_kubernetes_node_group" "hw06_mk8s_nodes" {
  name        = "hw06-mk8s-nodes"
  description = "Worker nodes group"
  cluster_id  = yandex_kubernetes_cluster.hw06_mk8s_cluster.id
  version     = "1.30"

  scale_policy {
    fixed_scale {
      size = var.node_count
    }
  }

  allocation_policy {
    location {
      zone = var.zone
    }
  }

  instance_template {
    platform_id = "standard-v3" # Современная платформа
    name        = "hw06-mk8s-node-{instance.index}"

    resources {
      cores         = var.node_cores
      memory        = var.node_memory
      core_fraction = var.preemptible ? 20 : 100 # 20% для preemptible, 100% для обычных
    }

    boot_disk {
      type = "network-ssd"
      size = 30 # GB, минимум для K8s
    }

    network_interface {
      subnet_ids         = [yandex_vpc_subnet.hw06_mk8s_subnet_a.id]
      nat                = true
      security_group_ids = [yandex_vpc_security_group.hw06_mk8s_sg.id]
    }

    scheduling_policy {
      preemptible = var.preemptible
    }

    # SSH ключ из переменной
    metadata = merge(
      {
        "user-data" = "#cloud-config\npackage_update: true\npackage_upgrade: true"
      },
      var.ssh_public_key != "" ? {
        "ssh-keys" = "ubuntu:${var.ssh_public_key}"
      } : {}
    )

    labels = {
      role        = "worker"
      environment = "demo"
      project     = "hw06"
    }
  }

  maintenance_policy {
    auto_repair  = true
    auto_upgrade = true

    maintenance_window {
      start_time = "03:00" # UTC  
      duration   = "3h"
      day        = "sunday"
    }
  }

  labels = {
    project    = "hw06"
    managed_by = "terraform"
    role       = "worker"
  }

  node_taints = [] # Без ограничений планирования
}

# ---------------------- Outputs --------------------
output "cluster_info" {
  description = "Основная информация о кластере"
  value = {
    id       = yandex_kubernetes_cluster.hw06_mk8s_cluster.id
    name     = yandex_kubernetes_cluster.hw06_mk8s_cluster.name
    endpoint = yandex_kubernetes_cluster.hw06_mk8s_cluster.master[0].external_v4_endpoint
  }
}

output "node_group_info" {
  description = "Информация о группе узлов"
  value = {
    id    = yandex_kubernetes_node_group.hw06_mk8s_nodes.id
    name  = yandex_kubernetes_node_group.hw06_mk8s_nodes.name
    count = var.node_count
    specs = "${var.node_cores} vCPU, ${var.node_memory} GB RAM"
  }
}

output "network_info" {
  description = "Сетевая информация"
  value = {
    vpc_id            = yandex_vpc_network.hw06_mk8s_vpc.id
    subnet_a_id       = yandex_vpc_subnet.hw06_mk8s_subnet_a.id
    security_group_id = yandex_vpc_security_group.hw06_mk8s_sg.id
  }
}

output "kubeconfig_command" {
  description = "Команда для получения kubeconfig"
  value       = "yc managed-kubernetes cluster get-credentials ${yandex_kubernetes_cluster.hw06_mk8s_cluster.name} --external --force"
}

output "useful_commands" {
  description = "Полезные команды для работы с кластером"
  value = [
    "# Получить kubeconfig:",
    "yc managed-kubernetes cluster get-credentials ${yandex_kubernetes_cluster.hw06_mk8s_cluster.name} --external --force",
    "",
    "# Проверить кластер:",
    "kubectl cluster-info",
    "kubectl get nodes -o wide",
    "",
    "# Создать тестовое приложение:",
    "kubectl create deployment nginx --image=nginx:latest",
    "kubectl expose deployment nginx --type=LoadBalancer --port=80",
    "kubectl get svc nginx -w"
  ]
}
