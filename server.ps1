# TaskBoard 用の小さな静的ファイルサーバー（Node/Python 不要）
# 使い方: powershell -ExecutionPolicy Bypass -File server.ps1 [-Port 5176]
param([int]$Port = 5176)

$root = [IO.Path]::GetFullPath((Split-Path -Parent $MyInvocation.MyCommand.Path))
$types = @{
  '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'
  '.css' = 'text/css; charset=utf-8'; '.svg' = 'image/svg+xml'; '.png' = 'image/png'
  '.webmanifest' = 'application/manifest+json'; '.json' = 'application/json'; '.ico' = 'image/x-icon'
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
$listener.Start()

Write-Host ""
Write-Host "  TaskBoard server is running."
Write-Host "  PC     : http://localhost:$Port"
try {
  Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    ForEach-Object { Write-Host "  iPhone : http://$($_.IPAddress):$Port   (same Wi-Fi)" }
} catch {}
Write-Host "  Stop   : Ctrl+C"
Write-Host ""

while ($true) {
  $client = $listener.AcceptTcpClient()
  try {
    $client.ReceiveTimeout = 2000
    $stream = $client.GetStream()
    $reader = [System.IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 8192, $true)
    $line = $reader.ReadLine()
    while ($true) { $h = $reader.ReadLine(); if ($null -eq $h -or $h -eq '') { break } }

    $path = '/'
    if ($line -match '^(GET|HEAD) (\S+)') { $path = [Uri]::UnescapeDataString(($matches[2] -split '\?')[0]) }
    if ($path -eq '/') { $path = '/index.html' }
    $file = [IO.Path]::GetFullPath((Join-Path $root $path.TrimStart('/')))

    if ($file.StartsWith($root) -and (Test-Path -LiteralPath $file -PathType Leaf) -and ($file -notlike '*.ps1')) {
      $body = [IO.File]::ReadAllBytes($file); $status = '200 OK'
      $ct = $types[[IO.Path]::GetExtension($file).ToLower()]
      if (-not $ct) { $ct = 'application/octet-stream' }
    } else {
      $body = [Text.Encoding]::UTF8.GetBytes('Not Found'); $status = '404 Not Found'; $ct = 'text/plain'
    }

    $head = "HTTP/1.1 $status`r`nContent-Type: $ct`r`nContent-Length: $($body.Length)`r`nCache-Control: no-cache`r`nConnection: close`r`n`r`n"
    $hb = [Text.Encoding]::ASCII.GetBytes($head)
    $stream.Write($hb, 0, $hb.Length)
    if ($line -notmatch '^HEAD') { $stream.Write($body, 0, $body.Length) }
    $stream.Flush()
  } catch {
  } finally {
    $client.Close()
  }
}
