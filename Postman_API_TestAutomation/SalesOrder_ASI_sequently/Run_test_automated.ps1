# ===================================================================
# KONFIGURACJA TESTU - Edytuj tylko te wartosci
# ===================================================================

# Sciezka bazowa do folderu z projektem testowym - tutaj zmienić sobie
$basePath = "C:\Users\sebastian.wutke.CDN\Desktop"

# Liczba glownych "powtorzen" calego testu wydajnosciowego
$ITERATIONS = 1

# --- Zakres uzytkownikow do uruchomienia ---
# Podaj zakres uzytkownikow z pliku JSON, ktorych chcesz uzyc (np. od 1 do 10).
# Numeracja jest zgodna z kolejnoscia w pliku.
$startUser = 1
# Ustaw na 0, zeby uruchomic WSZYSTKICH uzytkownikow z pliku.
$endUser = 4


# ===================================================================
# SCIEZKI DO PLIKOW - Zbudowane automatycznie (nie ruszac i nie zmieniac nazw plikow)
# ===================================================================

# === SEKCJA SCIEZEK ===
# Folder projektu
$projectFolder = Join-Path -Path $basePath -ChildPath "Postman_API_TestAutomation\SalesOrder_ASI_sequently"
$logFolder = Join-Path -Path $projectFolder -ChildPath "user_logs"
$collectionPath = Join-Path -Path $projectFolder -ChildPath "AAT_SO_ASI_sequently.postman_collection.json"
$environmentPath = Join-Path -Path $projectFolder -ChildPath "SO_ASI.postman_environment.json"
$dataPath = Join-Path -Path $projectFolder -ChildPath "TD_AAT_SalesOrder_Sequently.json"
$newmanPath = Join-Path -Path $env:APPDATA -ChildPath "npm\newman.cmd"
# === KONIEC SEKCJI ===

# ===================================================================
# SILNIK SKRYPTU - Nie wymaga modyfikacji
# ===================================================================

# --- Weryfikacja plików i folderów ---
Write-Host "Sprawdzanie sciezek do plikow..." -ForegroundColor Gray
if (-not (Test-Path $newmanPath)) { Write-Host "KRYTYCZNY BLAD: Nie znaleziono Newman..." -ForegroundColor Red; Read-Host; exit 1 }
if (-not (Test-Path $collectionPath)) { Write-Host "KRYTYCZNY BLAD: Nie znaleziono pliku KOLEKCJI..." -ForegroundColor Red; Read-Host; exit 1 }
if (-not (Test-Path $environmentPath)) { Write-Host "KRYTYCZNY BLAD: Nie znaleziono pliku SRODOWISKA..." -ForegroundColor Red; Read-Host; exit 1 }
if (-not (Test-Path $dataPath)) { Write-Host "KRYTYCZNY BLAD: Nie znaleziono pliku DANYCH..." -ForegroundColor Red; Read-Host; exit 1 }
if (-not (Test-Path $logFolder)) { New-Item -ItemType Directory -Path $logFolder | Out-Null }
Write-Host "Wszystkie pliki i foldery sa gotowe." -ForegroundColor Green


