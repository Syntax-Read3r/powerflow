$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

# ==============================================================================
# The human time-range grammar (PF-FEAT-004), which PF-FEAT-005 also waits on.
#
# $Now IS INJECTED throughout. A parser tested against the real clock passes in the morning
# and fails at 23:59, or only during British Summer Time -- and a suite that fails by the
# hour is one people learn to re-run rather than read.
# ==============================================================================

$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $repo 'components/shared/timerange.ps1')

# A fixed reference instant: Wednesday 19 August 2026, 14:30 local.
$now = [datetimeoffset]::new([datetime]::new(2026, 8, 19, 14, 30, 0), [System.TimeZoneInfo]::Local.GetUtcOffset([datetime]::new(2026, 8, 19, 14, 30, 0)))
$uk  = [System.Globalization.CultureInfo]::GetCultureInfo('en-GB')
$us  = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')

# ---- day tokens -------------------------------------------------------------
foreach ($t in 't', 'td', 'today', 'T', 'Today') {
    $d = Resolve-PFDayToken -Token $t -Now $now
    Assert-True ($d.Date -eq [datetime]::new(2026, 8, 19)) "'$t' resolves to today"
    Assert-True ($d.Label -eq 'today') "'$t' is labelled today"
}
foreach ($t in 'y', 'yd', 'yesterday') {
    $d = Resolve-PFDayToken -Token $t -Now $now
    Assert-True ($d.Date -eq [datetime]::new(2026, 8, 18)) "'$t' resolves to yesterday"
}
$iso = Resolve-PFDayToken -Token '2026-03-05' -Now $now
Assert-True ($iso.Date -eq [datetime]::new(2026, 3, 5)) 'an ISO date resolves exactly'
Assert-True (-not $iso.Ambiguous) 'an ISO date is never ambiguous'

# A SLASH DATE IS READ IN THE CULTURE'S ORDER, and flagged so the caller echoes it.
# 05/03 is 5 March in Britain and 3 May in America; guessing silently is how someone reads
# the wrong day's incident and believes it.
$gb = Resolve-PFDayToken -Token '05/03/26' -Now $now -Culture $uk
Assert-True ($gb.Date -eq [datetime]::new(2026, 3, 5)) 'en-GB reads 05/03 as 5 March'
Assert-True ($gb.Ambiguous) 'and flags it so the caller can echo the reading'
$am = Resolve-PFDayToken -Token '05/03/26' -Now $now -Culture $us
Assert-True ($am.Date -eq [datetime]::new(2026, 5, 3)) 'en-US reads the same token as 3 May'

Assert-True ((Resolve-PFDayToken -Token 'wibble' -Now $now).Error -ne '') 'a non-day is refused'
Assert-True ((Resolve-PFDayToken -Token '' -Now $now).Error -ne '') 'an empty day is refused without throwing'

# ---- the ordinary range -----------------------------------------------------
$r = ConvertTo-PFTimeRange -Tokens @('t@00:40', '00:50') -Now $now
Assert-True $r.Success 'a plain range parses'
Assert-True ($r.Start.Hour -eq 0 -and $r.Start.Minute -eq 40) 'start is 00:40'
Assert-True ($r.End.Minute -eq 50) 'end is 00:50'
Assert-True ($r.Start.Date -eq [datetime]::new(2026, 8, 19)) 'on today'
Assert-True ($r.End.Date -eq $r.Start.Date) 'a bare end time inherits the start day'
Assert-True ($r.Consumed -eq 2) 'two tokens consumed'

# `to` is optional visual grammar and must not change the answer.
$withTo = ConvertTo-PFTimeRange -Tokens @('t@00:40', 'to', '00:50') -Now $now
Assert-True ($withTo.Success -and $withTo.Start -eq $r.Start -and $withTo.End -eq $r.End) '"to" is optional and changes nothing'
Assert-True ($withTo.Consumed -eq 3) 'but it counts as a consumed token'

