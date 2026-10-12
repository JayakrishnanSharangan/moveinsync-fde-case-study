Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Text.RegularExpressions;

public class JsonHelper {
    public static string Unescape(string input) {
        return Regex.Unescape(input);
    }
}
"@

function Fetch-Reviews {
    param(
        [string]$AppId = "com.moveinsync.ets",
        [int]$Sort = 2, # 1 = Relevance, 2 = Newest, 3 = Rating
        [int]$Count = 100,
        [string]$Score = "null" # 1, 2, 3, 4, 5, or "null"
    )

    $payloadTemplate = "f.req=%5B%5B%5B%22oCPfdb%22%2C%22%5Bnull%2C%5B2%2C{0}%2C%5B{1}%5D%2Cnull%2C%5Bnull%2C{2}%2Cnull%2Cnull%2Cnull%2Cnull%2Cnull%2Cnull%2Cnull%5D%5D%2C%5B%5C%22{3}%5C%22%2C7%5D%5D%22%2Cnull%2C%22generic%22%5D%5D%5D%0A"
    $body = [string]::Format($payloadTemplate, $Sort, $Count, $Score, $AppId)
    $url = "https://play.google.com/_/PlayStoreUi/data/batchexecute?hl=en&gl=in"

    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
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
                BatchFilter = "Sort=$Sort, Score=$Score"
            }
        }
        return $list
    } catch {
        Write-Warning "Error fetching: $_"
        return @()
    }
}

Write-Output "Fetching Batch 1: Newest 100 reviews (all ratings)..."
$batch1 = Fetch-Reviews -Sort 2 -Count 100 -Score "null"
Write-Output "Batch 1: $($batch1.Count) reviews."

Start-Sleep -Seconds 1
Write-Output "Fetching Batch 2: 1-Star reviews (100 reviews)..."
$batch2 = Fetch-Reviews -Sort 2 -Count 100 -Score "1"
Write-Output "Batch 2: $($batch2.Count) reviews."

Start-Sleep -Seconds 1
Write-Output "Fetching Batch 3: 2-Star reviews (50 reviews)..."
$batch3 = Fetch-Reviews -Sort 2 -Count 50 -Score "2"
Write-Output "Batch 3: $($batch3.Count) reviews."

Start-Sleep -Seconds 1
Write-Output "Fetching Batch 4: 3-Star reviews (50 reviews)..."
$batch4 = Fetch-Reviews -Sort 2 -Count 50 -Score "3"
Write-Output "Batch 4: $($batch4.Count) reviews."

Start-Sleep -Seconds 1
Write-Output "Fetching Batch 5: Most Helpful / Relevant (100 reviews)..."
$batch5 = Fetch-Reviews -Sort 1 -Count 100 -Score "null"
Write-Output "Batch 5: $($batch5.Count) reviews."

$all = @($batch1) + @($batch2) + @($batch3) + @($batch4) + @($batch5)
Write-Output "Total raw fetched: $($all.Count)"

# Deduplicate by ReviewId
$unique = $all | Group-Object ReviewId | ForEach-Object { $_.Group[0] }
Write-Output "Total unique reviews collected: $($unique.Count)"

$unique | Export-Csv -Path "c:\Users\J\Downloads\mvsnz\moveinsync_reviews_comprehensive.csv" -NoTypeInformation -Encoding UTF8
$unique | ConvertTo-Json -Depth 5 | Set-Content "c:\Users\J\Downloads\mvsnz\moveinsync_reviews_comprehensive.json" -Encoding UTF8

Write-Output "`n=== RATING BREAKDOWN OF COLLECTED DATASET ==="
$unique | Group-Object Rating | Sort-Object Name | Select-Object Name, Count | Format-Table -AutoSize

Write-Output "Comprehensive dataset created successfully!"
