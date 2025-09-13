# ============================================================================
# Основные переменные
# ============================================================================

variable "cloud_id" {
  description = "Yandex Cloud cloud ID"
  type        = string
}

variable "folder_id" {
  description = "Yandex Cloud folder ID"
  type        = string
}

variable "zone" {
  description = "Default availability zone"
  type        = string
  default     = "ru-central1-a"
}

variable "sa_key_file" {
  description = "Path to service account key JSON file"
  type        = string
}

# ============================================================================
# Настройки доступа
# ============================================================================

variable "ssh_public_key" {
  description = "SSH public key content (not path to file)"
  type        = string
  sensitive   = true
}

variable "my_ip" {
  description = "Your IP address in CIDR format for SSH access (e.g., 1.2.3.4/32). Leave empty to disable SSH"
  type        = string
  default     = ""
}

# ============================================================================
# Основные параметры кластера k8s
# ============================================================================

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 10
    error_message = "Node count must be between 1 and 10."
  }
}

variable "node_cores" {
  description = "Number of CPU cores per node"
  type        = number
  default     = 2

  validation {
    condition     = contains([1, 2, 4, 6, 8], var.node_cores)
    error_message = "Node cores must be one of: 1, 2, 4, 6, 8."
  }
}

variable "node_memory" {
  description = "Amount of memory per node (GB)"
  type        = number
  default     = 4

  validation {
    condition     = var.node_memory >= 1 && var.node_memory <= 64
    error_message = "Node memory must be between 1 and 64 GB."
  }
}

variable "preemptible" {
  description = "Use preemptible (cheaper) instances"
  type        = bool
  default     = true
}
