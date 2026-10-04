# deploy.ps1 - run Terraform for ONE environment, chosen by argument.
# Usage: .\deploy.ps1 -Environment dev -Action plan [-ExtraArgs '-var=asg_max_size=4']
param(
  [Parameter(Mandatory = $true)][ValidateSet('dev', 'test', 'prod')][string]$Environment,
  [Parameter(Mandatory = $true)][ValidateSet('init', 'plan', 'apply', 'destroy', 'output', 'validate')][string]$Action,
  [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot "environments\$Environment")
Write-Host "=== Environment: $Environment | Action: $Action ==="

if ($Action -ne 'init' -and -not (Test-Path .terraform)) { terraform init }
terraform $Action @ExtraArgs
