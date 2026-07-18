#Requires -Version 5.1
<#
.SYNOPSIS
  Windows entrypoint for the DC34 Blue Team Village CTF Kubernetes sandbox.

.DESCRIPTION
  Parity with the repo Makefile targets on macOS (colima + minikube + helmfile).
  On Windows: Docker Desktop (WSL2 engine) + minikube docker driver + helmfile.

  Usage:
    .\windows\sandbox.ps1 tools
    .\windows\sandbox.ps1 up
    .\windows\sandbox.ps1 verify
    .\windows\sandbox.ps1 status
    .\windows\sandbox.ps1 stop
    .\windows\sandbox.ps1 clean

  Prefer windows\start.cmd, which bypasses PowerShell execution policy.
  Documentation: windows/README.md
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('tools', 'up', 'verify', 'stop', 'clean', 'status')]
    [string]$Command
)

# Bare `windows\start.cmd` (no subcommand) should print usage, not sit at an
# interactive parameter prompt.
if (-not $Command) {
    Write-Host 'Usage: windows\start.cmd <command>'
    Write-Host ''
    Write-Host 'Commands:'
    Write-Host '  tools    Install CLI tools (Docker Desktop, minikube, kubectl, helm, helmfile, Git)'
    Write-Host '  up       Start the dc34 cluster and deploy the sandbox stack'
    Write-Host '  verify   Automated health check'
    Write-Host '  status   Show cluster health'
    Write-Host '  stop     Pause the cluster (state preserved)'
    Write-Host '  clean    Delete the minikube profile and kubectl context'
    Write-Host ''
    Write-Host 'First-time setup: windows\start.cmd tools, then start Docker Desktop, open a new terminal, and run windows\start.cmd up'
    exit 1
}

$ErrorActionPreference = 'Stop'

# windows/ -> repo root
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $RepoRoot

$ProfileName = 'dc34'
$env:MINIKUBE_PROFILE = $ProfileName

function Assert-Command {
    param([string]$Name, [string]$Hint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name. $Hint"
    }
}

function Assert-DockerRunning {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    docker info 2>&1 | Out-Null
    $ok = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $prevEap
    if (-not $ok) {
        throw @"
Docker is not reachable (docker info failed).

If Docker Desktop says "unable to start":
  1. Quit Docker Desktop fully (tray icon -> Quit).
  2. In PowerShell (Admin):  wsl --shutdown
  3. Start Docker Desktop again and wait until Running (can take 2-5 min after reboot).
  4. Settings -> General -> Use the WSL 2 based engine (checked).

Still broken: Docker Desktop -> Troubleshoot -> Restart / Reset to factory defaults (last resort).

See windows/README.md (Troubleshooting).
"@
    }
}

