# README - Desafio: Deploy de Infraestrutura para Aplicação em Kubernetes com Terraform

Este projeto provisiona a infraestrutura necessária para rodar uma aplicação em Kubernetes (AKS) no Azure. A aplicação se conecta a um Azure Key Vault para recuperar a string de conexão de um banco de dados SQL Server e executa migrações automaticamente.

---

## Participantes

Ana Caroline Manso.\
Anderson S de Freitas.\
Fábio R de A Santos.

### Pré-requisitos

1. **Terraform instalado**: Certifique-se de que o Terraform está instalado na sua máquina. Você pode baixá-lo em [terraform.io](https://www.terraform.io/).
2. **Azure CLI instalado**: Instale o Azure CLI para autenticar no Azure. Siga as instruções em [docs.microsoft.com](https://docs.microsoft.com/cli/azure/install-azure-cli).
3. **Conta Azure**: Tenha uma conta Azure ativa e permissões para criar recursos.

### Passos para Executar o Terraform

1. **Inicie o Terraform:**
   ```bash
   terraform init

2. **Planeje as mudanças** (se aplicável):
   ```bash
   terraform plan

3. **Aplique as mudanças** (se aplicável):
   ```bash
   terraform apply
