# Configurar a versão do Terraform e provedores
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.00.0"
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
      purge_soft_deleted_keys_on_destroy = true
      purge_soft_deleted_secrets_on_destroy = true
    }
  }
  subscription_id = "999999999999999999999999999999999"
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

resource "azurerm_key_vault" "kv" {
  name                        = "cx-kv-aks-app-0x"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  purge_protection_enabled    = false
  sku_name                    = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Set", "Get", "Delete", "Purge", "List"
    ]
  }

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id

    secret_permissions = [
      "Get", "List"
    ]
  }

}

data "azurerm_client_config" "current" {}

# Criar um Banco de Dados SQL Server
resource "azurerm_mssql_server" "sql_server" {
  name                         = "cx-sqlserver-aks-app2"
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
# Logs de erro do AKS
#  tags = {
#    environment = "production"
#  }
}

resource "azurerm_key_vault_secret" "db_connection_string" {
  name         = "db-connection-string"
  value        = "Server=tcp:${azurerm_mssql_server.sql_server.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.sql_db.name};Persist Security Info=False;User ID=${azurerm_mssql_server.sql_server.administrator_login};Password=${azurerm_mssql_server.sql_server.administrator_login_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
    azurerm_key_vault_access_policy.aks
  ]
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
#          image = "ubuntu/nginx:latest"
          port {
            container_port = 8080 #Solicitaçao do projeto
          }

          env {
            name  = "SPD_KEY_VAULT_URI"
            value = azurerm_key_vault.kv.vault_uri
          }

          env {
            name  = "ASPNETCORE_ENVIRONMENT"
            value = "Development" # Habilitar modo de desenvolvimento
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

# Habilitar o Azure RBAC para o Key Vault (Opcional)
resource "azurerm_role_assignment" "aks_key_vault_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

# Adicionar Regra de Firewall para o IP do AKS(Permitir Serviços do Azure)
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "allow-azure-services"
  server_id        = azurerm_mssql_server.sql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

resource "kubernetes_service" "app" {
  metadata {
    name      = "cx-app-service"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name
  }

  spec {
    selector = {
      app = "app" # Deve corresponder ao label do deployment
    }

    port {
      port        = 8080         # Porta exposta externamente
      target_port = 8080       # Porta do container (8080)
      protocol    = "TCP"
    }

    type = "LoadBalancer" # Expõe o serviço externamente com um IP público
  }
}

output "app_service_ip" {
  value = kubernetes_service.app.status.0.load_balancer.0.ingress.0.ip
}

# Executar comandos locais
resource "null_resource" "set_azure_subscription" {
  provisioner "local-exec" {
    command = "az account set --subscription 919b98ed-13b1-4386-8894-1bf04ef96d62"
  }

  depends_on = [azurerm_resource_group.rg]
}

resource "null_resource" "get_aks_credentials" {
  provisioner "local-exec" {
    command = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name} --overwrite-existing"
  }

  depends_on = [azurerm_kubernetes_cluster.aks]
}
