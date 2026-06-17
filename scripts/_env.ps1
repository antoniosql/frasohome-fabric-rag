$ErrorActionPreference = "Stop"

function Import-DotEnv {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$Required
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($Required) {
            throw "No existe $Path. Copia .env.example a .env y edítalo."
        }
        return
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "" -or $trimmed.StartsWith("#")) {
            continue
        }

        $match = [regex]::Match($trimmed, "^(?:export\s+)?(?<name>[A-Za-z_][A-Za-z0-9_]*)=(?<value>.*)$")
        if (-not $match.Success) {
            continue
        }

        $name = $match.Groups["name"].Value
        $value = $match.Groups["value"].Value.Trim()

        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        Set-Variable -Name $name -Value $value -Scope Script
        Set-Item -Path "Env:$name" -Value $value
    }
}

function Require-Env {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $variable = Get-Variable -Name $Name -Scope Script -ErrorAction SilentlyContinue
    $value = if ($null -eq $variable) { "" } else { [string]$variable.Value }

    if ([string]::IsNullOrWhiteSpace($value) -or $value -eq "00000000-0000-0000-0000-000000000000" -or $value.Contains("<server>")) {
        throw "Variable requerida no configurada: $Name"
    }
}

function Test-EnvValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $variable = Get-Variable -Name $Name -Scope Script -ErrorAction SilentlyContinue
    if ($null -eq $variable) {
        return $false
    }

    $value = [string]$variable.Value
    return -not ([string]::IsNullOrWhiteSpace($value) -or $value -eq "00000000-0000-0000-0000-000000000000")
}

function Get-SqlCmdAuthArguments {
    $mode = if (Test-EnvValue "FABRIC_SQL_AUTH_MODE") { $FABRIC_SQL_AUTH_MODE.ToLowerInvariant() } else { "default" }

    switch ($mode) {
        "service-principal" {
            Require-Env "FAB_SPN_CLIENT_ID"
            Require-Env "FAB_SPN_CLIENT_SECRET"
            return @(
                "--authentication-method", "ActiveDirectoryServicePrincipal",
                "-U", $FAB_SPN_CLIENT_ID,
                "-P", $FAB_SPN_CLIENT_SECRET
            )
        }
        "managed-identity" {
            $arguments = @("--authentication-method", "ActiveDirectoryManagedIdentity")
            if (Test-EnvValue "FABRIC_SQL_MANAGED_IDENTITY_CLIENT_ID") {
                $arguments += @("-U", $FABRIC_SQL_MANAGED_IDENTITY_CLIENT_ID)
            }
            elseif (Test-EnvValue "FAB_SPN_CLIENT_ID") {
                $arguments += @("-U", $FAB_SPN_CLIENT_ID)
            }
            return $arguments
        }
        "default" {
            return @("--authentication-method", "ActiveDirectoryDefault")
        }
        default {
            throw "FABRIC_SQL_AUTH_MODE debe ser 'default', 'service-principal' o 'managed-identity'. Valor actual: $FABRIC_SQL_AUTH_MODE"
        }
    }
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [string[]]$Arguments = @()
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "El comando falló con código ${LASTEXITCODE}: $Command $($Arguments -join ' ')"
    }
}

Import-DotEnv -Path ".env" -Required