# Trailing tokens are left for the caller to use as filters.
$filtered = ConvertTo-PFTimeRange -Tokens @('t@12:35', '12:42', 'web-test') -Now $now
Assert-True ($filtered.Success -and $filtered.Consumed -eq 2) 'the range stops before a container name'

# ---- THE END-BEFORE-START RULE ---------------------------------------------
# A bare end time inherits the start's day, so yd@00:40 00:30 is ten minutes EARLIER, not
# a range crossing midnight. Silently adding a day would hand back an almost-24-hour window
# the user never asked for and would not notice.
$bad = ConvertTo-PFTimeRange -Tokens @('yd@00:40', '00:30') -Now $now
Assert-True (-not $bad.Success) 'an end before the start is refused'
Assert-True ($bad.Error -match 'before start time') 'and says so plainly'
Assert-True ($bad.Hint -match 'crosses midnight') 'and offers the two-day spelling'
Assert-True ($null -eq $bad.Start) 'a refused range yields no instants to act on'

# Naming the second day explicitly is how you really cross midnight, and it must work.
$cross = ConvertTo-PFTimeRange -Tokens @('yd@23:50', 't@00:30') -Now $now
Assert-True $cross.Success 'an explicit two-day range is accepted'
Assert-True ($cross.Start.Date -eq [datetime]::new(2026, 8, 18)) 'starting yesterday'
Assert-True ($cross.End.Date -eq [datetime]::new(2026, 8, 19)) 'and ending today'
Assert-True ($cross.End -gt $cross.Start) 'with the end genuinely after the start'

# An equal start and end is not a range either.
Assert-True (-not (ConvertTo-PFTimeRange -Tokens @('t@10:00', '10:00') -Now $now).Success) 'a zero-length range is refused'

# ---- malformed input teaches rather than throws -----------------------------
foreach ($case in @(
    @{ T = @();                     Why = 'no tokens' }
    @{ T = @('00:40', '00:50');     Why = 'a start with no day' }
    @{ T = @('t@00:40');            Why = 'no end time' }
    @{ T = @('t@00:40', 'to');      Why = 'a dangling to' }
    @{ T = @('t@25:00', '01:00');   Why = 'an impossible hour' }
    @{ T = @('t@00:70', '01:00');   Why = 'an impossible minute' }
    @{ T = @('t@00:40', 'wibble');  Why = 'a nonsense end' }
)) {
    $bad = ConvertTo-PFTimeRange -Tokens $case.T -Now $now
    Assert-True (-not $bad.Success) "refused: $($case.Why)"
    Assert-True ([bool]$bad.Error) "and explains: $($case.Why)"
}

# ---- THE OFFSET BELONGS TO THE DATE ----------------------------------------
# A range resolved with today's offset is an hour wrong across a DST boundary -- twice a
# year, in exactly the window someone is reading events to work out what happened. In a
# zone that observes DST, instants either side of the change must carry different offsets.
if ([System.TimeZoneInfo]::Local.SupportsDaylightSavingTime) {
    $winter = [datetimeoffset]::new([datetime]::new(2026, 1, 15, 12, 0, 0), [System.TimeZoneInfo]::Local.GetUtcOffset([datetime]::new(2026, 1, 15, 12, 0, 0)))
    $summerRange = ConvertTo-PFTimeRange -Tokens @('2026-07-15@12:00', '13:00') -Now $winter
    $winterRange = ConvertTo-PFTimeRange -Tokens @('2026-01-15@12:00', '13:00') -Now $winter
    Assert-True ($summerRange.Success -and $winterRange.Success) 'both explicit-date ranges parse'
    Assert-True ($summerRange.Start.Offset -ne $winterRange.Start.Offset) 'each instant carries the offset for its own date, not for now'
}

Write-Host 'OK - human time ranges resolve exactly, refuse to cross midnight silently, and never guess a date order.'
