$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Build = Join-Path $Root "target\native-windows-x86_64"
$Dist = Join-Path $Root "dist"
$Toolchain = if ($env:RUST_TOOLCHAIN) { $env:RUST_TOOLCHAIN } else { "1.85.1" }

New-Item -ItemType Directory -Force -Path $Build, $Dist | Out-Null
$Cl = Get-Command cl.exe -ErrorAction SilentlyContinue
if (-not $Cl) {
    $VsWhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $VsWhere)) {
        throw "Visual Studio locator was not found"
    }
    $VsRoot = (& $VsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
    $DevCmd = Join-Path $VsRoot "Common7\Tools\VsDevCmd.bat"
    if (-not (Test-Path $DevCmd)) {
        throw "Visual Studio developer environment was not found"
    }
    $EnvironmentLines = & cmd.exe /s /c "`"$DevCmd`" -no_logo -arch=x64 -host_arch=x64 >nul && set"
    foreach ($Line in $EnvironmentLines) {
        $Separator = $Line.IndexOf("=")
        if ($Separator -gt 0) {
            $Name = $Line.Substring(0, $Separator)
            $Value = $Line.Substring($Separator + 1)
            Set-Item -Path "Env:$Name" -Value $Value
        }
    }
}
$Rustc = (& rustup which --toolchain $Toolchain rustc).Trim()
$env:Path = "$(Split-Path $Rustc);$env:Path"
$env:RUSTFLAGS = "-C target-feature=+crt-static"
Push-Location $Root
try {
    cargo build --locked --release -p ferank-plugin
    cl.exe /nologo /c /O2 /W4 /WX /DSYSTEM=STWIN32 "/I$Root\plugin" `
        "$Root\plugin\stplugin.c" "/Fo$Build\stplugin.obj"
    cl.exe /nologo /c /O2 /W4 /WX /DSYSTEM=STWIN32 "/I$Root\plugin" `
        "$Root\plugin\stata_bridge.c" "/Fo$Build\stata_bridge.obj"
    link.exe /NOLOGO /DLL "/OUT:$Dist\ferank_windows.plugin" `
        /EXPORT:pginit /EXPORT:stata_call `
        "$Build\stplugin.obj" "$Build\stata_bridge.obj" `
        "$Root\target\release\ferank_plugin.lib" `
        advapi32.lib bcrypt.lib kernel32.lib ntdll.lib userenv.lib ws2_32.lib
    $Hash = (Get-FileHash -Algorithm SHA256 "$Dist\ferank_windows.plugin").Hash.ToLowerInvariant()
    "$Hash  ferank_windows.plugin" | Set-Content -Encoding ascii "$Dist\ferank_windows.plugin.sha256"
    Write-Output "Built $Dist\ferank_windows.plugin"
}
finally {
    Pop-Location
}
