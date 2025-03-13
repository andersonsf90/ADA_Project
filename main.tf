# Configurar a versão do Terraform e provedores
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.70.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
  }
}

# Configurar o Provedor Azure
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
  subscription_id = "919b98ed-13b1-4386-8894-1bf04ef96d62"
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

# Variáveis para configuração
variable "location" {
  description = "Localização dos recursos"
  type        = string
  default     = "West US" # Alterado para uma região suportada
}

variable "sql_admin_password" {
  description = "Senha do administrador do SQL Server"
  type        = string
  sensitive   = true
  default     = "P@ssw0rd123!" # Substitua por uma senha segura
}

# Criar um Grupo de Recursos
resource "azurerm_resource_group" "rg" {
  name     = "cx-rg-aks-app"
  location = var.location
}

# Criar um Azure Key Vault
resource "azurerm_key_vault" "kv" {
  name                        = "cx-kv-aks-app-c159657"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "Set", "List", "Delete"
    ]
  }
}

data "azurerm_client_config" "current" {}

# Criar um Banco de Dados SQL Server
resource "azurerm_mssql_server" "sql_server" {
  name                         = "cx-sqlserver-aks-app"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = var.sql_admin_password

  tags = {
    environment = "production"
  }
}

resource "azurerm_mssql_database" "sql_db" {
  name           = "cx-sqldb-aks-app"
  server_id      = azurerm_mssql_server.sql_server.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  max_size_gb    = 2
  sku_name       = "Basic"
  zone_redundant = false

  tags = {
    environment = "production"
  }
}

resource "azurerm_key_vault_secret" "db_connection_string" {
  name         = "db-connection-string"
  value        = "Server=tcp:${azurerm_mssql_server.sql_server.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.sql_db.name};Persist Security Info=False;User ID=${azurerm_mssql_server.sql_server.administrator_login};Password=${azurerm_mssql_server.sql_server.administrator_login_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  key_vault_id = azurerm_key_vault.kv.id
}

# Criar um Cluster Kubernetes (AKS)
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "cx-aks-cluster"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aks-cluster"

  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_B2s"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    environment = "production"
  }
}

# Configurar o Namespace no Kubernetes
resource "kubernetes_namespace" "app_namespace" {
  metadata {
    name = "app-namespace"
  }
}

# Configurar o Deployment da Aplicação
resource "kubernetes_deployment" "app" {
  metadata {
    name      = "app-deployment"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name
  }

  spec {
    replicas = 1 # Reduzido para 1 réplica

    selector {
      match_labels = {
        app = "app"
      }
    }

    template {
      metadata {
        labels = {
          app = "app"
        }
      }

      spec {
        container {
          name  = "app-container"
          image = "schwendler/embarque-ti-spd-project:latest"
          port {
            container_port = 8080 # Certifique-se de que esta porta está correta
          }

          env {
            name  = "SPD_KEY_VAULT_URI"
            value = azurerm_key_vault.kv.vault_uri
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "512Mi"
            }
          }
        }
      }
    }
  }
}

# Conceder Permissão para o AKS Acessar o Key Vault
resource "azurerm_key_vault_access_policy" "aks" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id

  secret_permissions = [
    "Get", "List"
  ]
}
