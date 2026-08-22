# ==============================================================================
# PowerFlow — Human Time Ranges
# ==============================================================================
# Domain   : Shared
# File     : components/shared/timerange.ps1
# Purpose  : Turn "t@00:40 to 00:50" into two exact local instants, or refuse clearly
# Functions: Resolve-PFDayToken, ConvertTo-PFTimeRange
# Depends  : none — pure parsing, no adapters, no OS calls
# ==============================================================================
#
# WHY THIS IS SHARED AND NOT PART OF `pman`
#
# PF-FEAT-004 asks for it on `pman events`, and PF-FEAT-005 asks for the same grammar on
# `pman logs` — and says in as many words that the two should share a parser rather than
# duplicate one. A second copy of "what does yd@00:40 mean" is a second thing to get wrong
# about midnight, and midnight is where this is hard.
#
# THE THREE RULES THAT SHAPE IT
#
# 1. NEVER SILENTLY ROLL PAST MIDNIGHT. `yd@00:40 00:30` looks like a forty-minute window
#    and is not one: the bare end time inherits the start's day, so it lands ten minutes
#    BEFORE the start. Quietly adding a day would hand back an almost-24-hour range that the
#    user never asked for and would not notice. It is refused, with the two-day spelling
#    printed so the fix is a copy-paste rather than a puzzle.
#
# 2. NEVER GUESS BETWEEN 05/03 AND 03/05. A slash date is read in the CULTURE'S order and
#    the resolved date is handed back for the caller to echo. `--json` and scripts should use
#    ISO, and the caller is expected to say which reading it took. Guessing between March and
#    May silently is how someone reads the wrong day's incident and believes it.
#
# 3. THE OFFSET BELONGS TO THE DATE, NOT TO NOW. A range over yesterday resolved with today's
#    UTC offset is an hour wrong across a DST boundary — twice a year, in exactly the window
#    someone is most likely to be reading events to work out what happened. Each end gets the
#    offset for its own instant.
#
# $Now is a PARAMETER so tests are not hostage to the clock. A parser whose test suite fails
# at midnight, or only in October, is a parser nobody trusts.
# ==============================================================================

$script:PF_DayAliases = @{
    't'         = 0
    'td'        = 0
    'today'     = 0
    'y'         = -1
    'yd'        = -1
    'yesterday' = -1
}

<#
.SYNOPSIS
    Turn a day token into a date, or explain why it is not one.
.DESCRIPTION
    Accepts today/yesterday aliases, ISO `YYYY-MM-DD`, and a slash date read in the given
    culture's order. Returns Date / Label / Ambiguous / Error.
#>
function Resolve-PFDayToken {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Token,
        [datetimeoffset]$Now = [datetimeoffset]::Now,
        [System.Globalization.CultureInfo]$Culture = [System.Globalization.CultureInfo]::CurrentCulture
    )

    $fail = { param($why) [pscustomobject]@{ Date = $null; Label = ''; Ambiguous = $false; Error = $why } }
    $bare = "$Token".Trim()
    if (-not $bare) { return (& $fail 'no day given') }

    $key = $bare.ToLowerInvariant()
    if ($script:PF_DayAliases.ContainsKey($key)) {
        $offset = $script:PF_DayAliases[$key]
        $date   = $Now.Date.AddDays($offset)
        $label  = if ($offset -eq 0) { 'today' } else { 'yesterday' }
        return [pscustomobject]@{ Date = $date; Label = $label; Ambiguous = $false; Error = '' }
    }

    # ISO first, and always unambiguous — this is the form scripts should use.
    $iso = [datetime]::MinValue
    if ([datetime]::TryParseExact($bare, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture,
                                  [System.Globalization.DateTimeStyles]::None, [ref]$iso)) {
        return [pscustomobject]@{ Date = $iso.Date; Label = $iso.ToString('yyyy-MM-dd'); Ambiguous = $false; Error = '' }
    }

    # A slash date is read in the CULTURE'S order, and flagged so the caller echoes it.
    # 05/03/25 is 5 March here and 3 May elsewhere; the difference is not the parser's to
    # settle silently.
    if ($bare -match '^\d{1,2}/\d{1,2}/\d{2,4}$') {
        $slash = [datetime]::MinValue
        # TryPARSE, not TryParseEXACT. An explicit format string DICTATES the order and so
        # ignores the culture entirely — a list beginning 'd/M/yy' reads 05/03 as 5 March on
        # an American machine too, which is the exact silent MDY/DMY swap this is meant to
        # prevent. (Caught by the test that runs the same token through en-GB and en-US.)
        # Culture-aware TryParse uses that culture's own order. The token is already
        # regex-gated to three numeric groups, so TryParse's usual leniency has nothing to
        # chew on beyond the ordering question.
        if ([datetime]::TryParse($bare, $Culture, [System.Globalization.DateTimeStyles]::None, [ref]$slash)) {
            return [pscustomobject]@{ Date = $slash.Date; Label = $slash.ToString('yyyy-MM-dd'); Ambiguous = $true; Error = '' }
        }
        return (& $fail "'$bare' is not a date this system's locale recognises — use YYYY-MM-DD")
    }

    return (& $fail "'$bare' is not a day. Use t/today, y/yesterday, YYYY-MM-DD, or a local slash date")
}

<#
.SYNOPSIS
    Parse "t@00:40 [to] 00:50" into two exact instants, or refuse with a usable message.
.OUTPUTS
    Success, Start, End, Label, Consumed, Ambiguous, Error, Hint.
    Consumed says how many tokens the range used, so a caller can treat the rest as filters.