function Get-GitBashExecutable {
    $candidates = @(
        (Join-Path ${env:ProgramFiles} 'Git\bin\bash.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe')
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

function Get-BashRepoPath {
    param([string]$BashExe)
    $unix = $RepoRoot -replace '\\', '/'
    if ($unix -notmatch '^([A-Za-z]):(.*)$') { return $unix }
    $drive = $Matches[1].ToLower()
    $tail = $Matches[2]
    if (-not $tail.StartsWith('/')) { $tail = "/$tail" }
    if ($BashExe -match 'Git[\\/]') {
        return "/$drive$tail"
    }
    return "/mnt/$drive$tail"
}

function Invoke-Bash {
    param([string]$CommandLine)
    $gitBash = Get-GitBashExecutable
    if ($gitBash) {
        $bashExe = $gitBash
    } else {
        Assert-Command -Name 'bash' -Hint 'Install Git for Windows (Git Bash). Required for helmfile presync hooks in helmfile.yaml.'
        $bashExe = (Get-Command bash).Source
        Write-Host "Warning: Git Bash not found; using $bashExe (WSL paths apply)." -ForegroundColor Yellow
    }
    $bashCd = Get-BashRepoPath -BashExe $bashExe
    & $bashExe -lc "cd '$bashCd' && $CommandLine"
    if ($LASTEXITCODE -ne 0) { throw "bash command failed (exit $LASTEXITCODE): $CommandLine" }
}

function Install-Helmfile {
    $installDir = Join-Path $env:LOCALAPPDATA 'Programs\helmfile'
    $helmfileExe = Join-Path $installDir 'helmfile.exe'
    if (Test-Path $helmfileExe) {
        $env:Path = "$installDir;$env:Path"
        Write-Host "helmfile already installed: $helmfileExe" -ForegroundColor DarkGray
        return
    }

    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
    $version = '1.5.2'
    $url = "https://github.com/helmfile/helmfile/releases/download/v$version/helmfile_${version}_windows_${arch}.tar.gz"

    Write-Host "==> Installing helmfile $version ($arch) to $installDir ..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null

    $tmp = Join-Path $env:TEMP "helmfile-install-$version"
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    $archive = Join-Path $tmp 'helmfile.tar.gz'
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
    & tar -xzf $archive -C $tmp
    if (-not (Test-Path (Join-Path $tmp 'helmfile.exe'))) {
        throw "helmfile.exe not found after extract. Check $tmp"
    }
    Copy-Item (Join-Path $tmp 'helmfile.exe') $helmfileExe -Force
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -notlike "*$installDir*") {
        [Environment]::SetEnvironmentVariable('Path', "$installDir;$userPath", 'User')
        Write-Host "Added $installDir to user PATH (open a new terminal if helmfile is not found)." -ForegroundColor Yellow
    }
    $env:Path = "$installDir;$env:Path"
    Write-Host "helmfile installed: $helmfileExe" -ForegroundColor Green
    & $helmfileExe version
}

switch ($Command) {
    'tools' {
        Write-Host 'Installing CLI tools via winget (see windows/README.md).' -ForegroundColor Cyan
        Assert-Command -Name 'winget' -Hint 'Install App Installer / winget from the Microsoft Store.'
        $packages = @(
            'Docker.DockerDesktop',
            'Kubernetes.minikube',
            'Kubernetes.kubectl',
            'Helm.Helm',
            'Git.Git'
        )
        foreach ($id in $packages) {
            Write-Host "==> winget install --id $id -e --accept-package-agreements --accept-source-agreements"
            winget install --id $id -e --accept-package-agreements --accept-source-agreements
        }
        Write-Host ''
        Install-Helmfile
        Write-Host ''
        Write-Host 'Optional: winget install -e --id Derailed.k9s'
        Write-Host 'Alternative (only if you already use scoop): scoop install helmfile'
        Write-Host ''
        Write-Host 'Enable Docker Desktop WSL2 engine, reboot if prompted, then:'
        Write-Host '  windows\start.cmd up'
    }

    'up' {
        Assert-Command -Name 'docker' -Hint 'Install Docker Desktop (windows\start.cmd tools).'
        Assert-Command -Name 'minikube' -Hint 'winget install -e --id Kubernetes.minikube'
        Assert-Command -Name 'kubectl' -Hint 'winget install -e --id Kubernetes.kubectl'
        Assert-Command -Name 'helm' -Hint 'winget install -e --id Helm.Helm'
        if (-not (Get-Command helmfile -ErrorAction SilentlyContinue)) {
            Install-Helmfile
        }
        Assert-Command -Name 'helmfile' -Hint 'Run: windows\start.cmd tools'
        Assert-DockerRunning

        Write-Host "==> Starting minikube profile '$ProfileName' (docker driver, Cilium CNI)..." -ForegroundColor Cyan
        & minikube start -p $ProfileName `
            --driver=docker `
            --cpus=4 `
            --memory=6144 `
            --cni=cilium `
            --addons=metrics-server
        if ($LASTEXITCODE -ne 0) { throw 'minikube start failed' }

        Write-Host '==> helmfile sync (Tetragon, Kyverno, policies)...' -ForegroundColor Cyan
        Invoke-Bash 'helmfile sync --enable-live-output'

        Write-Host ''
        Write-Host 'Sandbox ready. Check it:' -ForegroundColor Green
        Write-Host '  windows\start.cmd verify'
        Write-Host ''
        Write-Host 'When done with the competition:'
        Write-Host '  windows\start.cmd stop    pause the cluster (state preserved)'
        Write-Host '  windows\start.cmd clean   tear down the cluster'
    }

    'verify' {
        Assert-Command -Name 'kubectl' -Hint 'winget install -e --id Kubernetes.kubectl'
        $failures = [System.Collections.Generic.List[string]]::new()

        function Add-CheckFailure {
            param([string]$Message)
            $failures.Add($Message)
            Write-Host "FAIL: $Message" -ForegroundColor Red
        }

        function Add-CheckOk {
            param([string]$Message)
            Write-Host "OK:   $Message" -ForegroundColor Green
        }

        Write-Host "==> Verifying DC34 sandbox stack (profile $ProfileName)..." -ForegroundColor Cyan
        Write-Host ''

        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'

        & minikube status -p $ProfileName 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Add-CheckFailure "minikube profile '$ProfileName' is not running. Run: windows\start.cmd up"
        } else {
            Add-CheckOk "minikube profile '$ProfileName' is up"
        }

        & kubectl --context=$ProfileName cluster-info 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Add-CheckFailure "kubectl context '$ProfileName' is not reachable"
        } else {
            Add-CheckOk "kubectl context '$ProfileName' answers cluster-info"
        }

        $nodes = & kubectl --context=$ProfileName get nodes -o json 2>$null | ConvertFrom-Json
        if (-not $nodes -or $nodes.items.Count -eq 0) {
            Add-CheckFailure 'no Kubernetes nodes reported'
        } else {
            $notReady = @($nodes.items | Where-Object { $_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -ne 'True' } })
            if ($notReady.Count -gt 0) {
                Add-CheckFailure 'one or more nodes are NotReady'
            } else {
                Add-CheckOk 'all nodes Ready'
            }
        }

        $tetragon = & kubectl --context=$ProfileName -n kube-system get pods -l 'app.kubernetes.io/name=tetragon' -o json 2>$null | ConvertFrom-Json
        if (-not $tetragon -or $tetragon.items.Count -eq 0) {
            Add-CheckFailure 'Tetragon DaemonSet not found (run windows\start.cmd up)'
        } else {
            $bad = @($tetragon.items | Where-Object {
                    $phase = $_.status.phase
                    $phase -ne 'Running' -and $phase -ne 'Succeeded'
                })
            if ($bad.Count -gt 0) {
                Add-CheckFailure 'Tetragon pods are not Running'
            } else {
                Add-CheckOk 'Tetragon DaemonSet pods healthy'
            }
        }

        $kyverno = & kubectl --context=$ProfileName -n kyverno get pods -o json 2>$null | ConvertFrom-Json
        if (-not $kyverno -or $kyverno.items.Count -eq 0) {
            Add-CheckFailure 'Kyverno pods not found (run windows\start.cmd up)'
        } else {
            $bad = @($kyverno.items | Where-Object {
                    $phase = $_.status.phase
                    $phase -ne 'Running' -and $phase -ne 'Succeeded'
                })
            if ($bad.Count -gt 0) {
                Add-CheckFailure 'Kyverno pods are not Running'
            } else {
                Add-CheckOk 'Kyverno pods healthy'
            }
        }

        $ErrorActionPreference = $prevEap
        Write-Host ''
        if ($failures.Count -gt 0) {
            Write-Host "Verification failed ($($failures.Count) issue(s))." -ForegroundColor Red
            exit 1
        }
        Write-Host 'All checks passed. Happy hunting!' -ForegroundColor Green
    }

    'stop' {
        & minikube stop -p $ProfileName
        if ($LASTEXITCODE -ne 0) { throw 'minikube stop failed' }
    }

    'clean' {
        & minikube delete -p $ProfileName
        & kubectl config delete-context $ProfileName 2>$null
        & kubectl config delete-cluster $ProfileName 2>$null
        & kubectl config delete-user $ProfileName 2>$null
        Write-Host "Removed minikube profile and kubectl context '$ProfileName'."
    }

    'status' {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & minikube status -p $ProfileName 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Host ''
            Write-Host "No '$ProfileName' cluster yet. First-time setup:" -ForegroundColor Yellow
            Write-Host '  windows\start.cmd up'
            $ErrorActionPreference = $prevEap
            return
        }
        Write-Host ''
        & kubectl --context=$ProfileName get nodes 2>&1 | Write-Host
        Write-Host ''
        & kubectl --context=$ProfileName -n kube-system get pods -l 'app.kubernetes.io/name=tetragon' 2>&1 | Write-Host
        & kubectl --context=$ProfileName -n kyverno get pods 2>&1 | Write-Host
        $ErrorActionPreference = $prevEap
    }
}
