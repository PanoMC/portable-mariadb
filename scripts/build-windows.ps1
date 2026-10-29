# Builds a portable MariaDB server package for one Windows target with MSVC.
# Usage: scripts/build-windows.ps1 -Target windows-x64|windows-arm64|windows-x86
# Needs Visual Studio 2022 (C++), CMake, Strawberry Perl and bison (choco install winflexbison3).
# Output: dist/portable-mariadb-<version>-r<rev>-<target>.zip (+ .sha256)
param([Parameter(Mandatory = $true)][string]$Target)
$ErrorActionPreference = 'Stop'

$Root = Resolve-Path "$PSScriptRoot/.."
$Versions = @{}
Get-Content "$Root/versions.env" | Where-Object { $_ -match '^\s*([A-Z0-9_]+)=(.*)$' } | ForEach-Object {
    $Versions[$Matches[1]] = $Matches[2].Trim()
}
$Version = $Versions.MARIADB_VERSION
$Revision = $Versions.REVISION

$Arch = switch ($Target) {
    'windows-x64' { 'x64' }
    'windows-arm64' { 'ARM64' }
    'windows-x86' { 'Win32' }
    default { throw "unknown target $Target" }
}

$Name = "portable-mariadb-$Version-r$Revision-$Target"
$Work = "$Root/.work/$Target"
$Src = "$Work/src"
$Build = "$Work/build"
$Stage = "$Work/stage"
$Pkg = "$Work/$Name"
$Dist = "$Root/dist"
$Cache = "$Root/.cache"
$Tarball = "$Cache/mariadb-$Version.tar.gz"

New-Item -ItemType Directory -Force -Path $Cache, $Dist | Out-Null
if (-not (Test-Path $Tarball) -or (Get-FileHash $Tarball -Algorithm SHA256).Hash -ne $Versions.MARIADB_SHA256) {
    $Url = "https://archive.mariadb.org/mariadb-$Version/source/mariadb-$Version.tar.gz"
    Write-Host "Downloading $Url"
    # curl.exe ships with Windows 10+ and matches fetch-source.sh.
    curl.exe -fsSL --retry 5 --retry-delay 5 -o "$Tarball.part" $Url
    if ($LASTEXITCODE -ne 0) { throw "downloading $Url failed" }
    Move-Item -Force "$Tarball.part" $Tarball
}
if ((Get-FileHash $Tarball -Algorithm SHA256).Hash -ne $Versions.MARIADB_SHA256) {
    throw "SHA-256 mismatch for $Tarball"
}

if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Force -Path $Src, $Build, $Stage | Out-Null
tar -xzf $Tarball -C $Src --strip-components=1
if ($LASTEXITCODE -ne 0) { throw 'extracting the source failed' }

# Same feature set as build-unix.sh. The CRT is linked statically, so no VC++ redistributable is needed.
$CmakeArgs = @(
    '-S', $Src, '-B', $Build, '-G', 'Visual Studio 17 2022', '-A', $Arch,
    '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
    '-DWITH_SSL=bundled', '-DWITH_ZLIB=bundled', '-DWITH_PCRE=bundled', '-DWITH_LIBFMT=bundled',
    '-DWITH_WSREP=OFF', '-DWITH_EMBEDDED_SERVER=OFF', '-DWITH_UNIT_TESTS=OFF', '-DCONC_WITH_UNIT_TESTS=OFF',
    '-DWITH_MARIABACKUP=OFF', '-DMSVC_CRT_TYPE=/MT',
    '-DPLUGIN_ROCKSDB=NO', '-DPLUGIN_DUCKDB=NO', '-DPLUGIN_MROONGA=NO', '-DPLUGIN_SPIDER=NO', '-DPLUGIN_CONNECT=NO',
    '-DPLUGIN_COLUMNSTORE=NO', '-DPLUGIN_S3=NO', '-DPLUGIN_OQGRAPH=NO', '-DPLUGIN_SPHINX=NO',
    '-DPLUGIN_AUTH_GSSAPI=NO', '-DPLUGIN_AUTH_GSSAPI_CLIENT=NO', '-DPLUGIN_HASHICORP_KEY_MANAGEMENT=NO',
    '-DPLUGIN_AWS_KEY_MANAGEMENT=NO', '-DPLUGIN_PROVIDER_BZIP2=NO', '-DPLUGIN_PROVIDER_LZ4=NO',
    '-DPLUGIN_PROVIDER_LZMA=NO', '-DPLUGIN_PROVIDER_LZO=NO', '-DPLUGIN_PROVIDER_SNAPPY=NO',
    '-DCMAKE_DISABLE_FIND_PACKAGE_Boost=ON', '-DCMAKE_DISABLE_FIND_PACKAGE_LibXml2=ON',
    '-DCMAKE_DISABLE_FIND_PACKAGE_CURL=ON'
)
cmake @CmakeArgs
if ($LASTEXITCODE -ne 0) { throw 'cmake configure failed' }
cmake --build $Build --config RelWithDebInfo --parallel
if ($LASTEXITCODE -ne 0) { throw 'build failed' }
cmake --install $Build --config RelWithDebInfo --prefix $Stage | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'install failed' }

