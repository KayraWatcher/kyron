# GECICI - donma ani kanit toplayici. Olcumden sonra SILINECEK.
$S = Split-Path -Parent $MyInvocation.MyCommand.Path
$D = "CUFEMVTGNR4L4TU4"
$Port = "35717"
$Auth = "7RlctrTBj1w="

function W([string]$f, [string]$m) {
  $m | Out-File -FilePath (Join-Path $S $f) -Append -Encoding UTF8
}
function Reset([string]$f) { Remove-Item (Join-Path $S $f) -Force -ErrorAction SilentlyContinue }

Reset "now_chain.txt"; Reset "now_notes.txt"

# ---------- 1) BOZULMADAN ONCE: ekran + FRZ zinciri ----------
adb -s $D shell screencap -p /sdcard/now.png 2>&1 | Out-Null
adb -s $D pull /sdcard/now.png (Join-Path $S "now.png") 2>&1 | Out-Null

$chain = @(adb -s $D logcat -d -s flutter:I 2>&1 | Select-String -Pattern "FRZ" |
             ForEach-Object { $_.Line })
$chain | Out-File (Join-Path $S "now_chain.txt") -Encoding UTF8
W "now_notes.txt" "FRZ toplam satir: $($chain.Count)"
W "now_notes.txt" "SON 40 FRZ:"
$chain | Select-Object -Last 40 | ForEach-Object { W "now_notes.txt" $_ }

# FRZ disi flutter hatalari (exception vb.)
$other = @(adb -s $D logcat -d -s flutter:I 2>&1 |
             Select-String -Pattern "FRZ" -NotMatch | Select-Object -Last 40 |
             ForEach-Object { $_.Line })
W "now_notes.txt" "SON 40 NON-FRZ FLUTTER LOG:"
$other | ForEach-Object { W "now_notes.txt" $_ }

# ---------- 2) VM service yigin + bellek ----------
& dart (Join-Path $S "frz_stack.dart") $Port $Auth stack 2>&1 |
  Out-File (Join-Path $S "now_stack.txt") -Encoding UTF8

# ---------- 3) process / thread / cpu / bellek ----------
$p = ("$(adb -s $D shell pidof com.goldapp.gold)").Trim()
W "now_notes.txt" "pid=$p"
adb -s $D shell "ps -T -p $p" 2>&1 | Out-File (Join-Path $S "now_threads.txt") -Encoding UTF8
adb -s $D shell top -H -b -n 3 -d 2 -q -p $p 2>&1 |
  Select-String -Pattern "goldapp" | Out-File (Join-Path $S "now_top.txt") -Encoding UTF8
adb -s $D shell dumpsys meminfo com.goldapp.gold 2>&1 |
  Select-String -Pattern "TOTAL PSS|Native Heap|Java Heap" |
  ForEach-Object { $_.Line } | Out-File (Join-Path $S "now_mem.txt") -Encoding UTF8

# ---------- 4) input dispatch ----------
adb -s $D shell dumpsys input 2>&1 |
  Select-String -Pattern "PendingEvent|WaitQueue|FocusedWindow|FocusedApplication|dispatchingTimeout" |
  ForEach-Object { $_.Line } | Out-File (Join-Path $S "now_input.txt") -Encoding UTF8

# ---------- 5) frame uretimi ----------
$layer = "SurfaceView - com.goldapp.gold/com.goldapp.gold.MainActivity#0"
adb -s $D shell "dumpsys SurfaceFlinger --latency '$layer'" 2>&1 |
  Out-File (Join-Path $S "now_latency.txt") -Encoding UTF8

# ---------- 6) DENEY A: grafik pointer event aliyor mu? ----------
W "now_notes.txt" "=== DENEY A: grafik ortasina tik (540,1400) ==="
$before = $chain.Count
adb -s $D shell input tap 540 1400 2>&1 | Out-Null
Start-Sleep -Seconds 2
$after = @(adb -s $D logcat -d -s flutter:I 2>&1 | Select-String -Pattern "FRZ" |
             ForEach-Object { $_.Line })
$new = @($after | Select-Object -Skip $before)
W "now_notes.txt" "tik sonrasi yeni FRZ satir sayisi: $($new.Count)"
$new | Select-Object -Last 20 | ForEach-Object { W "now_notes.txt" ("  + " + $_) }
adb -s $D shell screencap -p /sdcard/after_tap.png 2>&1 | Out-Null
adb -s $D pull /sdcard/after_tap.png (Join-Path $S "after_tap.png") 2>&1 | Out-Null

# ---------- 7) DENEY B: grafik disindaki UI calisiyor mu? ----------
W "now_notes.txt" "=== DENEY B: 'Teknik Gorunum' sekmesine tik ==="
$beforeB = $after.Count
adb -s $D shell input tap 1050 891 2>&1 | Out-Null   # Teknik Görünüm (sol-orta)
Start-Sleep -Seconds 2
adb -s $D shell screencap -p /sdcard/after_teknik.png 2>&1 | Out-Null
adb -s $D pull /sdcard/after_teknik.png (Join-Path $S "after_teknik.png") 2>&1 | Out-Null
$afterB = @(adb -s $D logcat -d -s flutter:I 2>&1 | Select-String -Pattern "FRZ" |
              ForEach-Object { $_.Line })
$newB = @($afterB | Select-Object -Skip $beforeB)
W "now_notes.txt" "teknik sekmesi sonrasi yeni FRZ: $($newB.Count)"
$newB | Select-Object -Last 15 | ForEach-Object { W "now_notes.txt" ("  + " + $_) }

# ---------- 8) DENEY C: grafige geri don + tekrar dokunma ----------
adb -s $D shell input tap 354 891 2>&1 | Out-Null    # Grafik sekmesi
Start-Sleep -Seconds 2
adb -s $D shell screencap -p /sdcard/after_back_tab.png 2>&1 | Out-Null
adb -s $D pull /sdcard/after_back_tab.png (Join-Path $S "after_back_tab.png") 2>&1 | Out-Null

$final = @(adb -s $D logcat -d -s flutter:I 2>&1 | Select-String -Pattern "FRZ" |
             ForEach-Object { $_.Line })
W "now_notes.txt" "son toplam FRZ: $($final.Count)"
$final | Select-Object -Last 25 | ForEach-Object { W "now_notes.txt" ("  * " + $_) }

W "now_notes.txt" "Bitti: $(Get-Date -Format 'HH:mm:ss')"
Write-Output "kanit toplandi"
