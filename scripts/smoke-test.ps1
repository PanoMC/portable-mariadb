# Smoke test for an extracted Windows package (see smoke-test.sh for the Unix one).
# Usage: scripts/smoke-test.ps1 -Package <extracted package dir>
param([Parameter(Mandatory = $true)][string]$Package)
$ErrorActionPreference = 'Stop'

$B = (Resolve-Path $Package).Path
$T = Join-Path ([System.IO.Path]::GetTempPath()) ("pmdb-smoke-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$Port = 33071
$Password = 'Smoke-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
New-Item -ItemType Directory -Path $T | Out-Null

Write-Host "== $(Get-Content "$B/VERSION")"
& "$B/bin/mariadbd.exe" --version

& "$B/bin/mariadb-install-db.exe" "--datadir=$T/data" "--password=$Password" "--port=$Port"
if ($LASTEXITCODE -ne 0) { throw 'mariadb-install-db failed' }

# Local connection with a self-signed server certificate: TLS stays on, verification is off.
$Client = @('--no-defaults', '-uroot', "-p$Password", '-h127.0.0.1', "-P$Port", '--skip-ssl-verify-server-cert')

$Server = Start-Process -FilePath "$B/bin/mariadbd.exe" -PassThru -NoNewWindow `
    -ArgumentList "--defaults-file=$T/data/my.ini", '--bind-address=127.0.0.1', "--log-error=$T/error.log"
try {
    $Ready = $false
    for ($i = 0; $i -lt 120; $i++) {
        $Ping = & "$B/bin/mariadb-admin.exe" @Client ping 2>&1
        if ($LASTEXITCODE -eq 0) { $Ready = $true; break }
        if ($Server.HasExited) { break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $Ready) {
        Write-Host "last ping: $Ping"
        Get-Content "$T/error.log" -ErrorAction SilentlyContinue
        throw 'server did not start'
    }

    $Query = @"
SELECT VERSION();
CREATE DATABASE smoke CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE TABLE smoke.t (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(64), doc JSON) ENGINE=InnoDB;
INSERT INTO smoke.t (name, doc) VALUES ('pano', '{"a": 1}');
SELECT id, name, JSON_EXTRACT(doc, '$.a'), REGEXP_REPLACE(name, '[a]', '') FROM smoke.t;
SELECT @@have_ssl, @@version_ssl_library, SHA2('pano', 256);
"@
    & "$B/bin/mariadb.exe" @Client -e $Query
    if ($LASTEXITCODE -ne 0) { throw 'queries failed' }
    & "$B/bin/mariadb-dump.exe" @Client smoke | Out-File "$T/dump.sql"
    if (-not (Select-String -Path "$T/dump.sql" -Pattern 'CREATE TABLE `t`' -Quiet)) { throw 'dump failed' }

    & "$B/bin/mariadb-admin.exe" @Client shutdown
    if (-not $Server.WaitForExit(60000)) { throw 'server did not stop' }
    Write-Host 'PASS'
} finally {
    if (-not $Server.HasExited) { $Server.Kill() }
    Remove-Item -Recurse -Force $T -ErrorAction SilentlyContinue
}