# --- Przygotowanie danych dla uzytkownikow ---
$tempDataFolder = Join-Path -Path $projectFolder -ChildPath "temp_data"
if (Test-Path $tempDataFolder) { Remove-Item -Path $tempDataFolder -Recurse -Force }
New-Item -ItemType Directory -Path $tempDataFolder | Out-Null
try {
    $allUsersData = Get-Content -Path $dataPath -Raw | ConvertFrom-Json
    
    # --- ZMIANA: Filtrowanie uzytkownikow na podstawie zakresu ---
    if ($endUser -gt 0) {
        Write-Host "Aktywowano zakres: filtruje uzytkownikow od $startUser do $endUser." -ForegroundColor Cyan
        # Indeksowanie tablicy zaczyna sie od 0
        $startIndex = $startUser - 1
        $endIndex = $endUser - 1
        
        # Zabezpieczenie przed przekroczeniem zakresu
        if ($endIndex -ge $allUsersData.Count) {
            $endIndex = $allUsersData.Count - 1
        }
        
        $selectedUsersData = $allUsersData[$startIndex..$endIndex]
    } else {
        Write-Host "Uruchamiam test dla WSZYSTKICH uzytkownikow znalezionych w pliku." -ForegroundColor Cyan
        $selectedUsersData = $allUsersData
    }

    $userCount = $selectedUsersData.Count
    if ($userCount -eq 0) { throw "Nie znaleziono zadnych uzytkownikow w podanym zakresie." }

    Write-Host "Przygotowuje dane dla $userCount uzytkownikow..." -ForegroundColor Green

    for ($i = 0; $i -lt $userCount; $i++) {
        $userData = $selectedUsersData[$i]
        $jsonContent = ConvertTo-Json -InputObject @($userData) -Compress
        $tempDataFile = Join-Path -Path $tempDataFolder -ChildPath "user_$($i+1).json"
        $jsonContent | Out-File -FilePath $tempDataFile -Encoding utf8
    }
} catch {
    Write-Host "KRYTYCZNY BLAD: $_" -ForegroundColor Red; Read-Host "Nacisnij Enter, aby zakonczyc"; exit 1
}


# Zapisz czas rozpoczecia calego testu
$totalStartTime = Get-Date
Write-Host "Test wydajnosciowy dla $userCount uzytkownikow rozpoczety o: $totalStartTime" -ForegroundColor Green

# Zmienne do podsumowania wszystkich iteracji
$totalSummary = @{ SuccessfulRuns = 0; FailedRuns = 0; AbortedRuns = 0 }

# Petla glownych iteracji (powtorzen testu)
for ($iteration = 1; $iteration -le $ITERATIONS; $iteration++) {
    Write-Host "Rozpoczynam iteracje $iteration z $ITERATIONS" -ForegroundColor Cyan
    $iterationStartTime = Get-Date
    
    $processes = @()

    # Uruchom testy dla kazdego uzytkownika JEDNOCZESNIE
    for ($i = 1; $i -le $userCount; $i++) {
        $logFile = Join-Path -Path $logFolder -ChildPath "iter${iteration}_user_$i.log"
        $currentUserDataFile = Join-Path -Path $tempDataFolder -ChildPath "user_${i}.json"
        
        try {
            $argumenty = "run `"$collectionPath`" -e `"$environmentPath`" -d `"$currentUserDataFile`" -n 1"
            $process = Start-Process -NoNewWindow -FilePath $newmanPath -ArgumentList $argumenty -RedirectStandardOutput $logFile -PassThru
            $processes += $process
        } catch {
            Write-Host "Iteracja ${iteration} - KRYTYCZNY BLAD przy uruchamianiu procesu dla uzytkownika $i" -ForegroundColor Red
        }
    }
    Write-Host "Uruchomiono $userCount rownoczesnych uzytkownikow." -ForegroundColor Yellow

    # Czekaj na zakonczenie wszystkich procesow
    Write-Host "Iteracja ${iteration} - Czekam na zakonczenie testow..." -ForegroundColor Cyan

    $allDone = $false
    $timeout = 1800  # 30 minut
    $elapsed = 0
    $interval = 5  

    while (-not $allDone -and $elapsed -lt $timeout) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        $runningProcesses = $processes | Where-Object { -not $_.HasExited }
        
        if ($runningProcesses.Count -eq 0) { $allDone = $true } 
        else { Write-Host "Iteracja ${iteration} - Nadal trwa: $($runningProcesses.Count) procesow..." -ForegroundColor Yellow }
    }

    if (-not $allDone) {
        Write-Host "Iteracja ${iteration} - OSTRZEZENIE: Przekroczono limit czasu ($timeout s)." -ForegroundColor Yellow
        $processes | Where-Object { -not $_.HasExited } | ForEach-Object { Stop-Process -Id $_.Id -Force }
    }

    # Analiza wynikow
    $iterationSummary = @{ SuccessfulRuns = 0; FailedRuns = 0; AbortedRuns = 0 }

    for ($i = 1; $i -le $userCount; $i++) {
        $logFile = Join-Path -Path $logFolder -ChildPath "iter${iteration}_user_$i.log"
        if (Test-Path $logFile) {
            $content = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
            if ($content -match "One or more parallel requests failed. STOPPING COLLECTION." -or $content -match "Poprzednie żądanie nie powiodło się, przerywam wykonywanie kolekcji") {
                $iterationSummary.AbortedRuns++
            }
            elseif ($content -match "Całkowity czas wykonania:") {
                $iterationSummary.SuccessfulRuns++
            }
            else {
                $iterationSummary.FailedRuns++
            }
        } else {
            $iterationSummary.FailedRuns++
        }
    }
    
    $totalSummary.SuccessfulRuns += $iterationSummary.SuccessfulRuns
    $totalSummary.FailedRuns += $iterationSummary.FailedRuns
    $totalSummary.AbortedRuns += $iterationSummary.AbortedRuns
    
    Write-Host "Iteracja ${iteration} - Podsumowanie: Udane: $($iterationSummary.SuccessfulRuns), Nieudane: $($iterationSummary.FailedRuns), Przerwane: $($iterationSummary.AbortedRuns)" -ForegroundColor Cyan
    
    if ($iteration -lt $ITERATIONS) {
        Write-Host "Pauza 5 sekund przed nastepna iteracja..." -ForegroundColor Cyan
        Start-Sleep -Seconds 5
    }
}

