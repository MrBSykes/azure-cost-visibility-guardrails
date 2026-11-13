<#
.SYNOPSIS
  One-time setup: lets this repo's GitHub Actions log in to Azure with short-lived
  OIDC tokens (no stored passwords or client secrets).

.DESCRIPTION
  Creates (or reuses): an app registration and service principal, three federated
  credentials (pull requests, the main branch, the 'production' environment),
  and the role assignments the pipeline needs. Safe to run again.

  Run from any folder after `az login`, on the subscription you want to govern.
  It prints three values for GitHub secrets. They are identifiers, not passwords,
  but treat them as private: do not paste them into chats, issues or screenshots.
#>
param(
  [string]$Repo         = 'MrBSykes/azure-cost-visibility-guardrails',
  [string]$AppName      = 'github-actions-cost-governance',
  [string]$StateRG      = 'TerraformStateRG',
  [string]$StateAccount = 'sykestfstate'
)

$ErrorActionPreference = 'Stop'

function Run-Az {
  # Runs az, throws if it fails, returns the output.
  $out = & az @args
  if ($LASTEXITCODE -ne 0) { throw "az $($args -join ' ') failed" }
  return $out
}

$sub    = (Run-Az account show --query id -o tsv)
$tenant = (Run-Az account show --query tenantId -o tsv)
Write-Host "Subscription and tenant read from your current az login." -ForegroundColor Cyan

# 1. App registration
$appId = (Run-Az ad app list --display-name $AppName --query "[0].appId" -o tsv)
if (-not $appId) {
  $appId = (Run-Az ad app create --display-name $AppName --query appId -o tsv)
  Write-Host "Created app registration: $AppName"
} else { Write-Host "App registration exists: $AppName" }

# 2. Service principal
$spId = (Run-Az ad sp list --filter "appId eq '$appId'" --query "[0].id" -o tsv)
if (-not $spId) {
  $spId = (Run-Az ad sp create --id $appId --query id -o tsv)
  Write-Host "Created service principal"
} else { Write-Host "Service principal exists" }

# 3. Federated credentials: which GitHub runs may log in as this identity
function Ensure-FedCred($name, $subject) {
  $existing = (Run-Az ad app federated-credential list --id $appId --query "[?name=='$name'].name" -o tsv)
  if ($existing) { Write-Host "Federated credential exists: $name"; return }
  $json = @{
    name      = $name
    issuer    = 'https://token.actions.githubusercontent.com'
    subject   = $subject
    audiences = @('api://AzureADTokenExchange')
  } | ConvertTo-Json -Compress
  $tmp = [System.IO.Path]::GetTempFileName()
  try {
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    Run-Az ad app federated-credential create --id $appId --parameters "@$tmp" | Out-Null
  } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
  Write-Host "Created federated credential: $name  ($subject)"
}

Ensure-FedCred 'github-pull-request' "repo:${Repo}:pull_request"
Ensure-FedCred 'github-main-branch'  "repo:${Repo}:ref:refs/heads/main"
Ensure-FedCred 'github-env-production' "repo:${Repo}:environment:production"

# 4. Roles: what the pipeline is allowed to do
function Ensure-Role($role, $scope) {
  $has = (Run-Az role assignment list --assignee $spId --role $role --scope $scope --query "[0].id" -o tsv)
  if ($has) { Write-Host "Role exists: $role"; return }
  Run-Az role assignment create --assignee-object-id $spId --assignee-principal-type ServicePrincipal --role $role --scope $scope | Out-Null
  Write-Host "Assigned: $role"
}

$subScope   = "/subscriptions/$sub"
$stateScope = "/subscriptions/$sub/resourceGroups/$StateRG/providers/Microsoft.Storage/storageAccounts/$StateAccount"

Ensure-Role 'Contributor'                    $subScope    # budgets, action group, views, anomaly alert
Ensure-Role 'Resource Policy Contributor'    $subScope    # custom policy definition and assignment
Ensure-Role 'Storage Blob Data Contributor'  $stateScope  # read/write state and its lock, with Entra auth

Write-Host ""
Write-Host "Done. Add these as GitHub repository SECRETS (Settings > Secrets and variables > Actions):" -ForegroundColor Green
Write-Host "  AZURE_CLIENT_ID       = $appId"
Write-Host "  AZURE_TENANT_ID       = $tenant"
Write-Host "  AZURE_SUBSCRIPTION_ID = $sub"
Write-Host "  ALERT_EMAIL           = (the same address you pass as TF_VAR_alert_email)"
Write-Host ""
Write-Host "Do not paste the values above anywhere public." -ForegroundColor Yellow
