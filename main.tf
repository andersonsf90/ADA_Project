#Configurar a versão
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.70.0"
    }
  }
}

#Configurar o Provedor Azure
provider "azurerm" {
  features {}
  subscription_id = "919b98ed-13b1-4386-8894-1bf04ef96d62"
}
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

#Criar um Grupo de Recursos
resource "azurerm_resource_group" "rg" {
  name     = "rg-cx-aks-app"
  location = "East US"
}

#Criar um Azure Key Vault
resource "azurerm_key_vault" "kv" {
  name                        = "kv-aks-app"
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

#Criar um Banco de Dados SQL Server
resource "azurerm_mssql_server" "sql_server" {
  name                         = "sqlserver-aks-app"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = "P@ssw0rd123!" # Substitua por uma senha segura

  tags = {
    environment = "production"
  }
}

resource "azurerm_mssql_database" "sql_db" {
  name           = "sqldb-aks-app"
  server_id      = azurerm_mssql_server.sql_server.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  max_size_gb    = 10
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
#Criar um Cluster Kubernetes (AKS)
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-cluster"
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

#Configurar o Namespace no Kubernetes
resource "kubernetes_namespace" "app_namespace" {
  metadata {
    name = "app-namespace"
  }
}

#Configurar o Deployment da Aplicação
resource "kubernetes_deployment" "app" {
  metadata {
    name      = "app-deployment"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name
  }

  spec {
    replicas = 2

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
          image = "sua-imagem-docker" # Substitua pela imagem da aplicação
          port {
            container_port = 8080
          }

          env {
            name  = "SPD_KEY_VAULT_URI"
            value = azurerm_key_vault.kv.vault_uri
          }
        }
      }
    }
  }
}

#Conceder Permissão para o AKS Acessar o Key Vault
#Adicione uma política de acesso no Key Vault para a identidade do AKS:
resource "azurerm_key_vault_access_policy" "aks" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id

  secret_permissions = [
    "Get", "List"
  ]
}
#Atualize o deployment da aplicação para usar a identidade gerenciada
resource "kubernetes_deployment" "app" {
  metadata {
    name      = "app-deployment"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name
  }

  spec {
    replicas = 2

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
          image = "sua-imagem-docker" # Substitua pela imagem da aplicação
          port {
            container_port = 8080
          }

          env {
            name  = "SPD_KEY_VAULT_URI"
            value = azurerm_key_vault.kv.vault_uri
          }
        }
      }
    }
  }
}