# --- Sprzatanie po testach ---
Write-Host "Sprzatam pliki tymczasowe..." -ForegroundColor Gray
Remove-Item -Path $tempDataFolder -Recurse -Force

# Oblicz calkowity czas trwania i podsumuj
$totalEndTime = Get-Date
$totalDuration = $totalEndTime - $totalStartTime
$summaryFile = "$projectFolder\podsumowanie_testu.txt"
"Podsumowanie testu wydajnosciowego" | Out-File $summaryFile -Force
"---------------------------------------" | Out-File $summaryFile -Append
"Data: $(Get-Date)" | Out-File $summaryFile -Append
"Kolekcja: $($collectionPath | Split-Path -Leaf)" | Out-File $summaryFile -Append
"Liczba powtorzen testu: $ITERATIONS" | Out-File $summaryFile -Append
"Liczba jednoczesnych uzytkownikow: $userCount" | Out-File $summaryFile -Append
"Calkowity czas testu: $($totalDuration.TotalSeconds) sekund" | Out-File $summaryFile -Append
"---------------------------------------" | Out-File $summaryFile -Append
"Przebiegi udane: $($totalSummary.SuccessfulRuns)" | Out-File $summaryFile -Append
"Przebiegi nieudane: $($totalSummary.FailedRuns)" | Out-File $summaryFile -Append
"Przebiegi przerwane przez blad: $($totalSummary.AbortedRuns)" | Out-File $summaryFile -Append

# Wyswietl podsumowanie w konsoli
Write-Host "-------------------- PODSUMOWANIE --------------------" -ForegroundColor Magenta
Write-Host "- Calkowity czas testu: $($totalDuration.TotalSeconds) sekund" -ForegroundColor Cyan
Write-Host "- Przebiegi udane: $($totalSummary.SuccessfulRuns)" -ForegroundColor Green
Write-Host "- Przebiegi nieudane: $($totalSummary.FailedRuns)" -ForegroundColor Red
Write-Host "- Przebiegi przerwane przez blad: $($totalSummary.AbortedRuns)" -ForegroundColor Yellow
Write-Host "Szczegolowe logi znajduja sie w folderze: $logFolder" -ForegroundColor White
Write-Host "------------------------------------------------------" -ForegroundColor Magenta

# Pauza na koncu
Write-Host "Nacisnij dowolny klawisz, aby zakonczyc..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")