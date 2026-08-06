# Saved SSH endpoints appeared before authentication

**Status:** Fix applied — awaiting user confirmation.

## Symptom

Normal `srv` use repeated the stored SSH username, address, and sometimes port in connection
banners and management views. This exposed details the operator had already supplied when the
alias was created.

## Cause

`servers.ps1` combined persistence, public presentation, and native SSH target construction.
Because the same formatted endpoint was convenient for all three jobs, it spread into lists,
picker rows, confirmations, warnings, and connection output.

## Fix

The endpoint-sensitive work now has a separate `server-privacy.ps1` component:

- ordinary views receive only an alias and live status;
- direct connection passes the stored port and target to native OpenSSH without a PowerFlow
  endpoint banner;
- `srv <name> info` runs a constant, non-mutating SSH authentication probe and reveals details
  only when that process succeeds;
- failed, cancelled, and redirected authentication keeps the endpoint hidden; and
- PowerFlow never captures, stores, or validates the password itself.

Native OpenSSH still owns the credential prompt and can display its own target while asking for
a password. Hiding that would require intercepting credentials, which this design deliberately
does not do.

## Regression protection

The network suite uses sentinel-only fixture endpoints and asserts that ordinary output cannot
contain them. Separate tests verify exact native SSH argument tokens and both the success and
failure sides of authenticated info. Windows and Linux release-validation workflows run the
suite.
