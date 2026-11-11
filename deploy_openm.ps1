param(
    [ValidateSet('check', 'sync', 'deploy', 'local')]
    [string]$Mode = 'deploy',
    [string]$SourcePath = ''
)

$ErrorActionPreference = 'Stop'
$package = $PSScriptRoot.TrimEnd('\')

function Assert-Package {
    $required = @(
        'OpenM_backend_python\app\main.py',
        'OpenM_backend_python\app\database.py',
        'OpenM_backend_python\requirements.txt',
        'OpenM_frontend_flutter\pubspec.yaml',
        'OpenM_frontend_flutter\pubspec.lock',
        'OpenM_frontend_flutter\lib\main.dart',
        'OpenM_frontend_flutter\web\index.html',
        'start_openm.bat',
        'build_server.bat',
        'deploy\docker-compose.source.yml',
        'deploy\backend.Dockerfile',
        'deploy\frontend.Dockerfile',
        'deploy\nginx.conf',
        'deploy\.env.example'
    )
    foreach ($path in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $package $path) -PathType Leaf)) {
            throw "Required package file is missing: $path"
        }
    }
}

function Get-Differences([string]$source) {
    $sourceFiles = @(& git -C $source -c core.quotepath=false ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to list source files with Git.' }
    $paths = @{}
    $changes = @()
    foreach ($entry in $sourceFiles) {
        $relative = $entry.Replace('/', '\')
        $from = Join-Path $source $relative
        if (-not (Test-Path -LiteralPath $from -PathType Leaf)) { continue }
        $paths[$relative.ToLowerInvariant()] = $true
        $to = Join-Path $package $relative
        if (-not (Test-Path -LiteralPath $to -PathType Leaf)) {
            $changes += $relative
        } elseif ((Get-FileHash -LiteralPath $from -Algorithm SHA256).Hash -ne
                  (Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash) {
            $changes += $relative
        }
    }

    $extras = @()
    Get-ChildItem -LiteralPath $package -Force -File -Recurse |
        ForEach-Object {
            $relative = $_.FullName.Substring($package.Length + 1)
            if (-not $relative.StartsWith('.git\', [StringComparison]::OrdinalIgnoreCase) -and
                -not $paths.ContainsKey($relative.ToLowerInvariant())) {
                $extras += $relative
            }
        }
    $unmatched = @()
    foreach ($relative in $extras) {
        & git -C $source check-ignore --quiet --no-index -- $relative
        if ($LASTEXITCODE -gt 1) { throw 'Unable to check ignored files with Git.' }
        if ($LASTEXITCODE -eq 1) { $unmatched += $relative }
    }
    return @{ Changes = $changes; Extras = $unmatched }
}

try {
    if ($Mode -ne 'local') {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            throw 'Git is required to compare with the source repository.'
        }
        if (-not $SourcePath) { $SourcePath = $env:OPENM_SOURCE_ROOT }
        if (-not $SourcePath) { $SourcePath = 'D:\Projekte\OpenM_Projcet' }
        $source = (Resolve-Path -LiteralPath $SourcePath).ProviderPath.TrimEnd('\')
        $top = & git -C $source rev-parse --show-toplevel
        if ($LASTEXITCODE -ne 0) { throw "Source is not a Git repository: $source" }
        $top = (Resolve-Path -LiteralPath $top).ProviderPath.TrimEnd('\')
        if (-not $source.Equals($top, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'SourcePath must point to the root of the source Git repository.'
        }
        if ($source.Equals($package, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Source and distribution package must be different folders.'
        }
        Write-Host "Source: $source"
        Write-Host "Package: $package"
        $diff = Get-Differences $source
        if ($diff.Changes.Count -gt 0) {
            Write-Host "Missing or changed files ($($diff.Changes.Count)):"
            $diff.Changes | ForEach-Object { Write-Host "  $_" }
        }
        if ($diff.Extras.Count -gt 0) {
            Write-Host "Additional non-ignored files in package ($($diff.Extras.Count)):"
            $diff.Extras | ForEach-Object { Write-Host "  $_" }
            throw 'Review these extra files manually. No files were deleted or overwritten.'
        }
        if ($diff.Changes.Count -gt 0) {
            if ($Mode -eq 'check') { throw 'Package differs from the source.' }
            $answer = Read-Host 'Copy these source files to the package and overwrite matching files? Type YES'
            if ($answer -cne 'YES') { throw 'Synchronization cancelled; no files were changed.' }
            foreach ($relative in $diff.Changes) {
                $to = Join-Path $package $relative
                $parent = Split-Path -Parent $to
                if (-not (Test-Path -LiteralPath $parent)) {
                    New-Item -ItemType Directory -Path $parent -Force | Out-Null
                }
                Copy-Item -LiteralPath (Join-Path $source $relative) -Destination $to -Force
            }
            $diff = Get-Differences $source
            if ($diff.Changes.Count -gt 0 -or $diff.Extras.Count -gt 0) {
                throw 'Package verification failed after synchronization.'
            }
        }
        Write-Host 'Package matches all non-ignored source files.'
        Assert-Package
        if ($Mode -eq 'check' -or $Mode -eq 'sync') { exit 0 }
    } else {
        Write-Warning 'Local deployment: freshness against the source repository was not checked.'
        Assert-Package
    }

    $envFile = Join-Path $package 'deploy\.env'
    if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
        Copy-Item -LiteralPath (Join-Path $package 'deploy\.env.example') -Destination $envFile
        throw 'Created deploy\.env. Set OPENM_DB_PASSWORD there and run the command again.'
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker is not installed or is not on PATH.'
    }
    & docker info --format '{{.ServerVersion}}'
    if ($LASTEXITCODE -ne 0) { throw 'Docker Engine is not running.' }
    $compose = Join-Path $package 'deploy\docker-compose.source.yml'
    & docker compose --env-file $envFile -f $compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose configuration is invalid.' }
    & docker compose --env-file $envFile -f $compose up -d --build --wait
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose build or startup failed.' }

    $healthy = $false
    for ($i = 0; $i -lt 30; $i++) {
        & docker compose --env-file $envFile -f $compose exec -T backend python -c "import json,urllib.request; data=json.load(urllib.request.urlopen('http://127.0.0.1:8002/health',timeout=3)); assert data.get('status') == 'healthy' and data.get('database') == 'connected', data"
        if ($LASTEXITCODE -eq 0) { $healthy = $true; break }
        Start-Sleep -Seconds 2
    }
    if (-not $healthy) { throw 'Backend did not report a healthy PostgreSQL connection. Check Docker Compose logs.' }
    & docker compose --env-file $envFile -f $compose exec -T web nginx -t
    if ($LASTEXITCODE -ne 0) { throw 'Web server configuration check failed.' }
    & docker compose --env-file $envFile -f $compose exec -T web wget -q -O /dev/null http://127.0.0.1/
    if ($LASTEXITCODE -ne 0) { throw 'Web frontend is not reachable inside the web container.' }
    & docker compose --env-file $envFile -f $compose exec -T web wget -q -O /dev/null http://127.0.0.1/api/health
    if ($LASTEXITCODE -ne 0) { throw 'Backend is not reachable through the web proxy.' }
    Write-Host 'OpenM started. Backend, PostgreSQL, frontend and proxy are reachable.'
} catch {
    Write-Error $_
    exit 1
}
