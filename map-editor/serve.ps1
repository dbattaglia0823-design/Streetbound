# Local-only static HTTP server, built into Windows PowerShell.
param([int]$Port = 8765)
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd([char[]]@('\','/'))
$prefix = $root + [System.IO.Path]::DirectorySeparatorChar
$mime = @{
  '.html'='text/html; charset=utf-8'
  '.js'='text/javascript; charset=utf-8'
  '.css'='text/css; charset=utf-8'
  '.json'='application/json; charset=utf-8'
  '.gd'='text/plain; charset=utf-8'
  '.svg'='image/svg+xml'
  '.png'='image/png'
  '.webp'='image/webp'
  '.md'='text/plain; charset=utf-8'
}
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
try {
  $listener.Start()
  $url = "http://127.0.0.1:$Port/"
  Write-Host "Streetbound Map Builder: $url"
  Write-Host 'Serving local files only. Press Ctrl+C to stop.'
  Start-Process $url
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $client.ReceiveTimeout = 10000
      $client.SendTimeout = 10000
      $stream = $client.GetStream()
      $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
      $request = $reader.ReadLine()
      while ($null -ne $request) {
        $h = $reader.ReadLine()
        if ([string]::IsNullOrEmpty($h)) { break }
      }
      $status = '200 OK'
      $file = $null
      if ($request -notmatch '^GET\s+([^\s]+)\s+HTTP/') {
        $status = '405 Method Not Allowed'
      } else {
        $relative = $Matches[1].Split('?')[0].Split('#')[0]
        $relative = [System.Uri]::UnescapeDataString($relative).TrimStart('/')
        if ([string]::IsNullOrWhiteSpace($relative)) { $relative = 'index.html' }
        $relative = $relative.Replace('\\', '/')
        try {
          if ($relative -ceq 'worlds/morrow-coast.world.json') {
            # Explicit read-only reference to the playable world. Do not
            # expose the rest of the repository (especially .git metadata).
            $file = [System.IO.Path]::GetFullPath((Join-Path $root '..\worlds\morrow-coast.world.json'))
          } else {
            $file = [System.IO.Path]::GetFullPath((Join-Path $root $relative))
            if (-not $file.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
              $status = '403 Forbidden'
            }
          }
          if ($status -eq '200 OK' -and -not [System.IO.File]::Exists($file)) {
            $status = '404 Not Found'
          }
        } catch { $status = '400 Bad Request' }
      }
      if ($status -eq '200 OK') {
        $body = [System.IO.File]::ReadAllBytes($file)
        $extension = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
        $type = if ($mime.ContainsKey($extension)) { $mime[$extension] } else { 'application/octet-stream' }
      } else {
        $body = [System.Text.Encoding]::UTF8.GetBytes($status)
        $type = 'text/plain; charset=utf-8'
      }
      $crlf = [System.Environment]::NewLine
      $response = "HTTP/1.1 $status" + $crlf +
        "Content-Type: $type" + $crlf +
        "Content-Length: $($body.Length)" + $crlf +
        "Connection: close" + $crlf +
        "Cache-Control: no-store" + $crlf + $crlf
      $header = [System.Text.Encoding]::ASCII.GetBytes($response)
      $stream.Write($header, 0, $header.Length)
      $stream.Write($body, 0, $body.Length)
      $stream.Flush()
    } catch {
      Write-Warning "Request failed: $($_.Exception.Message)"
    } finally {
      $client.Close()
    }
  }
} finally {
  $listener.Stop()
}