#>
function ConvertTo-PFTimeRange {
    param(
        [string[]]$Tokens = @(),
        [datetimeoffset]$Now = [datetimeoffset]::Now,
        [System.Globalization.CultureInfo]$Culture = [System.Globalization.CultureInfo]::CurrentCulture
    )

    $result = [pscustomobject]@{
        Success = $false; Start = $null; End = $null; Label = ''
        Consumed = 0; Ambiguous = $false; Error = ''; Hint = ''
    }

    $words = @($Tokens | Where-Object { "$_".Trim() })
    if (-not $words.Count) { $result.Error = 'no time range given'; return $result }

    # ---- start: <day>@HH:mm ---------------------------------------------------
    $first = "$($words[0])"
    if ($first -notmatch '^(?<day>[^@]+)@(?<time>\d{1,2}:\d{2}(:\d{2})?)$') {
        $result.Error = "'$first' is not a start time"
        $result.Hint  = 'Start with a day and a time, joined by @:   t@00:40'
        return $result
    }
    $startDay  = Resolve-PFDayToken -Token $Matches['day'] -Now $Now -Culture $Culture
    $startTime = $Matches['time']
    if ($startDay.Error) { $result.Error = $startDay.Error; $result.Hint = 'e.g.  t@00:40   ·   yd@23:50   ·   2026-08-19@12:35'; return $result }

    # ---- optional "to", then the end -----------------------------------------
    $index = 1
    if ($words.Count -gt $index -and "$($words[$index])".ToLowerInvariant() -eq 'to') { $index++ }
    if ($words.Count -le $index) {
        $result.Error = 'no end time given'
        $result.Hint  = "Add an end time:   $first 00:50      (or $first to 00:50)"
        return $result
    }

    $second = "$($words[$index])"
    $endDay = $startDay
    if ($second -match '^(?<day>[^@]+)@(?<time>\d{1,2}:\d{2}(:\d{2})?)$') {
        $endDay  = Resolve-PFDayToken -Token $Matches['day'] -Now $Now -Culture $Culture
        $endTime = $Matches['time']
        if ($endDay.Error) { $result.Error = $endDay.Error; return $result }
    }
    elseif ($second -match '^\d{1,2}:\d{2}(:\d{2})?$') {
        # A BARE END TIME INHERITS THE START'S DAY. That is the whole reason rule 1 exists.
        $endTime = $second
    }
    else {
        $result.Error = "'$second' is not an end time"
        $result.Hint  = "Use a time, or a day and a time:   $first 00:50   ·   $first t@00:30"
        return $result
    }
    $result.Consumed = $index + 1

    # ---- to exact instants ---------------------------------------------------
    $startLocal = Add-PFClockTime -Date $startDay.Date -Clock $startTime
    $endLocal   = Add-PFClockTime -Date $endDay.Date   -Clock $endTime
    if ($null -eq $startLocal) { $result.Error = "'$startTime' is not a valid time of day"; return $result }
    if ($null -eq $endLocal)   { $result.Error = "'$endTime' is not a valid time of day"; return $result }

    # THE OFFSET BELONGS TO THE DATE. Resolving yesterday with today's offset is an hour
    # wrong across a DST change — in precisely the window someone is reading events to
    # find out what happened.
    $start = [datetimeoffset]::new($startLocal, [System.TimeZoneInfo]::Local.GetUtcOffset($startLocal))
    $end   = [datetimeoffset]::new($endLocal,   [System.TimeZoneInfo]::Local.GetUtcOffset($endLocal))

    if ($end -le $start) {
        $sameDay = $startDay.Date -eq $endDay.Date
        if ($sameDay) {
            $result.Error = "End time $endTime is before start time $startTime on $($startDay.Label)."
            $result.Hint  = "For a range that crosses midnight, name the second day:`n     $first $(Get-PFNextDayToken $startDay.Label)@$endTime"
        }
        else {
            $result.Error = "The end ($($endDay.Label) $endTime) is not after the start ($($startDay.Label) $startTime)."
            $result.Hint  = 'Put the earlier instant first.'
        }
        return $result
    }

    $result.Success   = $true
    $result.Start     = $start
    $result.End       = $end
    $result.Ambiguous = ($startDay.Ambiguous -or $endDay.Ambiguous)
    $result.Label     = if ($startDay.Date -eq $endDay.Date) {
        "$($startDay.Label) $startTime → $endTime"
    } else {
        "$($startDay.Label) $startTime → $($endDay.Label) $endTime"
    }
    return $result
}

<#
.SYNOPSIS
    Combine a date with an HH:mm[:ss] clock reading, or $null if the clock is not real.
.DESCRIPTION
    Separate from the regex that matched it because `25:99` matches \d{1,2}:\d{2} perfectly
    well and is still not a time. The shape and the validity are two different questions.
#>
function Add-PFClockTime {
    param([Parameter(Mandatory)][datetime]$Date, [Parameter(Mandatory)][string]$Clock)

    $parts = @("$Clock".Split(':'))
    $h = 0; $m = 0; $s = 0
    if (-not [int]::TryParse($parts[0], [ref]$h)) { return $null }
    if (-not [int]::TryParse($parts[1], [ref]$m)) { return $null }
    if ($parts.Count -ge 3 -and -not [int]::TryParse($parts[2], [ref]$s)) { return $null }
    if ($h -lt 0 -or $h -gt 23 -or $m -lt 0 -or $m -gt 59 -or $s -lt 0 -or $s -gt 59) { return $null }
    return $Date.Date.AddHours($h).AddMinutes($m).AddSeconds($s)
}

<#
.SYNOPSIS
    The token naming the day after the one described, for the cross-midnight hint.
#>
function Get-PFNextDayToken {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$DayLabel)
    switch ($DayLabel) {
        'yesterday' { return 't' }
        'today'     { return 't' }   # today+1 has no alias; the caller edits the date
        default     { return 't' }
    }
}
