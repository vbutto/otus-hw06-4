# Роли сервисного аккаунта для terraform
# iam.serviceAccounts.admin - для создания сервисных аккаунтов
# container-registry.admin - для создания реестра и назначения прав
# vpc.publicAdmin - для создания VPC-сети и подсети
# vpc.privateAdmin - для создания VPC-сети и подсети
# vpc.user
# vpc.securityGroups.admin - для создания security group
# compute.admin - для создания группы ВМ


# ---------------------- Поиск существующего реестра YCR --------------------
# Находим реестр по имени в нужной папке
data "yandex_container_registry" "cr" {
  name      = "hw06-cr-demo"
  folder_id = var.folder_id
}

