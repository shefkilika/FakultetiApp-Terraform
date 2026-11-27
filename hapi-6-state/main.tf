# main.tf — burimet kryesore: grupi, Storage, App Service Plan dhe Web App.
# Key Vault është te keyvault.tf; SQL është te sql.tf.
# Terraform i lexon të gjitha skedarët .tf në këtë folder si një e vetme; emrat e skedarëve janë vetëm për rregull.
#
# Sintaksa e përgjithshme:  resource "<LLOJI>" "<EMRI_LOKAL>" { ... }
#   LLOJI      = çfarë krijohet në Azure (p.sh. azurerm_storage_account)
#   EMRI_LOKAL = si e quajmë në kod; përdoret për t'iu referuar (azurerm_resource_group.rg.name)

# ---------------------------------------------------------------------------
# 1) Prapashtesa e rastësishme
# ---------------------------------------------------------------------------
# random_string gjenerohet NJË herë dhe ruhet në state, prandaj mbetet e njëjtë në çdo "apply".
# Na duhet sepse emrat e Storage, Key Vault, SQL dhe Web App duhet të jenë unikë në gjithë botën.
resource "random_string" "suffix" {
  length  = 5
  lower   = true
  upper   = false # Storage account pranon vetëm shkronja të vogla
  numeric = true
  special = false
}

# ---------------------------------------------------------------------------
# 2) locals = vlera të llogaritura që i ripërdorim (si variabla të brendshme)
# ---------------------------------------------------------------------------
locals {
  prapashtesa = random_string.suffix.result

  # Etiketat (tags) vihen në çdo burim; ndihmojnë të dimë kush e ka krijuar dhe pse
  tags = {
    projekti = "FakultetiApp"
    studenti = var.emri
    krijuar  = "terraform"
    viti     = "2026"
  }
}

# ---------------------------------------------------------------------------
# 3) Resource Group = "folderi" që mban të gjitha burimet
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "rg" {
  name     = "rg-tf-${var.emri}" # emri në Azure; ${...} fut vlerën e variablës
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# 4) Storage account (për blobs) dhe container-i i dokumenteve
# ---------------------------------------------------------------------------
# Kur shkruajmë azurerm_resource_group.rg.name, Terraform kupton vetë që grupi duhet krijuar
# PARA storage-it. Kjo quhet varësi e nënkuptuar (implicit dependency).
resource "azurerm_storage_account" "st" {
  name                     = "st${var.emri}${local.prapashtesa}" # vetëm shkronja të vogla dhe numra, max 24
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS" # kopja më e lirë (3 kopje në një datacenter)
  tags                     = local.tags
}

resource "azurerm_storage_container" "dokumentet" {
  name                  = "dokumentet-${var.emri}"
  storage_account_id    = azurerm_storage_account.st.id
  container_access_type = "private" # askush nuk i hap skedarët pa autorizim
}

# ---------------------------------------------------------------------------
# 5) App Service Plan = "kompjuteri" ku punon aplikacioni
# ---------------------------------------------------------------------------
resource "azurerm_service_plan" "plan" {
  name                = "plan-tf-${var.emri}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = var.plan_sku # F1 = falas (60 min CPU në ditë)
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# 6) Web App = aplikacioni vetë (.NET 10)
# ---------------------------------------------------------------------------
resource "azurerm_linux_web_app" "app" {
  name                = "app-tf-${var.emri}-${local.prapashtesa}" # bëhet adresa <emri>.azurewebsites.net
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_plan_id     = azurerm_service_plan.plan.id
  https_only          = true # HTTP ridrejtohet automatikisht te HTTPS
  tags                = local.tags

  # Managed Identity: Azure i jep aplikacionit një identitet; me të lexon sekrete pa fjalëkalim
  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on = false # F1 nuk e mbështet "always on"

    application_stack {
      dotnet_version = "10.0"
    }
  }

  # app_settings bëhen variabla ambienti të aplikacionit.
  # "__" në .NET do të thotë ":" (ConnectionStrings__Sql lexohet si ConnectionStrings:Sql)
  app_settings = {
    "Blob__Container" = azurerm_storage_container.dokumentet.name

    # REFERENCË te Key Vault: në app ruhet vetëm "pointer"; vlera e vërtetë mbetet në Key Vault.
    # Azure e zgjidh referencën me Managed Identity të aplikacionit.
    "ConnectionStrings__Storage" = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.kv.name};SecretName=StorageConnection)"
    "ConnectionStrings__Sql"     = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.kv.name};SecretName=SqlConnection)"
  }
}