New-Item -ItemType Directory -Force -Path "$Pkg/bin", "$Pkg/lib/plugin" | Out-Null
$Tools = 'mariadbd', 'mariadb', 'mariadb-admin', 'mariadb-dump', 'mariadb-upgrade', 'mariadb-check',
    'mariadb-install-db', 'my_print_defaults'
foreach ($Tool in $Tools) {
    Copy-Item "$Stage/bin/$Tool.exe" "$Pkg/bin/"
}
Copy-Item -Recurse "$Stage/share" "$Pkg/share"
$Excluded = Get-Content "$Root/package/excluded-plugins.txt" | Where-Object { $_ }
Get-ChildItem "$Stage/lib/plugin" -Filter '*.dll' -ErrorAction SilentlyContinue |
    Where-Object { $Excluded -notcontains $_.BaseName } | Copy-Item -Destination "$Pkg/lib/plugin/"
Copy-Item "$Src/COPYING" "$Pkg/COPYING"
Copy-Item "$Root/package/README.txt" "$Pkg/README.txt"
"MariaDB $Version, portable-mariadb r$Revision, target $Target" | Set-Content -NoNewline "$Pkg/VERSION"

# Only Windows system DLLs may be imported.
$Dumpbin = Get-ChildItem "${env:ProgramFiles}/Microsoft Visual Studio" -Recurse -Filter dumpbin.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'Hostx64\\x64' } | Select-Object -First 1
if ($Dumpbin) {
    $Allowed = '^(kernel32|advapi32|ws2_32|user32|shell32|ole32|oleaut32|shlwapi|secur32|crypt32|bcrypt|ncrypt|version|dbghelp|psapi|iphlpapi|userenv|mswsock|rpcrt4|netapi32|api-ms-win-.*|ntdll|kernelbase|mariadbd)\.(dll|exe)$'
    foreach ($File in Get-ChildItem "$Pkg/bin", "$Pkg/lib/plugin" -Include '*.exe', '*.dll' -Recurse) {
        $Deps = & $Dumpbin.FullName /nologo /dependents $File.FullName | Where-Object { $_ -match '^\s+\S+\.(dll|exe)\s*$' } | ForEach-Object { $_.Trim() }
        foreach ($Dep in $Deps) {
            if ($Dep.ToLower() -notmatch $Allowed) { throw "$($File.Name) imports non-system DLL $Dep" }
        }
    }
}

$Zip = "$Dist/$Name.zip"
if (Test-Path $Zip) { Remove-Item $Zip }
Compress-Archive -Path $Pkg -DestinationPath $Zip -CompressionLevel Optimal
$Hash = (Get-FileHash $Zip -Algorithm SHA256).Hash.ToLower()
"$Hash  $Name.zip" | Set-Content -NoNewline "$Zip.sha256"
Write-Host "Built $Zip ($([math]::Round((Get-Item $Zip).Length / 1MB, 1)) MB)"
