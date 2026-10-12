<#
.SYNOPSIS
    MoveInSync Play Store Rating Sentinel & Monitoring Tool
    Designed for the Forward Deployed Engineering (FDE) workflow.
    Answers the recurring question: "How are our Play Store ratings?" in real-time.
#>

param(
    [string]$AppId = "com.moveinsync.ets",
    [int]$FetchCount = 100,
    [switch]$Detailed,
    [string]$OutputFile = "moveinsync_latest_health.json"
)

Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Text.RegularExpressions;

public class JsonHelper {
    public static string Unescape(string input) {
        return Regex.Unescape(input);
    }
}
"@

function Get-PlayStoreReviews {
    param([string]$AppId, [int]$Count, [int]$Sort = 2)

    $payload = "f.req=%5B%5B%5B%22oCPfdb%22%2C%22%5Bnull%2C%5B2%2C$Sort%2C%5B$Count%5D%2Cnull%2C%5Bnull%2Cnull%2Cnull%2Cnull%2Cnull%2Cnull%2Cnull%2Cnull%2Cnull%5D%5D%2C%5B%5C%22$AppId%5C%22%2C7%5D%5D%22%2Cnull%2C%22generic%22%5D%5D%5D%0A"
    $url = "https://play.google.com/_/PlayStoreUi/data/batchexecute?hl=en&gl=in"

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Method = "POST"
    $req.ContentType = "application/x-www-form-urlencoded;charset=utf-8"
    $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    $req.ContentLength = $bytes.Length
    
    $stream = $req.GetRequestStream()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Close()
    
    $resp = $req.GetResponse()
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $content = $reader.ReadToEnd()
    $reader.Close()

    $startMarker = '"wrb.fr","oCPfdb","'
    $startIdx = $content.IndexOf($startMarker)
    if ($startIdx -lt 0) { return @() }
    $startIdx += $startMarker.Length

    $endMarker = '",null,null,null,"generic"'
    $endIdx = $content.IndexOf($endMarker, $startIdx)
    if ($endIdx -lt 0) {
        $endMarker = '",null,"generic"'
        $endIdx = $content.IndexOf($endMarker, $startIdx)
    }
    if ($endIdx -lt 0) { return @() }

    $escaped = $content.Substring($startIdx, $endIdx - $startIdx)
    $unescaped = [JsonHelper]::Unescape($escaped)
    $json = $unescaped | ConvertFrom-Json
    
    $items = $json[0]
    $list = @()
    foreach ($item in $items) {
        $epoch = $item[5][0]
        $d = [DateTimeOffset]::FromUnixTimeSeconds($epoch).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")
        $reply = $null
        if ($item[7] -and $item[7].Count -ge 2 -and $item[7][1]) {
            $reply = $item[7][1]
        }

        $list += [PSCustomObject]@{
            ReviewId = $item[0]
            Date = $d
            UserName = $item[1][0]
            Rating = $item[2]
            Content = $item[4]
            AppVersion = $item[10]
            ThumbsUp = $item[6]
            DeveloperReply = $reply
        }
    }
    return $list
}

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " MOVEINSYNC PLAY STORE SENTINEL (FDE AUTOMATION TOOL)           " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Polling latest $FetchCount reviews for '$AppId'..." -ForegroundColor Gray

$reviews = Get-PlayStoreReviews -AppId $AppId -Count $FetchCount

if ($reviews.Count -eq 0) {
    Write-Host "Failed to retrieve reviews. Check network connectivity." -ForegroundColor Red
    exit 1
}

$ratings = $reviews | Measure-Object -Property Rating -Average
$avgRating = [math]::Round($ratings.Average, 2)
$star1 = ($reviews | Where-Object { $_.Rating -eq 1 }).Count
$star2 = ($reviews | Where-Object { $_.Rating -eq 2 }).Count
$star3 = ($reviews | Where-Object { $_.Rating -eq 3 }).Count
$star4 = ($reviews | Where-Object { $_.Rating -eq 4 }).Count
$star5 = ($reviews | Where-Object { $_.Rating -eq 5 }).Count

$negativeCount = $star1 + $star2
$negativePct = [math]::Round(($negativeCount / $reviews.Count) * 100, 1)

$latestVersion = ($reviews | Where-Object { $_.AppVersion } | Select-Object -First 1).AppVersion

Write-Host "`n[SNAPSHOT SUMMARY]" -ForegroundColor Green
Write-Host " Sample Size              : $($reviews.Count) recent reviews"
Write-Host " Recent Average Rating    : $avgRating / 5.0" -ForegroundColor $(if ($avgRating -ge 4.2) { 'Green' } elseif ($avgRating -ge 3.5) { 'Yellow' } else { 'Red' })
Write-Host " Negative Sentiment Share : $negativePct% (1-star: $star1, 2-star: $star2)" -ForegroundColor $(if ($negativePct -gt 20) { 'Red' } else { 'Green' })
Write-Host " Latest Active Version    : $latestVersion"
Write-Host "`n[RATING BREAKDOWN]" -ForegroundColor Gray
Write-Host " 5 Stars: $('*' * [math]::Round($star5 / 2)) ($star5)" -ForegroundColor Green
Write-Host " 4 Stars: $('*' * [math]::Round($star4 / 2)) ($star4)" -ForegroundColor DarkGreen
Write-Host " 3 Stars: $('*' * [math]::Round($star3 / 2)) ($star3)" -ForegroundColor Yellow
Write-Host " 2 Stars: $('*' * [math]::Round($star2 / 2)) ($star2)" -ForegroundColor DarkYellow
Write-Host " 1 Stars: $('*' * [math]::Round($star1 / 2)) ($star1)" -ForegroundColor Red

# Top Negative Drivers
$critics = $reviews | Where-Object { $_.Rating -le 2 }
$otpIssues = ($critics | Where-Object { $_.Content -match "otp|seat belt|seatbelt" }).Count
$trackingIssues = ($critics | Where-Object { $_.Content -match "track|gps|location|map|eta" }).Count
$crashIssues = ($critics | Where-Object { $_.Content -match "update|crash|uninstall|reinstall|stuck" }).Count
$forceRating = ($critics | Where-Object { $_.Content -match "forcing|rate|feedback|rating" }).Count

Write-Host "`n[CRITICAL FRICTION SIGNALS IN LATEST BATCH]" -ForegroundColor Magenta
Write-Host " - Forced Rating / Blocking Feedback Popups: $forceRating instances"
Write-Host " - OTP / Seatbelt Modal Frustration        : $otpIssues instances"
Write-Host " - GPS Live Tracking / ETA Disparities     : $trackingIssues instances"
Write-Host " - Update Crashes / Freeze / Stuck         : $crashIssues instances"

$output = @{
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    AppId = $AppId
    SampleSize = $reviews.Count
    RecentAverageRating = $avgRating
    NegativeSharePercent = $negativePct
    RatingBreakdown = @{
        Star5 = $star5
        Star4 = $star4
        Star3 = $star3
        Star2 = $star2
        Star1 = $star1
    }
    LatestVersion = $latestVersion
    FrictionSignals = @{
        ForcedRatingBlocks = $forceRating
        OtpModalFrustrations = $otpIssues
        GpsTrackingIssues = $trackingIssues
        CrashUpdateIssues = $crashIssues
    }
}

$output | ConvertTo-Json -Depth 4 | Set-Content $OutputFile -Encoding UTF8
Write-Host "`nHealth metrics exported to $OutputFile" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan
