param (
    [Parameter(Mandatory=$true)]
    [string]$Url,
    [int]$Layers = 1
)

Write-Host "Ensuring 'files' directory exists..."
if (-not (Test-Path -Path "files")) {
    New-Item -ItemType Directory -Force -Path "files" | Out-Null
}

$ConfigFile = "files/.sync_config"
Write-Host "Checking for config file at $ConfigFile..."
if (-not (Test-Path -Path $ConfigFile)) {
    Write-Host "Config file not found. Creating $ConfigFile..."
    New-Item -ItemType File -Force -Path $ConfigFile | Out-Null
}

function Get-StoredLastModified {
    param ([string]$TargetUrl)
    if (Test-Path -Path $ConfigFile) {
        $lines = Get-Content -Path $ConfigFile
        if ($null -ne $lines) {
            if ($lines -is [string]) { $lines = @($lines) }
            foreach ($line in $lines) {
                $parts = $line -split "`t"
                if ($parts.Count -eq 2 -and $parts[0] -eq $TargetUrl) {
                    return $parts[1]
                }
            }
        }
    }
    return $null
}

function Update-Config {
    param ([string]$TargetUrl, [string]$Lm)
    if (Test-Path -Path $ConfigFile) {
        $lines = Get-Content -Path $ConfigFile
        $newLines = @()
        if ($null -ne $lines) {
            if ($lines -is [string]) { $lines = @($lines) }
            foreach ($line in $lines) {
                $parts = $line -split "`t"
                if ($parts.Count -ge 2 -and $parts[0] -ne $TargetUrl) {
                    $newLines += $line
                }
            }
        }
        $newLines += "$TargetUrl`t$Lm"
        $newLines | Set-Content -Path $ConfigFile
    } else {
        Set-Content -Path $ConfigFile -Value "$TargetUrl`t$Lm"
    }
}

Write-Host "Initializing tracking files (queue_0.txt, visited.txt, downloaded.txt)..."
New-Item -ItemType File -Force -Path "visited.txt" | Out-Null
New-Item -ItemType File -Force -Path "downloaded.txt" | Out-Null

Write-Host "Adding initial URL to queue_0.txt..."
Set-Content -Path "queue_0.txt" -Value $Url

function Get-AbsoluteUrl {
    param ([string]$Base, [string]$Link)

    # Remove fragment
    $index = $Link.IndexOf("#")
    if ($index -ge 0) {
        $Link = $Link.Substring(0, $index)
    }

    if ($Link -match "^(http://|https://|ftp://)") {
        return $Link
    } elseif ($Link.StartsWith("/")) {
        if ($Base -match "^(https?://[^/]+)") {
            return $matches[1] + $Link
        }
        return $Base + $Link
    } else {
        if ($Base.EndsWith("/")) {
            return $Base + $Link
        } else {
            if ($Base -match "^(https?://[^/]+)$") {
                return $Base + "/" + $Link
            } else {
                $lastSlash = $Base.LastIndexOf("/")
                if ($lastSlash -ge 0) {
                    $baseDir = $Base.Substring(0, $lastSlash)
                    return $baseDir + "/" + $Link
                }
                return $Base + "/" + $Link
            }
        }
    }
}

function Is-TargetFileStrict {
    param ([string]$TargetUrl)
    $cleanUrl = $TargetUrl
    $index = $cleanUrl.IndexOf("?")
    if ($index -ge 0) {
        $cleanUrl = $cleanUrl.Substring(0, $index)
    }

    if ($cleanUrl.EndsWith("/")) {
        return $false
    }

    $extIndex = $cleanUrl.LastIndexOf(".")
    if ($extIndex -lt 0) {
        return $false
    }

    $ext = $cleanUrl.Substring($extIndex + 1).ToLower()
    if ($ext -eq $cleanUrl.ToLower()) {
        return $false
    }

    $exclude = @("htm", "html", "php", "asp", "aspx", "jsp", "css", "xml", "json", "com", "org", "net", "in", "edu", "uk", "us", "info", "io", "gov", "mil")
    $include = @("pdf", "c", "js", "cpp", "py", "txt", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "zip", "tar", "gz", "rar", "bz2", "7z", "jpg", "jpeg", "png", "gif", "svg", "mp3", "mp4", "avi", "mkv", "webm", "webp", "h", "hpp")

    if ($exclude -contains $ext) {
        return $false
    }
    if ($include -contains $ext) {
        return $true
    }
    return $false
}

$currentLayer = 0

