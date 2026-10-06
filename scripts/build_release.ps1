<#
.SYNOPSIS
    KYRON Flutter release APK builder - ASCII workspace workaround for OneDrive/non-ASCII paths.
.DESCRIPTION
    Flutter AOT compiler (Dart kernel) fails on Windows paths with non-ASCII characters (e.g., OneDrive "Masaüstü").
    This script syncs the project to a clean ASCII path, builds release APK there, and copies result back.
    Designed to be idempotent, safe, and return proper exit codes.

    Supabase wiring (added after "forced update never appeared" incident):
    `String.fromEnvironment('SUPABASE_URL' / 'SUPABASE_ANON_KEY')` is resolved at COMPILE time.
    A plain `flutter build apk --release` compiles them as EMPTY strings, which silently disables
    both telemetry and the whole app-update subsystem (UpdateConfigProvider throws before any HTTP call).

    This script therefore reads those two values from a dot-env file and forwards them as
    `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.

    Resolution order (first match wins per key, root file has priority):
      1. <project>\.env.local
      2. <project>\web\.env.local
      3. <project>\.env

    Accepted key names:
      SUPABASE_URL             <- VITE_SUPABASE_URL
      SUPABASE_ANON_KEY        <- SUPABASE_PUBLISHABLE_KEY
                              <- VITE_SUPABASE_ANON_KEY
                              <- VITE_SUPABASE_PUBLISHABLE_KEY

    Secrets are NEVER printed: only `<set, length=N>` / `<empty>` masks reach the console, and the
    logged command line is redacted. If the values are missing the build ABORTS (exit 2) instead of
    silently shipping an APK with empty defines - pass -AllowMissingSupabase to opt out.

    Hardening note: this Flutter version also supports `--dart-define-from-file=<file.env>`, which
    keeps the secret out of the process command line entirely. Not used yet to keep the documented
    `--dart-define=` contract.
.NOTES
    Usage: powershell -ExecutionPolicy Bypass -File .\scripts\build_release.ps1 [--dart-define=KEY=VALUE ...]
    All additional args are passed through to `flutter build apk --release` and, for identical keys,
    take precedence over the values resolved from the dot-env file.
#>

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArgs = @(),

    # Degerler bulunamazsa build'i durdurma; SUPABASE_* tanimsiz (bos) gecer.
    [switch]$AllowMissingSupabase
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Configuration ---
$ProjectRoot   = Split-Path -Parent $PSScriptRoot
$BuildWorkspace = 'C:\flutter_build\kyron_release'
$OutputDir     = Join-Path $ProjectRoot 'build\app\outputs\apk\release'
$SyncExcludes  = @(
    '.git', '.github', '.idea', '.vscode',
    'build', '.dart_tool', '.flutter-plugins*',
    '*.log', '*.iml', '*.iws',
    'node_modules', 'dist', '*.tsbuildinfo',
    '*.local', '.env', '.env.*',
    'android/app/build', 'android/.gradle',
    'web/node_modules', 'web/dist', 'web/.vite'
)

# --- Helpers ---
function Write-Log { param([string]$Msg) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Msg" -ForegroundColor Cyan }
function Write-Err { param([string]$Msg) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ERROR: $Msg" -ForegroundColor Red }
function Write-Ok  { param([string]$Msg) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] OK: $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] WARN: $Msg" -ForegroundColor Yellow }

# --- Secret-safe dot-env helpers -------------------------------------------
# Bir dot-env dosyasini okur. Bos satirlar, '#' yorumlari, 'export ' prefiksi ve
# tek/cift tirnakli degerler desteklenir. Hicbir deger loglanmaz.
function Read-DotEnvFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }

    foreach ($raw in [System.IO.File]::ReadAllLines($Path)) {
        $line = $raw.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith('#')) { continue }
        if ($line.StartsWith('export ')) { $line = $line.Substring(7).Trim() }

        $sep = $line.IndexOf('=')
        if ($sep -lt 1) { continue }

        $key = $line.Substring(0, $sep).Trim()
        $val = $line.Substring($sep + 1).Trim()
        if ($key.Length -eq 0) { continue }

        if ($val.Length -ge 2) {
            if ($val.StartsWith('"') -and $val.EndsWith('"')) {
                $val = $val.Substring(1, $val.Length - 2)
            } elseif ($val.StartsWith("'") -and $val.EndsWith("'")) {
                $val = $val.Substring(1, $val.Length - 2)
            }
        }

        $map[$key] = $val
    }

    return $map
}

# Ilk bos olmayan adayi dondurur.
function Select-FirstNonEmpty {
    param([object[]]$Candidates)
    foreach ($c in $Candidates) {
        if ($null -ne $c -and -not [string]::IsNullOrWhiteSpace([string]$c)) { return ([string]$c).Trim() }
    }
    return ''
}

# Secret degerini asla gostermez; yalnizca varlik/uzunluk bilgisi verir.
function Format-SecretMask {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '<BOS>' }
    return "<set, length=$(([string]$Value).Trim().Length)>"
}

# Arguman listesini loglanabilir hale getirir: -D / --dart-define degerleri redakte edilir.
# Arguman listesini loglanabilir hale getirir: -D / --dart-define degerleri redakte edilir.
# NOT: Parametre adi kasitli olarak $Args DEGIL. $args PowerShell'in otomatik
# degiskenidir; ayni isimli parametre baglanmaz ve fonksiyon BOS doner.
function Format-MaskedArgs {
    param([string[]]$ArgList)
    $out = @()
    foreach ($a in $ArgList) {
        if ($null -eq $a) { continue }
        if ($a -like '--dart-define=*' -or $a -like '-D*=*') {
            $eq = $a.IndexOf('=')
            if ($eq -ge 0) { $out += $a.Substring(0, $eq + 1) + '<redacted>' } else { $out += '<redacted>' }
        } else {
            $out += $a
        }
    }
    return $out
}

# Dot-env dosyalarindan SUPABASE_* degerlerini cozer ve --dart-define argumanlarini uretir.
function Resolve-SupabaseDefineArgs {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    # Not: robocopy senkronu '.env' / '.env.*' dosyalarini workspace'e KOPYALAMAZ
    # (bkz. $SyncExcludes). Bu yuzden cozumleme kaynak proje uzerinde yapilir.
    $searchPaths = @(
        (Join-Path $ProjectRoot '.env.local'),
        (Join-Path $ProjectRoot 'web\.env.local'),
        (Join-Path $ProjectRoot '.env')
    )

    $values = @{}
    foreach ($p in $searchPaths) {
        if (Test-Path -LiteralPath $p) {
            $kv = Read-DotEnvFile -Path $p
            foreach ($k in $kv.Keys) {
                if (-not $values.ContainsKey($k)) { $values[$k] = $kv[$k] }
            }
            Write-Log "Env source: $p ($($kv.Count) key)"
        }
    }

    $url = Select-FirstNonEmpty @(
        $values['SUPABASE_URL'],
        $values['VITE_SUPABASE_URL']
    )
    $anon = Select-FirstNonEmpty @(
        $values['SUPABASE_ANON_KEY'],
        $values['SUPABASE_PUBLISHABLE_KEY'],
        $values['VITE_SUPABASE_ANON_KEY'],
        $values['VITE_SUPABASE_PUBLISHABLE_KEY']
    )

    Write-Log "Resolved SUPABASE_URL=$(Format-SecretMask $url)"
    Write-Log "Resolved SUPABASE_ANON_KEY=$(Format-SecretMask $anon)"

    if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($anon)) {
        return @()
    }

    return @(
        "--dart-define=SUPABASE_URL=$url",
        "--dart-define=SUPABASE_ANON_KEY=$anon"
    )
}

# --- Validate source ---
if (-not (Test-Path (Join-Path $ProjectRoot 'pubspec.yaml'))) {
    Write-Err "Project root not found: $ProjectRoot"
    exit 1
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Err "flutter not in PATH"
    exit 1
}

# --- Resolve Supabase compile-time defines ---
# SUPABASE_URL / SUPABASE_ANON_KEY compile-time tanimsiz kalirsa telemetri VE
# update sistemi sessizce devre disi kalir. Bu yuzden eksikse build durdurulur.
$DefineArgs = @(Resolve-SupabaseDefineArgs -ProjectRoot $ProjectRoot)
if ($DefineArgs.Count -eq 0) {
    if ($AllowMissingSupabase) {
        Write-Warn "Supabase degerleri cozulemedi; -AllowMissingSupabase verildigi icin build SUPABASE_* BOS olarak devam ediyor (telemetry + update devre disi kalir)."
    } else {
        Write-Err "SUPABASE_URL ve/veya SUPABASE_ANON_KEY cozulemedi."
        Write-Err "Beklenen dosyalar: .env.local, web\.env.local, .env"
        Write-Err "Anahtar adlari: SUPABASE_URL | VITE_SUPABASE_URL  ve  SUPABASE_ANON_KEY | VITE_SUPABASE_ANON_KEY"
        Write-Err "Bilerek bos build istiyorsan: -AllowMissingSupabase"
        exit 2
    }
} else {
    Write-Ok "dart-define uretildi: SUPABASE_URL, SUPABASE_ANON_KEY (degerler maskeli)"
}

# --- Prepare ASCII workspace ---
Write-Log "Preparing ASCII build workspace: $BuildWorkspace"
if (Test-Path $BuildWorkspace) {
    # DIKKAT: Her ogeler parantez icinde. Virguller parantezsiz yazilsaydi
    # PowerShell onlari Join-Path'in arguman listesine eklerdi ve -ChildPath
    # 'System.Object[]' donusum hatasi verirdi.
    $cleanDirs = @(
        (Join-Path $BuildWorkspace 'build'),
        (Join-Path $BuildWorkspace '.dart_tool'),
        (Join-Path $BuildWorkspace 'android\app\build'),
        (Join-Path $BuildWorkspace 'android\.gradle')
    )
    foreach ($d in $cleanDirs) {
        if (Test-Path $d) { Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue }
    }
} else {
    New-Item -ItemType Directory -Force -Path $BuildWorkspace | Out-Null
}

# --- Sync source to workspace (robocopy for speed & Unicode safety) ---
Write-Log "Syncing source to workspace..."
$excludeDirs = $SyncExcludes | Where-Object { $_ -notlike '*.*' }
$excludeFiles = $SyncExcludes | Where-Object { $_ -like '*.*' }
$robocopyArgs = @(
    $ProjectRoot, $BuildWorkspace,
    '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS',
    '/XJ', '/COPY:DAT', '/MT:8'
)
# DIKKAT: /XD ve /XF argumanlari AYRI TOKEN olarak verilir.
# Tek string halinde ("/XD build node_modules ...") PowerShell bunu native
# komuta tirnakli gecer ve robocopy ayristiramaz -> exit code 16.
if ($excludeDirs.Count -gt 0)  { $robocopyArgs += '/XD'; $robocopyArgs += $excludeDirs }
if ($excludeFiles.Count -gt 0) { $robocopyArgs += '/XF'; $robocopyArgs += $excludeFiles }

$rc = robocopy @robocopyArgs
if ($LASTEXITCODE -ge 8) {
    Write-Err "robocopy failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}
Write-Ok "Sync complete (robocopy exit: $LASTEXITCODE)"

# --- Build in workspace ---
Write-Log "Starting Flutter release build in workspace..."
Push-Location $BuildWorkspace
try {
    # Supabase define'lar once, kullanici argumanlari sonra gelir; boylece ayni
    # anahtarda kullanicinin acikca gectigi deger sonraki konumda durur.
    $allArgs = @('build', 'apk', '--release') + $DefineArgs + $FlutterArgs
    $argString = $allArgs -join ' '

    # Loglanabilir kopya uret: -D / --dart-define degerleri redakte edilir.
    $maskedArgs = Format-MaskedArgs -ArgList $allArgs
    Write-Log "Command: flutter $($maskedArgs -join ' ')"

    $proc = Start-Process -FilePath 'flutter' -ArgumentList $argString -Wait -PassThru -NoNewWindow
    $exitCode = $proc.ExitCode
    if ($exitCode -ne 0) {
        Write-Err "flutter build failed with exit code $exitCode"
        exit $exitCode
    }
    Write-Ok "Flutter build succeeded"
} finally {
    Pop-Location
}

# --- Copy APKs back to project output dir ---
Write-Log "Copying release APKs back to project..."
$wsApks = Get-ChildItem -Path (Join-Path $BuildWorkspace 'build\app\outputs\flutter-apk') -Filter '*.apk' -Recurse -ErrorAction SilentlyContinue
if (-not $wsApks) {
    Write-Err "No APK found in workspace output"
    exit 1
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
foreach ($apk in $wsApks) {
    $dest = Join-Path $OutputDir $apk.Name
    Copy-Item -Path $apk.FullName -Destination $dest -Force
    $sizeMB = [Math]::Round($apk.Length / 1MB, 1)
    Write-Ok "Copied: $($apk.Name) ($sizeMB MB) -> $OutputDir"
}

# --- Verify APK exists ---
$finalApk = Get-ChildItem -Path $OutputDir -Filter 'app-release.apk' -ErrorAction SilentlyContinue
if (-not $finalApk) {
    Write-Err "Expected app-release.apk not found in $OutputDir"
    exit 1
}

Write-Ok "Release build completed successfully."
Write-Log "Output: $($finalApk.FullName) ($([Math]::Round($finalApk.Length / 1MB, 1)) MB)"
exit 0