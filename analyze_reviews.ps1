$reviews = Get-Content "c:\Users\J\Downloads\mvsnz\moveinsync_reviews_comprehensive.json" -Raw | ConvertFrom-Json

Write-Output "Analyzing $($reviews.Count) reviews..."

# Define keyword patterns for categories
$categories = @{
    "Login_Onboarding_OTP" = @("login", "otp", "sign in", "register", "credential", "password", "verification code", "log in", "logs out", "logout")
    "Booking_Roster_Waitlist" = @("book", "roster", "schedule", "waitlist", "shift", "monthly view", "day view", "cancel", "slot")
    "Routing_ETA_Detours" = @("route", "routing", "eta", "google map", "delay", "long time", "darshan", "circuit", "algorithm", "far away", "late cab", "punctual")
    "LiveTracking_GPS" = @("track", "tracking", "gps", "location", "live", "map", "moving", "freeze", "stuck")
    "Boarding_OTP_UX_Popups" = @("seat belt", "seatbelt", "view otp", "otp click", "popup", "pop up", "pop-up", "click", "skip", "force rating", "mandatory rating")
    "Driver_Fleet_Operations" = @("driver", "cab", "van", "transport desk", "vendor", "ac", "rash driving", "call driver", "masking", "behavior")
    "AppStability_Updates_Crashes" = @("update", "crash", "bug", "stuck", "uninstall", "reinstall", "freeze", "hang", "battery", "lag", "heat", "slow")
    "CustomerSupport_Helpdesk" = @("support", "helpdesk", "customer care", "desk", "helptask", "ticket", "response", "no reply", "useless")
}

$classified = @()

foreach ($r in $reviews) {
    $text = ($r.Content + " " + $r.DeveloperReply).ToLower()
    $matchedCats = @()
    
    foreach ($cat in $categories.Keys) {
        foreach ($kw in $categories[$cat]) {
            if ($text -match [regex]::Escape($kw)) {
                $matchedCats += $cat
                break
            }
        }
    }
    
    if ($matchedCats.Count -eq 0) {
        if ($r.Rating -le 2) {
            $matchedCats += "General_Negative_UX"
        } elseif ($r.Rating -ge 4) {
            $matchedCats += "General_Positive_Feedback"
        } else {
            $matchedCats += "Neutral_Unspecified"
        }
    }
    
    $classified += [PSCustomObject]@{
        ReviewId = $r.ReviewId
        Date = $r.Date
        UserName = $r.UserName
        Rating = $r.Rating
        Content = $r.Content
        AppVersion = $r.AppVersion
        ThumbsUp = $r.ThumbsUp
        HasDeveloperReply = ($null -ne $r.DeveloperReply -and $r.DeveloperReply.Trim() -ne "")
        Categories = $matchedCats
    }
}

$classified | ConvertTo-Json -Depth 5 | Set-Content "c:\Users\J\Downloads\mvsnz\reviews_classified.json" -Encoding UTF8

# Analyze Negative Reviews (Rating <= 2)
$negatives = $classified | Where-Object { $_.Rating -le 2 }
Write-Output "`n================================================="
Write-Output "TOTAL REVIEWS: $($reviews.Count)"
Write-Output "NEGATIVE REVIEWS (1-2 Stars): $($negatives.Count) ($([math]::Round($negatives.Count / $reviews.Count * 100, 1))%)"
Write-Output "================================================="

$catCounts = @{}
foreach ($n in $negatives) {
    foreach ($c in $n.Categories) {
        if (-not $catCounts.ContainsKey($c)) { $catCounts[$c] = 0 }
        $catCounts[$c]++
    }
}

Write-Output "`nTOP COMPLAINT DRIVERS (Negative Reviews Breakdown):"
$catCounts.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
    $pct = [math]::Round(($_.Value / $negatives.Count) * 100, 1)
    Write-Output " - $($_.Key): $($_.Value) mentions ($pct%)"
}

# Version breakdown for negative reviews
Write-Output "`nNEGATIVE REVIEWS BY APP VERSION:"
$negatives | Group-Object AppVersion | Sort-Object Count -Descending | Select-Object -First 8 Name, Count | Format-Table -AutoSize

# Developer response analysis
$devRepliesCount = ($reviews | Where-Object { $null -ne $_.DeveloperReply -and $_.DeveloperReply.Trim() -ne "" }).Count
$devReplyNegCount = ($negatives | Where-Object { $null -ne $_.DeveloperReply -and $_.DeveloperReply.Trim() -ne "" }).Count
Write-Output "Developer Reply Rate Overall: $devRepliesCount / $($reviews.Count) ($([math]::Round($devRepliesCount / $reviews.Count * 100, 1))%)"
Write-Output "Developer Reply Rate on Negative: $devReplyNegCount / $($negatives.Count) ($([math]::Round($devReplyNegCount / $negatives.Count * 100, 1))%)"

# Output Top Thumbs-Up Negative Reviews (highest community consensus)
Write-Output "`nTOP IMPACT NEGATIVE REVIEWS (Most Helpful / Agreed):"
$negatives | Sort-Object ThumbsUp -Descending | Select-Object -First 10 Date, Rating, AppVersion, ThumbsUp, Content | Format-List
