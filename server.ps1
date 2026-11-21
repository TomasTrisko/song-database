param(
    [int]$Port = 8080,
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $RootDir "data"
$SongsJsonPath = Join-Path $DataDir "songs.json"
$PlaylistsJsonPath = Join-Path $DataDir "playlists.json"
$SettingsJsonPath = Join-Path $DataDir "settings.json"
$StagingRoot = Join-Path $DataDir "_staging"
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

if (-not (Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir | Out-Null
}
if (Test-Path $StagingRoot) {
    Remove-Item -Path $StagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}
if (-not (Test-Path $SongsJsonPath)) {
    [System.IO.File]::WriteAllText($SongsJsonPath, "[]", $Utf8NoBom)
}
if (-not (Test-Path $PlaylistsJsonPath)) {
    [System.IO.File]::WriteAllText($PlaylistsJsonPath, "[]", $Utf8NoBom)
}
if (-not (Test-Path $SettingsJsonPath)) {
    [System.IO.File]::WriteAllText($SettingsJsonPath, "{}", $Utf8NoBom)
}

function Get-MimeType([string]$FilePath) {
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    switch ($ext) {
        ".html" { return "text/html; charset=utf-8" }
        ".css" { return "text/css; charset=utf-8" }
        ".js" { return "application/javascript; charset=utf-8" }
        ".json" { return "application/json; charset=utf-8" }
        ".txt" { return "text/plain; charset=utf-8" }
        ".mp3" { return "audio/mpeg" }
        ".wav" { return "audio/wav" }
        ".ogg" { return "audio/ogg" }
        ".flac" { return "audio/flac" }
        ".m4a" { return "audio/mp4" }
        ".aac" { return "audio/aac" }
        ".opus" { return "audio/opus" }
        ".webm" { return "audio/webm" }
        ".png" { return "image/png" }
        ".jpg" { return "image/jpeg" }
        ".jpeg" { return "image/jpeg" }
        ".webp" { return "image/webp" }
        ".gif" { return "image/gif" }
        ".svg" { return "image/svg+xml" }
        default { return "application/octet-stream" }
    }
}

function Get-StatusText([int]$Code) {
    switch ($Code) {
        200 { return "OK" }
        201 { return "Created" }
        206 { return "Partial Content" }
        400 { return "Bad Request" }
        404 { return "Not Found" }
        416 { return "Range Not Satisfiable" }
        500 { return "Internal Server Error" }
        default { return "OK" }
    }
}

function Read-Songs {
    if (-not (Test-Path $SongsJsonPath)) { return @() }
    $raw = [System.IO.File]::ReadAllText($SongsJsonPath, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $parsed = $raw | ConvertFrom-Json
    if ($null -eq $parsed) { return @() }
    if ($parsed -is [System.Array]) { return @($parsed) }
    return @($parsed)
}

function Write-Songs($Songs) {
    $arr = @($Songs)
    if ($arr.Count -eq 0) {
        $json = "[]"
    }
    else {
        $json = ConvertTo-Json -InputObject $arr -Depth 6
        if ($arr.Count -eq 1 -and -not $json.TrimStart().StartsWith("[")) {
            $json = "[$json]"
        }
    }
    [System.IO.File]::WriteAllText($SongsJsonPath, $json, $Utf8NoBom)
}

function Read-Playlists {
    if (-not (Test-Path $PlaylistsJsonPath)) { return @() }
    $raw = [System.IO.File]::ReadAllText($PlaylistsJsonPath, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $parsed = $raw | ConvertFrom-Json
    if ($null -eq $parsed) { return @() }
    if ($parsed -is [System.Array]) { return @($parsed) }
    return @($parsed)
}

function Write-Playlists($Playlists) {
    $arr = @($Playlists)
    if ($arr.Count -eq 0) {
        $json = "[]"
    }
    else {
        $json = ConvertTo-Json -InputObject $arr -Depth 6
        if ($arr.Count -eq 1 -and -not $json.TrimStart().StartsWith("[")) {
            $json = "[$json]"
        }
    }
    [System.IO.File]::WriteAllText($PlaylistsJsonPath, $json, $Utf8NoBom)
}

function Get-SafeExtension([string]$Filename, [string]$DefaultExt) {
    if ([string]::IsNullOrWhiteSpace($Filename)) { return $DefaultExt }
    $decoded = [System.Uri]::UnescapeDataString($Filename)
    $ext = [System.IO.Path]::GetExtension($decoded).ToLowerInvariant()
    if ($ext -match "^\.[a-z0-9]{1,8}$") { return $ext }
    return $DefaultExt
}

function Read-HttpRequest($Stream) {
    $ms = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 4096
    $headerEndIndex = -1

    while ($headerEndIndex -lt 0) {
        $read = $Stream.Read($buf, 0, $buf.Length)
        if ($read -le 0) { return $null }
        $ms.Write($buf, 0, $read)
        $arr = $ms.ToArray()
        for ($i = [Math]::Max(0, $arr.Length - $read - 3); $i -le ($arr.Length - 4); $i++) {
            if ($arr[$i] -eq 13 -and $arr[$i + 1] -eq 10 -and $arr[$i + 2] -eq 13 -and $arr[$i + 3] -eq 10) {
                $headerEndIndex = $i
                break
            }
        }
        if ($arr.Length -gt 65536 -and $headerEndIndex -lt 0) { return $null }
    }

    $allBytes = $ms.ToArray()
    $headerStr = [System.Text.Encoding]::ASCII.GetString($allBytes, 0, $headerEndIndex)
    $bodyOffset = $headerEndIndex + 4
    $initialBodyLen = $allBytes.Length - $bodyOffset
    $initialBody = New-Object byte[] $initialBodyLen
    if ($initialBodyLen -gt 0) {
        [Array]::Copy($allBytes, $bodyOffset, $initialBody, 0, $initialBodyLen)
    }

    $lines = $headerStr -split "`r`n"
    if ($lines.Length -eq 0) { return $null }
    $reqParts = $lines[0] -split " "
    if ($reqParts.Length -lt 2) { return $null }

    $method = $reqParts[0].ToUpperInvariant()
    $rawTarget = $reqParts[1]
    $qIdx = $rawTarget.IndexOf("?")
    $path = if ($qIdx -ge 0) { $rawTarget.Substring(0, $qIdx) } else { $rawTarget }

    $headers = @{}
    for ($i = 1; $i -lt $lines.Length; $i++) {
        $colon = $lines[$i].IndexOf(":")
        if ($colon -gt 0) {
            $k = $lines[$i].Substring(0, $colon).Trim().ToLowerInvariant()
            $v = $lines[$i].Substring($colon + 1).Trim()
            $headers[$k] = $v
        }
    }

    $contentLength = [long]0
    if ($headers.ContainsKey("content-length")) {
        [long]::TryParse($headers["content-length"], [ref]$contentLength) | Out-Null
    }

    return [PSCustomObject]@{
        Method        = $method
        Path          = $path
        Headers       = $headers
        ContentLength = $contentLength
        InitialBody   = $initialBody
    }
}

function Read-BodyBytes($Stream, $Req) {
    $total = $Req.ContentLength
    if ($total -le 0) { return [byte[]]@() }
    $out = New-Object byte[] $total
    $copied = [Math]::Min($Req.InitialBody.Length, $total)
    if ($copied -gt 0) {
        [Array]::Copy($Req.InitialBody, 0, $out, 0, $copied)
    }
    while ($copied -lt $total) {
        $read = $Stream.Read($out, $copied, [int]($total - $copied))
        if ($read -le 0) { break }
        $copied += $read
    }
    return $out
}

function Save-BodyToFile($Stream, $Req, [string]$DestPath) {
    $total = $Req.ContentLength
    $fs = [System.IO.File]::Create($DestPath)
    try {
        $written = [long]0
        if ($Req.InitialBody.Length -gt 0 -and $total -gt 0) {
            $toWrite = [int][Math]::Min($Req.InitialBody.Length, $total)
            $fs.Write($Req.InitialBody, 0, $toWrite)
            $written += $toWrite
        }
        $buf = New-Object byte[] 65536
        while ($written -lt $total) {
            $toRead = [int][Math]::Min($buf.Length, $total - $written)
            $read = $Stream.Read($buf, 0, $toRead)
            if ($read -le 0) { break }
            $fs.Write($buf, 0, $read)
            $written += $read
        }
    }
    finally {
        $fs.Close()
    }
}

function Send-TextResponse($Stream, [int]$StatusCode, [string]$Body, [string]$ContentType = "application/json; charset=utf-8") {
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $statusText = Get-StatusText $StatusCode
    $header = "HTTP/1.1 $StatusCode $statusText`r`n" +
    "Content-Type: $ContentType`r`n" +
    "Content-Length: $($bodyBytes.Length)`r`n" +
    "Cache-Control: no-cache`r`n" +
    "Connection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($bodyBytes.Length -gt 0) {
        $Stream.Write($bodyBytes, 0, $bodyBytes.Length)
    }
    $Stream.Flush()
}

function Send-FileResponse($Stream, $Req, [string]$FilePath) {
    if (-not (Test-Path $FilePath -PathType Leaf)) {
        Send-TextResponse $Stream 404 '{"error":"Soubor nenalezen"}'
        return
    }

    $fileInfo = Get-Item $FilePath
    $totalLength = $fileInfo.Length
    $mime = Get-MimeType $FilePath

    if ($totalLength -eq 0) {
        Send-TextResponse $Stream 200 "" $mime
        return
    }

    $start = [long]0
    $end = $totalLength - 1
    $isRange = $false

    if ($Req.Headers.ContainsKey("range") -and $Req.Headers["range"] -match "^bytes=(\d*)-(\d*)$") {
        $isRange = $true
        if ($Matches[1] -ne "") { $start = [long]$Matches[1] }
        if ($Matches[2] -ne "") { $end = [long]$Matches[2] }
        if ($start -ge $totalLength -or $end -ge $totalLength -or $start -gt $end) {
            $h416 = "HTTP/1.1 416 Range Not Satisfiable`r`nContent-Range: bytes */$totalLength`r`nConnection: close`r`n`r`n"
            $b416 = [System.Text.Encoding]::ASCII.GetBytes($h416)
            $Stream.Write($b416, 0, $b416.Length)
            $Stream.Flush()
            return
        }
    }

    $chunkLength = $end - $start + 1
    $statusCode = if ($isRange) { 206 } else { 200 }
    $statusText = Get-StatusText $statusCode
    $header = "HTTP/1.1 $statusCode $statusText`r`n" +
    "Content-Type: $mime`r`n" +
    "Accept-Ranges: bytes`r`n" +
    "Content-Length: $chunkLength`r`n"
    if ($isRange) {
        $header += "Content-Range: bytes $start-$end/$totalLength`r`n"
    }
    $header += "Connection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)

    $fs = [System.IO.File]::OpenRead($FilePath)
    try {
        if ($start -gt 0) {
            $fs.Seek($start, [System.IO.SeekOrigin]::Begin) | Out-Null
        }
        $buffer = New-Object byte[] 65536
        $remaining = $chunkLength
        while ($remaining -gt 0) {
            $toRead = [int][Math]::Min($buffer.Length, $remaining)
            $read = $fs.Read($buffer, 0, $toRead)
            if ($read -le 0) { break }
            $Stream.Write($buffer, 0, $read)
            $remaining -= $read
        }
        $Stream.Flush()
    }
    catch {
        # Client disconnected mid-stream (normal during audio seeking)
    }
    finally {
        $fs.Close()
    }
}

# Start TcpListener on first available port
$listener = $null
$boundPort = $Port
for ($p = $Port; $p -lt ($Port + 20); $p++) {
    $tryListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $p)
    try {
        $tryListener.Start()
        $listener = $tryListener
        $boundPort = $p
        break
    }
    catch {
        try { $tryListener.Stop() } catch {}
    }
}

if ($null -eq $listener) {
    Write-Host "Nepodarilo se spustit server na zadnem portu ($Port-$($Port+19))." -ForegroundColor Red
    exit 1
}

$url = "http://127.0.0.1:$boundPort/"
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Databaze pisnicek bezi na: $url" -ForegroundColor Green
Write-Host "  Slozka s daty: $DataDir" -ForegroundColor Gray
Write-Host "  Pro ukonceni zavrete toto okno nebo Ctrl+C" -ForegroundColor DarkGray
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

if (-not $NoBrowser) {
    Start-Process $url
}

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $client.ReceiveTimeout = 30000
            $client.SendTimeout = 30000
            $stream = $client.GetStream()
            $req = Read-HttpRequest $stream
            if ($null -eq $req) { continue }

            $method = $req.Method
            $path = $req.Path

            # GET / or /index.html
            if ($method -eq "GET" -and ($path -eq "/" -or $path -eq "/index.html")) {
                Send-FileResponse $stream $req (Join-Path $RootDir "index.html")
                continue
            }

            # GET /api/ping
            if ($method -eq "GET" -and $path -eq "/api/ping") {
                $info = @{ ok = $true; dataDir = $DataDir } | ConvertTo-Json -Compress
                Send-TextResponse $stream 200 $info
                continue
            }

            # GET /api/songs
            if ($method -eq "GET" -and $path -eq "/api/songs") {
                $raw = [System.IO.File]::ReadAllText($SongsJsonPath, [System.Text.Encoding]::UTF8)
                if ([string]::IsNullOrWhiteSpace($raw)) { $raw = "[]" }
                Send-TextResponse $stream 200 $raw
                continue
            }

            # POST /api/songs
            if ($method -eq "POST" -and $path -eq "/api/songs") {
                $bodyBytes = Read-BodyBytes $stream $req
                $bodyJson = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
                $body = $bodyJson | ConvertFrom-Json

                $title = if ($body.title) { [string]$body.title } else { "Bez názvu" }
                $artist = if ($body.artist) { [string]$body.artist } else { "" }
                $album = if ($body.album) { [string]$body.album } else { "" }
                $lyrics = if ($body.lyrics) { [string]$body.lyrics } else { "" }

                $id = "song_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + "_" + ([Guid]::NewGuid().ToString("N").Substring(0, 6))
                $songDir = Join-Path $DataDir $id
                New-Item -ItemType Directory -Path $songDir -Force | Out-Null

                if (-not [string]::IsNullOrWhiteSpace($lyrics)) {
                    [System.IO.File]::WriteAllText((Join-Path $songDir "lyrics.txt"), $lyrics, $Utf8NoBom)
                }

                $newSong = [PSCustomObject]@{
                    id        = $id
                    title     = $title.Trim()
                    artist    = $artist.Trim()
                    album     = $album.Trim()
                    lyrics    = $lyrics
                    audioFile = $null
                    coverFile = $null
                    createdAt = (Get-Date).ToString("o")
                }

                # Attach staged files from /api/import-url if provided
                if ($body.stagingToken -and ([string]$body.stagingToken -match "^[a-zA-Z0-9_-]+$")) {
                    $stageDir = Join-Path $StagingRoot ([string]$body.stagingToken)
                    if (Test-Path $stageDir) {
                        $useAudio = if ($null -ne $body.useStagedAudio) { [bool]$body.useStagedAudio } else { $true }
                        $useCover = if ($null -ne $body.useStagedCover) { [bool]$body.useStagedCover } else { $true }
                        if ($useAudio) {
                            $stAudio = Get-ChildItem $stageDir -Filter "audio.*" -File | Select-Object -First 1
                            if ($stAudio) {
                                Move-Item -Path $stAudio.FullName -Destination (Join-Path $songDir $stAudio.Name) -Force
                                $newSong.audioFile = "/data/$id/$($stAudio.Name)"
                            }
                        }
                        if ($useCover) {
                            $stCover = Get-ChildItem $stageDir -Filter "cover.*" -File | Select-Object -First 1
                            if ($stCover) {
                                Move-Item -Path $stCover.FullName -Destination (Join-Path $songDir $stCover.Name) -Force
                                $newSong.coverFile = "/data/$id/$($stCover.Name)"
                            }
                        }
                        Remove-Item -Path $stageDir -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }

                $songs = @(Read-Songs)
                $songs = @($newSong) + $songs
                Write-Songs $songs

                Send-TextResponse $stream 201 ($newSong | ConvertTo-Json -Depth 4)
                continue
            }

            # POST /api/songs/{id}/audio or /cover
            if ($method -eq "POST" -and $path -match "^/api/songs/([a-zA-Z0-9_-]+)/(audio|cover)$") {
                $id = $Matches[1]
                $kind = $Matches[2]
                $songs = @(Read-Songs)
                $target = $songs | Where-Object { $_.id -eq $id } | Select-Object -First 1

                if ($null -eq $target) {
                    Send-TextResponse $stream 404 '{"error":"Písnička nenalezena"}'
                    continue
                }

                $songDir = Join-Path $DataDir $id
                if (-not (Test-Path $songDir)) {
                    New-Item -ItemType Directory -Path $songDir -Force | Out-Null
                }

                $origName = if ($req.Headers.ContainsKey("x-filename")) { $req.Headers["x-filename"] } else { "" }
                $defaultExt = if ($kind -eq "audio") { ".mp3" } else { ".jpg" }
                $ext = Get-SafeExtension $origName $defaultExt
                $fileName = "$kind$ext"
                $destPath = Join-Path $songDir $fileName

                $oldRel = if ($kind -eq "audio") { $target.audioFile } else { $target.coverFile }
                if ($oldRel) {
                    $oldName = Split-Path -Leaf $oldRel
                    $oldPath = Join-Path $songDir $oldName
                    if ((Test-Path $oldPath) -and ($oldPath -ne $destPath)) {
                        Remove-Item $oldPath -Force -ErrorAction SilentlyContinue
                    }
                }

                Save-BodyToFile $stream $req $destPath

                $relUrl = "/data/$id/$fileName"
                if ($kind -eq "audio") {
                    $target.audioFile = $relUrl
                }
                else {
                    $target.coverFile = $relUrl
                }
                Write-Songs $songs

                Send-TextResponse $stream 200 ($target | ConvertTo-Json -Depth 4)
                continue
            }

            # DELETE /api/songs/{id}/cover
            if ($method -eq "DELETE" -and $path -match "^/api/songs/([a-zA-Z0-9_-]+)/cover$") {
                $id = $Matches[1]
                $songs = @(Read-Songs)
                $target = $songs | Where-Object { $_.id -eq $id } | Select-Object -First 1
                if ($null -eq $target) {
                    Send-TextResponse $stream 404 '{"error":"Písnička nenalezena"}'
                    continue
                }
                if ($target.coverFile) {
                    $oldName = Split-Path -Leaf $target.coverFile
                    $oldPath = Join-Path (Join-Path $DataDir $id) $oldName
                    if (Test-Path $oldPath) { Remove-Item $oldPath -Force -ErrorAction SilentlyContinue }
                    $target.coverFile = $null
                    Write-Songs $songs
                }
                Send-TextResponse $stream 200 ($target | ConvertTo-Json -Depth 4)
                continue
            }

            # PUT /api/songs/{id}
            if ($method -eq "PUT" -and $path -match "^/api/songs/([a-zA-Z0-9_-]+)$") {
                $id = $Matches[1]
                $bodyBytes = Read-BodyBytes $stream $req
                $bodyJson = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
                $body = $bodyJson | ConvertFrom-Json

                $songs = @(Read-Songs)
                $target = $songs | Where-Object { $_.id -eq $id } | Select-Object -First 1

                if ($null -eq $target) {
                    Send-TextResponse $stream 404 '{"error":"Písnička nenalezena"}'
                    continue
                }

                if ($null -ne $body.title) { $target.title = ([string]$body.title).Trim() }
                if ($null -ne $body.artist) { $target.artist = ([string]$body.artist).Trim() }
                if ($null -ne $body.album) { $target.album = ([string]$body.album).Trim() }
                if ($null -ne $body.lyrics) {
                    $target.lyrics = [string]$body.lyrics
                    $songDir = Join-Path $DataDir $id
                    if (-not (Test-Path $songDir)) { New-Item -ItemType Directory -Path $songDir -Force | Out-Null }
                    $lyricsFile = Join-Path $songDir "lyrics.txt"
                    if ([string]::IsNullOrWhiteSpace($target.lyrics)) {
                        if (Test-Path $lyricsFile) { Remove-Item $lyricsFile -Force -ErrorAction SilentlyContinue }
                    }
                    else {
                        [System.IO.File]::WriteAllText($lyricsFile, $target.lyrics, $Utf8NoBom)
                    }
                }

                Write-Songs $songs
                Send-TextResponse $stream 200 ($target | ConvertTo-Json -Depth 4)
                continue
            }

            # DELETE /api/songs/{id}
            if ($method -eq "DELETE" -and $path -match "^/api/songs/([a-zA-Z0-9_-]+)$") {
                $id = $Matches[1]
                $songs = @(Read-Songs)
                $remaining = @($songs | Where-Object { $_.id -ne $id })
                Write-Songs $remaining

                # Also remove deleted song from any playlists
                $playlists = @(Read-Playlists)
                $plChanged = $false
                foreach ($pl in $playlists) {
                    $curIds = @($pl.songIds | Where-Object { $_ -ne $id })
                    if ($curIds.Count -ne @($pl.songIds).Count) {
                        $pl.songIds = [string[]]$curIds
                        $plChanged = $true
                    }
                }
                if ($plChanged) { Write-Playlists $playlists }

                $songDir = Join-Path $DataDir $id
                if (Test-Path $songDir) {
                    Remove-Item -Path $songDir -Recurse -Force -ErrorAction SilentlyContinue
                }

                Send-TextResponse $stream 200 '{"deleted":true}'
                continue
            }

            # GET /api/playlists
            if ($method -eq "GET" -and $path -eq "/api/playlists") {
                $raw = [System.IO.File]::ReadAllText($PlaylistsJsonPath, [System.Text.Encoding]::UTF8)
                if ([string]::IsNullOrWhiteSpace($raw)) { $raw = "[]" }
                Send-TextResponse $stream 200 $raw
                continue
            }

            # POST /api/playlists
            if ($method -eq "POST" -and $path -eq "/api/playlists") {
                $bodyBytes = Read-BodyBytes $stream $req
                $bodyJson = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
                $body = $bodyJson | ConvertFrom-Json

                $name = if ($body.name) { ([string]$body.name).Trim() } else { "Nový playlist" }
                if ([string]::IsNullOrWhiteSpace($name)) { $name = "Nový playlist" }
                $songIds = [string[]]@()
                if ($null -ne $body.songIds) {
                    $songIds = [string[]]@($body.songIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                }

                $plId = "pl_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + "_" + ([Guid]::NewGuid().ToString("N").Substring(0, 5))
                $newPl = [PSCustomObject]@{
                    id        = $plId
                    name      = $name
                    songIds   = $songIds
                    createdAt = (Get-Date).ToString("o")
                }

                $playlists = @(Read-Playlists)
                $playlists = $playlists + @($newPl)
                Write-Playlists $playlists

                Send-TextResponse $stream 201 ($newPl | ConvertTo-Json -Depth 4)
                continue
            }

            # PUT /api/playlists/{id}
            if ($method -eq "PUT" -and $path -match "^/api/playlists/([a-zA-Z0-9_-]+)$") {
                $plId = $Matches[1]
                $bodyBytes = Read-BodyBytes $stream $req
                $bodyJson = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
                $body = $bodyJson | ConvertFrom-Json

                $playlists = @(Read-Playlists)
                $target = $playlists | Where-Object { $_.id -eq $plId } | Select-Object -First 1
                if ($null -eq $target) {
                    Send-TextResponse $stream 404 '{"error":"Playlist nenalezen"}'
                    continue
                }

                if ($null -ne $body.name) {
                    $trimmedName = ([string]$body.name).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($trimmedName)) {
                        $target.name = $trimmedName
                    }
                }
                if ($null -ne $body.songIds) {
                    $target.songIds = [string[]]@($body.songIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                }

                Write-Playlists $playlists
                Send-TextResponse $stream 200 ($target | ConvertTo-Json -Depth 4)
                continue
            }

            # DELETE /api/playlists/{id}
            if ($method -eq "DELETE" -and $path -match "^/api/playlists/([a-zA-Z0-9_-]+)$") {
                $plId = $Matches[1]
                $playlists = @(Read-Playlists)
                $remaining = @($playlists | Where-Object { $_.id -ne $plId })
                Write-Playlists $remaining
                Send-TextResponse $stream 200 '{"deleted":true}'
                continue
            }

            # POST /api/find-lyrics (LRCLIB synced/plain + lyrics.ovh fallback)
            if ($method -eq "POST" -and $path -eq "/api/find-lyrics") {
                $bodyBytes = Read-BodyBytes $stream $req
                $bodyJson = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
                $body = $bodyJson | ConvertFrom-Json

                $title = if ($body.title) { ([string]$body.title).Trim() } else { "" }
                $artist = if ($body.artist) { ([string]$body.artist).Trim() } else { "" }
                $album = if ($body.album) { ([string]$body.album).Trim() } else { "" }
                $duration = if ($body.duration) { [int][Math]::Round([double]$body.duration) } else { 0 }

                if ([string]::IsNullOrWhiteSpace($title)) {
                    Send-TextResponse $stream 400 '{"error":"Chybí název písničky"}'
                    continue
                }

                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $wc = New-Object System.Net.WebClient
                $wc.Encoding = [System.Text.Encoding]::UTF8
                $wc.Headers.Add("User-Agent", "SongDatabase/1.0")

                $lyrics = ""
                $synced = $false
                $source = ""

                # 1. Try LRCLIB exact get
                $lrcFound = $null
                if (-not [string]::IsNullOrWhiteSpace($artist)) {
                    $qUrl = "https://lrclib.net/api/get?track_name=" + [System.Uri]::EscapeDataString($title) +
                    "&artist_name=" + [System.Uri]::EscapeDataString($artist)
                    if (-not [string]::IsNullOrWhiteSpace($album)) {
                        $qUrl += "&album_name=" + [System.Uri]::EscapeDataString($album)
                    }
                    if ($duration -gt 0) {
                        $qUrl += "&duration=$duration"
                    }
                    try {
                        $lrcRaw = $wc.DownloadString($qUrl)
                        $lrcFound = $lrcRaw | ConvertFrom-Json
                    }
                    catch {}
                }

                # 2. Try LRCLIB search
                if ($null -eq $lrcFound -or (-not $lrcFound.syncedLyrics -and -not $lrcFound.plainLyrics)) {
                    $searchQ = if ($artist) { "$artist $title" } else { $title }
                    $sUrl = "https://lrclib.net/api/search?q=" + [System.Uri]::EscapeDataString($searchQ)
                    try {
                        $sRaw = $wc.DownloadString($sUrl)
                        $sArr = @($sRaw | ConvertFrom-Json)
                        if ($sArr.Count -gt 0) {
                            $best = $sArr | Where-Object { $_.syncedLyrics } | Select-Object -First 1
                            if (-not $best) { $best = $sArr | Select-Object -First 1 }
                            $lrcFound = $best
                        }
                    }
                    catch {}
                }

                if ($lrcFound) {
                    if ($lrcFound.syncedLyrics) {
                        $lyrics = [string]$lrcFound.syncedLyrics
                        $synced = $true
                        $source = "LRCLIB"
                    }
                    elseif ($lrcFound.plainLyrics) {
                        $lyrics = [string]$lrcFound.plainLyrics
                        $source = "LRCLIB"
                    }
                }

                # 3. Fallback to lyrics.ovh if still empty and artist is known
                if ([string]::IsNullOrWhiteSpace($lyrics) -and -not [string]::IsNullOrWhiteSpace($artist)) {
                    try {
                        $ovhUrl = "https://api.lyrics.ovh/v1/" + [System.Uri]::EscapeDataString($artist) + "/" + [System.Uri]::EscapeDataString($title)
                        $ovhRaw = $wc.DownloadString($ovhUrl)
                        $ovhObj = $ovhRaw | ConvertFrom-Json
                        if ($ovhObj -and $ovhObj.lyrics) {
                            $lyrics = ([string]$ovhObj.lyrics).Trim()
                            $source = "lyrics.ovh"
                        }
                    }
                    catch {}
                }

                if ([string]::IsNullOrWhiteSpace($lyrics)) {
                    Send-TextResponse $stream 404 '{"error":"Lyrics nebyly nalezeny v LRCLIB ani lyrics.ovh."}'
                    continue
                }

                $respObj = [PSCustomObject]@{
                    lyrics = $lyrics
                    synced = $synced
                    source = $source
                }
                Send-TextResponse $stream 200 ($respObj | ConvertTo-Json -Depth 4)
                continue
            }

            # POST /api/import-url (YouTube / YouTube Music via local yt-dlp + ffmpeg + LRCLIB lyrics)
            if ($method -eq "POST" -and $path -eq "/api/import-url") {
                $client.ReceiveTimeout = 180000
                $client.SendTimeout = 180000
                $bodyBytes = Read-BodyBytes $stream $req
                $bodyJson = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
                $body = $bodyJson | ConvertFrom-Json
                $url = if ($body.url) { ([string]$body.url).Trim() } else { "" }
                $convertToMp3 = if ($null -ne $body.convertToMp3) { [bool]$body.convertToMp3 } else { $false }
                $convertCoverToJpg = if ($null -ne $body.convertCoverToJpg) { [bool]$body.convertCoverToJpg } else { $false }

                if ($url -notmatch "^https?://") {
                    Send-TextResponse $stream 400 '{"error":"Zadej platný odkaz (http:// nebo https://)"}'
                    continue
                }

                # Locate yt-dlp & ffmpeg already installed on system
                $ytdlpCmd = Get-Command yt-dlp -ErrorAction SilentlyContinue
                $ytdlpExe = if ($ytdlpCmd) { $ytdlpCmd.Source } elseif (Test-Path "C:\ytdlp\yt-dlp.exe") { "C:\ytdlp\yt-dlp.exe" } else { $null }
                if (-not $ytdlpExe) {
                    Send-TextResponse $stream 500 '{"error":"Nebyl nalezen yt-dlp.exe na tomto počítači."}'
                    continue
                }

                $ffmpegCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
                $ffmpegDir = if ($ffmpegCmd) { Split-Path -Parent $ffmpegCmd.Source } elseif (Test-Path "C:\ytdlp\ffmpeg.exe") { "C:\ytdlp" } else { $null }

                $token = "imp_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + "_" + ([Guid]::NewGuid().ToString("N").Substring(0, 6))
                $stageDir = Join-Path $StagingRoot $token
                New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

                $outTemplate = Join-Path $stageDir "media.%(ext)s"
                $ytArgs = @(
                    "--no-playlist",
                    "--no-warnings",
                    "--no-mtime",
                    "--no-part",
                    "--concurrent-fragments", "4",
                    "--socket-timeout", "15",
                    "--print-json"
                )
                if ($convertToMp3) {
                    $ytArgs += @("-x", "--audio-format", "mp3", "--audio-quality", "0")
                } else {
                    $ytArgs += @("-f", "`"bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio`"")
                }
                $ytArgs += "--write-thumbnail"
                if ($convertCoverToJpg) {
                    $ytArgs += @("--convert-thumbnails", "jpg")
                }
                $ytArgs += @("-o", "`"$outTemplate`"")
                if ($ffmpegDir) {
                    $ytArgs += @("--ffmpeg-location", "`"$ffmpegDir`"")
                }
                $ytArgs += "`"$url`""

                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $ytdlpExe
                $psi.Arguments = ($ytArgs -join " ")
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
                $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

                $proc = New-Object System.Diagnostics.Process
                $proc.StartInfo = $psi
                [void]$proc.Start()
                $stdOut = $proc.StandardOutput.ReadToEnd()
                $stdErr = $proc.StandardError.ReadToEnd()
                $proc.WaitForExit()

                $meta = $null
                foreach ($line in ($stdOut -split "`r?`n")) {
                    $tr = $line.Trim()
                    if ($tr.StartsWith("{") -and $tr.EndsWith("}")) {
                        try { $meta = $tr | ConvertFrom-Json; break } catch {}
                    }
                }

                # Rename downloaded audio & cover into clean audio.* / cover.*
                $audioObj = Get-ChildItem $stageDir -File | Where-Object { $_.Extension -in @(".mp3", ".m4a", ".opus", ".webm", ".ogg", ".wav", ".flac") } | Select-Object -First 1
                $hasAudio = $false
                $audioName = $null
                if ($audioObj) {
                    $audioName = "audio" + $audioObj.Extension.ToLowerInvariant()
                    Move-Item -Path $audioObj.FullName -Destination (Join-Path $stageDir $audioName) -Force
                    $hasAudio = $true
                }

                $coverObj = Get-ChildItem $stageDir -File | Where-Object { $_.Extension -in @(".jpg", ".jpeg", ".png", ".webp") } | Select-Object -First 1
                $hasCover = $false
                $coverPreviewUrl = $null
                if ($coverObj) {
                    $coverName = "cover" + $coverObj.Extension.ToLowerInvariant()
                    Move-Item -Path $coverObj.FullName -Destination (Join-Path $stageDir $coverName) -Force
                    $hasCover = $true
                    $coverPreviewUrl = "/api/staging/$token/$coverName"
                }

                if (-not $hasAudio -and $null -eq $meta) {
                    Remove-Item -Path $stageDir -Recurse -Force -ErrorAction SilentlyContinue
                    $msg = if ($stdErr) { ($stdErr -split "`r?`n" | Select-Object -Last 1) } else { "Nepodařilo se stáhnout z odkazu." }
                    $safeErr = @{ error = $msg } | ConvertTo-Json -Compress
                    Send-TextResponse $stream 500 $safeErr
                    continue
                }

                # Extract clean title, artist, album
                $title = ""
                $artist = ""
                $album = ""
                $duration = 0

                if ($meta) {
                    if ($meta.track) { $title = [string]$meta.track }
                    elseif ($meta.title) { $title = [string]$meta.title }

                    if ($meta.artist) { $artist = [string]$meta.artist }
                    elseif ($meta.artists -and $meta.artists.Count -gt 0) { $artist = [string]$meta.artists[0] }
                    elseif ($meta.creator) { $artist = [string]$meta.creator }
                    elseif ($meta.uploader) { $artist = ([string]$meta.uploader) -replace "\s*-\s*Topic$", "" }
                    elseif ($meta.channel) { $artist = ([string]$meta.channel) -replace "\s*-\s*Topic$", "" }

                    if ($meta.album) { $album = [string]$meta.album }
                    if ($meta.duration) { $duration = [int][Math]::Round([double]$meta.duration) }

                    # Clean "Artist - Song (Official Video)" when track tag wasn't provided
                    if (-not $meta.track -and $title -match "^(.+?)\s+-\s+(.+)$") {
                        $candArtist = $Matches[1].Trim()
                        $candTitle = $Matches[2].Trim()
                        if ([string]::IsNullOrWhiteSpace($artist) -or $artist -eq $meta.uploader) {
                            $artist = $candArtist
                        }
                        $title = $candTitle
                    }
                    $title = ($title -replace "\s*[\(\[](Official\s*(Music\s*)?Video|Official\s*Audio|Lyric\s*Video|Lyrics|HD|4K)[\)\]]", "").Trim()
                }

                # Try fetching synced lyrics (LRC) from LRCLIB
                $lyrics = ""
                $lyricsSynced = $false
                if (-not [string]::IsNullOrWhiteSpace($title)) {
                    try {
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                        $wc = New-Object System.Net.WebClient
                        $wc.Encoding = [System.Text.Encoding]::UTF8
                        $wc.Headers.Add("User-Agent", "SongDatabase/1.0")

                        $lrcFound = $null
                        if (-not [string]::IsNullOrWhiteSpace($artist)) {
                            $qUrl = "https://lrclib.net/api/get?track_name=" + [System.Uri]::EscapeDataString($title) +
                            "&artist_name=" + [System.Uri]::EscapeDataString($artist)
                            if (-not [string]::IsNullOrWhiteSpace($album)) {
                                $qUrl += "&album_name=" + [System.Uri]::EscapeDataString($album)
                            }
                            if ($duration -gt 0) {
                                $qUrl += "&duration=$duration"
                            }
                            try {
                                $lrcRaw = $wc.DownloadString($qUrl)
                                $lrcFound = $lrcRaw | ConvertFrom-Json
                            }
                            catch {}
                        }

                        if ($null -eq $lrcFound -or (-not $lrcFound.syncedLyrics -and -not $lrcFound.plainLyrics)) {
                            $searchQ = if ($artist) { "$artist $title" } else { $title }
                            $sUrl = "https://lrclib.net/api/search?q=" + [System.Uri]::EscapeDataString($searchQ)
                            try {
                                $sRaw = $wc.DownloadString($sUrl)
                                $sArr = @($sRaw | ConvertFrom-Json)
                                if ($sArr.Count -gt 0) {
                                    $best = $sArr | Where-Object { $_.syncedLyrics } | Select-Object -First 1
                                    if (-not $best) { $best = $sArr | Select-Object -First 1 }
                                    $lrcFound = $best
                                }
                            }
                            catch {}
                        }

                        if ($lrcFound) {
                            if ($lrcFound.syncedLyrics) {
                                $lyrics = [string]$lrcFound.syncedLyrics
                                $lyricsSynced = $true
                            }
                            elseif ($lrcFound.plainLyrics) {
                                $lyrics = [string]$lrcFound.plainLyrics
                            }
                            if ([string]::IsNullOrWhiteSpace($album) -and $lrcFound.albumName) {
                                $album = [string]$lrcFound.albumName
                            }
                        }
                    }
                    catch {}
                }

                $respObj = [PSCustomObject]@{
                    token           = $token
                    title           = $title
                    artist          = $artist
                    album           = $album
                    lyrics          = $lyrics
                    lyricsSynced    = $lyricsSynced
                    hasAudio        = $hasAudio
                    audioName       = $audioName
                    hasCover        = $hasCover
                    coverPreviewUrl = $coverPreviewUrl
                }
                Send-TextResponse $stream 200 ($respObj | ConvertTo-Json -Depth 4)
                continue
            }

            # GET /api/staging/{token}/{filename}
            if ($method -eq "GET" -and $path -match "^/api/staging/([a-zA-Z0-9_-]+)/([a-zA-Z0-9._-]+)$") {
                $token = $Matches[1]
                $fileName = $Matches[2]
                $filePath = Join-Path (Join-Path $StagingRoot $token) $fileName
                Send-FileResponse $stream $req $filePath
                continue
            }

            # DELETE /api/staging/{token}
            if ($method -eq "DELETE" -and $path -match "^/api/staging/([a-zA-Z0-9_-]+)$") {
                $token = $Matches[1]
                $stageDir = Join-Path $StagingRoot $token
                if (Test-Path $stageDir) {
                    Remove-Item -Path $stageDir -Recurse -Force -ErrorAction SilentlyContinue
                }
                Send-TextResponse $stream 200 '{"cleaned":true}'
                continue
            }

            # GET /api/settings
            if ($method -eq "GET" -and $path -eq "/api/settings") {
                $raw = "{}"
                if (Test-Path $SettingsJsonPath) {
                    $raw = [System.IO.File]::ReadAllText($SettingsJsonPath, [System.Text.Encoding]::UTF8)
                    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = "{}" }
                }
                Send-TextResponse $stream 200 $raw
                continue
            }

            # PUT /api/settings
            if ($method -eq "PUT" -and $path -eq "/api/settings") {
                $bodyBytes = Read-BodyBytes $stream $req
                $bodyJson = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
                if ([string]::IsNullOrWhiteSpace($bodyJson)) { $bodyJson = "{}" }
                # Validate JSON before saving
                $null = $bodyJson | ConvertFrom-Json
                [System.IO.File]::WriteAllText($SettingsJsonPath, $bodyJson, $Utf8NoBom)
                Send-TextResponse $stream 200 $bodyJson
                continue
            }

            # POST /api/translate (line-by-line translation preserving exact sync order)
            if ($method -eq "POST" -and $path -eq "/api/translate") {
                $bodyBytes = Read-BodyBytes $stream $req
                $bodyJson = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
                $body = $bodyJson | ConvertFrom-Json

                $targetLang = if ($body.target) { ([string]$body.target).Trim() } else { "cs" }
                $sourceLang = if ($body.source) { ([string]$body.source).Trim() } else { "auto" }
                if ($targetLang -notmatch "^[a-zA-Z]{2,5}(-[a-zA-Z]{2,4})?$") { $targetLang = "cs" }
                if ($sourceLang -notmatch "^(auto|[a-zA-Z]{2,5}(-[a-zA-Z]{2,4})?)$") { $sourceLang = "auto" }

                $inputLines = @($body.lines | ForEach-Object { [string]$_ })
                if ($inputLines.Count -eq 0) {
                    Send-TextResponse $stream 200 '{"lines":[]}'
                    continue
                }

                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

                $translateChunk = {
                    param([string]$text, [string]$sl, [string]$tl)
                    $wc = New-Object System.Net.WebClient
                    $wc.Encoding = [System.Text.Encoding]::UTF8
                    $wc.Headers.Add("Content-Type", "application/x-www-form-urlencoded; charset=utf-8")
                    $wc.Headers.Add("User-Agent", "Mozilla/5.0")
                    $apiUrl = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=$sl&tl=$tl&dt=t"
                    $postData = "q=" + [System.Uri]::EscapeDataString($text)
                    $respRaw = $wc.UploadString($apiUrl, "POST", $postData)
                    $parsed = $respRaw | ConvertFrom-Json
                    $sb = New-Object System.Text.StringBuilder
                    foreach ($seg in $parsed[0]) {
                        if ($null -ne $seg -and $seg.Count -gt 0 -and $null -ne $seg[0]) {
                            [void]$sb.Append([string]$seg[0])
                        }
                    }
                    return $sb.ToString()
                }

                $outLines = New-Object System.Collections.ArrayList
                $batchSize = 20
                for ($i = 0; $i -lt $inputLines.Count; $i += $batchSize) {
                    $endIdx = [Math]::Min($i + $batchSize - 1, $inputLines.Count - 1)
                    $chunk = @($inputLines[$i..$endIdx])
                    $joined = ($chunk -join "`n")
                    $translatedJoined = & $translateChunk $joined $sourceLang $targetLang
                    $splitRes = @($translatedJoined -split "`r?`n")

                    if ($splitRes.Count -eq $chunk.Count) {
                        foreach ($l in $splitRes) { [void]$outLines.Add($l) }
                    }
                    else {
                        # Fallback per-line if translator merged/split newlines
                        foreach ($singleLine in $chunk) {
                            if ([string]::IsNullOrWhiteSpace($singleLine)) {
                                [void]$outLines.Add("")
                            }
                            else {
                                $tSingle = & $translateChunk $singleLine $sourceLang $targetLang
                                [void]$outLines.Add(($tSingle -replace "`r?`n", " ").Trim())
                            }
                        }
                    }
                }

                $resultObj = [PSCustomObject]@{
                    target = $targetLang
                    lines  = [string[]]@($outLines)
                }
                Send-TextResponse $stream 200 ($resultObj | ConvertTo-Json -Depth 4)
                continue
            }

            # GET /data/{id}/{filename}
            if ($method -eq "GET" -and $path -match "^/data/([a-zA-Z0-9_-]+)/([a-zA-Z0-9._-]+)$") {
                $id = $Matches[1]
                $fileName = $Matches[2]
                $filePath = Join-Path (Join-Path $DataDir $id) $fileName
                Send-FileResponse $stream $req $filePath
                continue
            }

            Send-TextResponse $stream 404 '{"error":"Nenalezeno"}'
        }
        catch {
            $errMsg = $_.Exception.Message -replace '"', '\"'
            try {
                Send-TextResponse $stream 500 "{`"error`":`"$errMsg`"}"
            }
            catch {}
        }
        finally {
            try { $client.Close() } catch {}
        }
    }
}
finally {
    $listener.Stop()
}