while ($currentLayer -le $Layers) {
    Write-Host "=== Processing Layer $currentLayer ==="

    $nextLayer = $currentLayer + 1
    New-Item -ItemType File -Force -Path "queue_$nextLayer.txt" | Out-Null

    $queueFile = "queue_$currentLayer.txt"
    if (Test-Path -Path $queueFile) {
        $urls = Get-Content -Path $queueFile
        if ($null -ne $urls) {
            if ($urls -is [string]) { $urls = @($urls) }
            foreach ($currentUrl in $urls) {
                if ([string]::IsNullOrWhiteSpace($currentUrl)) { continue }

                Write-Host "Checking if URL $currentUrl was already visited..."
                $visited = $false
                if (Test-Path -Path "visited.txt") {
                    $visitedLines = Get-Content -Path "visited.txt"
                    if ($null -ne $visitedLines) {
                        if ($visitedLines -is [string]) { $visitedLines = @($visitedLines) }
                        foreach ($v in $visitedLines) {
                            if ($v -eq $currentUrl) {
                                $visited = $true
                                break
                            }
                        }
                    }
                }

                if ($visited) {
                    Write-Host "URL $currentUrl already visited. Skipping..."
                    continue
                }

                Write-Host "Marking URL $currentUrl as visited..."
                Add-Content -Path "visited.txt" -Value $currentUrl

                if (Is-TargetFileStrict -TargetUrl $currentUrl) {
                    Write-Host "[Layer $currentLayer] File found: $currentUrl"

                    $cleanUrl = $currentUrl
                    $index = $cleanUrl.IndexOf("?")
                    if ($index -ge 0) {
                        $cleanUrl = $cleanUrl.Substring(0, $index)
                    }

                    $filename = $cleanUrl
                    $lastSlash = $cleanUrl.LastIndexOf("/")
                    if ($lastSlash -ge 0) {
                        $filename = $cleanUrl.Substring($lastSlash + 1)
                    }

                    if ($filename -like "*/*" -or $filename -like "*\*" -or $filename -eq ".." -or $filename -eq ".") {
                        Write-Host "Invalid filename $filename"
                        continue
                    }

                    if ([string]::IsNullOrWhiteSpace($filename)) { continue }

                    $downloaded = $false
                    if (Test-Path -Path "downloaded.txt") {
                        $downloadedLines = Get-Content -Path "downloaded.txt"
                        if ($null -ne $downloadedLines) {
                            if ($downloadedLines -is [string]) { $downloadedLines = @($downloadedLines) }
                            foreach ($d in $downloadedLines) {
                                if ($d -eq $currentUrl) {
                                    $downloaded = $true
                                    break
                                }
                            }
                        }
                    }

                    Write-Host "Checking if file $currentUrl was already downloaded..."
                    if (-not $downloaded) {
                        Write-Host "Fetching headers for $currentUrl..."
                        $lastModified = ""
                        try {
                            $response = Invoke-WebRequest -Uri $currentUrl -Method Head -UseBasicParsing -ErrorAction Stop
                            if ($response.Headers.ContainsKey("Last-Modified")) {
                                $lastModified = $response.Headers["Last-Modified"]
                                if ($lastModified -is [array]) {
                                    $lastModified = $lastModified[-1]
                                }
                            }
                        } catch {
                            # Head might fail, proceed anyway
                        }

                        $shouldDownload = $true
                        if (-not [string]::IsNullOrEmpty($lastModified)) {
                            $storedLm = Get-StoredLastModified -TargetUrl $currentUrl
                            if ($lastModified -eq $storedLm -and (Test-Path -Path "files/$filename")) {
                                Write-Host "Skipping (already downloaded and not modified): $currentUrl"
                                $shouldDownload = $false
                            }
                        }

                        if ($shouldDownload) {
                            Write-Host "Downloading: $currentUrl"
                            try {
                                Invoke-WebRequest -Uri $currentUrl -OutFile "files/$filename" -UseBasicParsing -ErrorAction Stop
                                Add-Content -Path "downloaded.txt" -Value $currentUrl
                                if (-not [string]::IsNullOrEmpty($lastModified)) {
                                    Update-Config -TargetUrl $currentUrl -Lm $lastModified
                                }
                            } catch {
                                # Failed to download
                            }
                        } else {
                            Add-Content -Path "downloaded.txt" -Value $currentUrl
                        }
                    }
                    continue
                }

                if ($currentLayer -lt $Layers) {
                    Write-Host "[Layer $currentLayer] Crawling: $currentUrl"

                    Write-Host "Fetching content for $currentUrl..."
                    $content = ""
                    try {
                        $response = Invoke-WebRequest -Uri $currentUrl -UseBasicParsing -ErrorAction Stop
                        $content = $response.Content
                    } catch {
                        # Failed to fetch
                    }

                    Write-Host "Extracting links from $currentUrl..."
                    if (-not [string]::IsNullOrEmpty($content)) {
                        $matches1 = [regex]::Matches($content, '(?i)href="([^"]*)"')
                        foreach ($m in $matches1) {
                            $link = $m.Groups[1].Value
                            if ($link -match "^(mailto:|tel:|javascript:|data:|#)") { continue }
                            $absUrl = Get-AbsoluteUrl -Base $currentUrl -Link $link
                            Add-Content -Path "queue_$nextLayer.txt" -Value $absUrl
                        }

                        $matches2 = [regex]::Matches($content, "(?i)href='([^']*)'")
                        foreach ($m in $matches2) {
                            $link = $m.Groups[1].Value
                            if ($link -match "^(mailto:|tel:|javascript:|data:|#)") { continue }
                            $absUrl = Get-AbsoluteUrl -Base $currentUrl -Link $link
                            Add-Content -Path "queue_$nextLayer.txt" -Value $absUrl
                        }
                    }
                }
            }
        }
    }

    $nextQueueFile = "queue_$nextLayer.txt"
    if (Test-Path -Path $nextQueueFile) {
        Write-Host "Deduplicating queue for next layer..."
        $content = Get-Content -Path $nextQueueFile
        if ($null -ne $content) {
            $uniqueUrls = $content | Sort-Object -Unique
            $uniqueUrls | Set-Content -Path $nextQueueFile
        }
    }

    $currentLayer = $nextLayer
}

Write-Host "Done!"
