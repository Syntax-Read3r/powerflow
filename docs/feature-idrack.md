this feature should only be runable in idrack similar to pmx or proxmox

Tiny lesson: think of RACADM as the **T440’s remote control room**:

* **Green instruments** only read information.
* **Amber switches** change configuration.
* **Red levers** can interrupt service or erase data.

For PowerFlow, expose the green instruments freely, put confirmation prompts on amber switches, and heavily guard the red levers.

## First: the authoritative command list

RACADM commands vary by iDRAC firmware, server generation, installed hardware and licence. The exact list for **your T440** is:

```text
racadm help
```

For details about one command:

```text
racadm help serveraction
racadm help storage
racadm help get
```

Dell states that `racadm help` lists the subcommands actually available, while `racadm help <subcommand>` explains one command. In the interactive RACADM shell, pressing **Tab** can also display available commands. ([Dell][1])

## Recommended PowerFlow command structure

These are the commands an ordinary T440 administrator should learn first.

### Green: safe monitoring commands

| PowerFlow idea              | RACADM command                    | Purpose                                       |
| --------------------------- | --------------------------------- | --------------------------------------------- |
| `idrac help`                | `racadm help`                     | List available commands                       |
| `idrac help power`          | `racadm help serveraction`        | Explain a command                             |
| `idrac info`                | `racadm getsysinfo`               | General iDRAC and server information          |
| `idrac tag`                 | `racadm getsvctag`                | Show Dell Service Tag                         |
| `idrac versions`            | `racadm getversion`               | Firmware and component versions               |
| `idrac power status`        | `racadm serveraction powerstatus` | Show ON or OFF                                |
| `idrac health`              | `racadm getsensorinfo`            | Temperatures, fans, voltages and power health |
| `idrac hardware`            | `racadm hwinventory`              | Hardware inventory                            |
| `idrac software`            | `racadm swinventory`              | Installed firmware/software inventory         |
| `idrac storage status`      | `racadm storage get status`       | Overall storage state                         |
| `idrac storage controllers` | `racadm storage get controllers`  | List storage controllers                      |
| `idrac storage disks`       | `racadm storage get pdisks and vdisks`      | List physical disks                           |
| `idrac storage pdisks`       | `racadm storage get pdisks`      | List physical disks                           |
| `idrac storage vdisks`      | `racadm storage get vdisks`       | List virtual disks                            |
| `idrac logs sel`            | `racadm getsel`                   | System Event Log                              |
| `idrac logs lifecycle`      | `racadm lclog view`               | Lifecycle Controller log                      |
| `idrac jobs`                | `racadm jobqueue view`            | Pending and completed jobs                    |
| `idrac sessions`            | `racadm getssninfo`               | Logged-in iDRAC sessions                      |
| `idrac time`                | `racadm getractime`               | iDRAC clock                                   |
| `idrac led status`          | `racadm getled`                   | Identification LED status                     |
| `idrac network`             | `racadm get iDRAC.NIC`            | iDRAC network configuration                   |
| `idrac netstat`             | `racadm netstat`                  | iDRAC network connections                     |
| `idrac ping <host>`         | `racadm ping <host>`              | Test IPv4 reachability from iDRAC             |
| `idrac trace <host>`        | `racadm traceroute <host>`        | Trace the route from iDRAC                    |
| `idrac remote-services`     | `racadm getremoteservicesstatus`  | Lifecycle/remote-services status              |
| `idrac dump`                | `racadm racdump`                  | Broad diagnostic information                  |

Dell documents `getsysinfo`, inventories, sensors, logs, storage inspection and the job queue as RACADM management functions. Storage changes require greater privileges, but the `storage get ...` commands above are inventory checks. ([Dell][2])

## Amber: commands that change state

These need PowerFlow confirmation.

| PowerFlow idea              | RACADM command                          | Effect                                 |
| --------------------------- | --------------------------------------- | -------------------------------------- |
| `idrac power on`            | `racadm serveraction powerup`           | Turn the T440 on                       |
| `idrac power shutdown`      | `racadm serveraction graceshutdown`     | Ask the OS to shut down cleanly        |
| `idrac identify on/off`     | `racadm setled ...`                     | Control the front identification light |
| `idrac controller restart`  | `racadm racreset soft`                  | Restart iDRAC, not the T440            |
| `idrac config get <object>` | `racadm get <object>`                   | Read configuration                     |
| `idrac config set ...`      | `racadm set ...`                        | Change configuration                   |
| `idrac update ...`          | `racadm update ...`                     | Install firmware                       |
| `idrac rollback ...`        | `racadm rollback ...`                   | Roll firmware back                     |
| `idrac cert ...`            | `sslcert*`, `sslcsrgen`, `sslkeyupload` | Manage HTTPS certificates              |
| `idrac ssh-key ...`         | `racadm sshpkauth ...`                  | Manage SSH public keys                 |
| `idrac licence ...`         | `racadm license ...`                    | View/import/export licences            |
| `idrac test email`          | `racadm testemail ...`                  | Test email alerts                      |
| `idrac test syslog`         | `racadm testrsyslogconnection ...`      | Test remote logging                    |
| `idrac support collect`     | `racadm supportassist ...`              | Produce support data                   |

A `set` operation can apply immediately or become **pending** until a job and reboot apply it. BIOS, NIC and some storage changes may therefore need `jobqueue`. Firmware updates also create jobs whose progress is checked with `jobqueue view`. ([Dell][3])

## Red: disruptive or destructive commands

PowerFlow should never execute these without an explicit warning and confirmation.

| Command                               | Risk                           |
| ------------------------------------- | ------------------------------ |
| `racadm serveraction powerdown`       | Immediate power-off            |
| `racadm serveraction powercycle`      | Power off and back on          |
| `racadm serveraction hardreset`       | Forced server reset            |
| `racadm clrsel`                       | Clears the System Event Log    |
| `racadm jobqueue delete --all`        | Removes all jobs               |
| `racadm clearpending ...`             | Discards pending configuration |
| `racadm storage ...` write operations | Can alter arrays or disks      |
| `racadm racresetcfg`                  | Resets iDRAC configuration     |
| `racadm sslresetcfg`                  | Resets SSL configuration       |
| `racadm systemerase`                  | Erases selected system data    |
| `racadm coredumpdelete`               | Deletes diagnostic dumps       |
| `racadm sslcertdelete`                | Deletes certificates           |

`powercycle`, `powerdown` and `hardreset` can interrupt Proxmox and every running VM. Prefer a clean Proxmox shutdown first. Dell describes `serveraction` as the server power-control family, while `racreset` restarts iDRAC itself and may leave iDRAC unavailable for roughly two minutes. ([Dell][4])

A good PowerFlow safety pattern would be:

```text
Green command:
Run immediately.

Amber command:
Display intended change and request confirmation.

Red command:
Show affected server, action and risk.
Require the user to type the server name or exact confirmation phrase.
```

## Full current RACADM command-family inventory

Dell’s current iDRAC9 7.xx guide lists the following command families. **Not every one will appear on your T440**; Fibre Channel, InfiniBand, chassis, vFlash and newer-platform commands depend on hardware and firmware. ([Dell][5])

### Core and configuration

```text
help
get
set
cd
connect
racadm proxy
```

### Identity, power and front panel

```text
getsvctag
getsysinfo
getversion
getled
setled
frontpanelerror
serveraction
witnessnodepoweraction
```

`witnessnodepoweraction` is platform-specific and is not a normal T440 command.

### Health, sensors and performance

```text
getsensorinfo
sensorsettings
getmetrics
systemperfstatistics
inlettemphistory
getremoteservicesstatus
```

### Logs, sessions and diagnostics

```text
getsel
clrsel
lclog
getraclog
gettracelog
getssninfo
closessn
getractime
racdump
coredump
coredumpexport
coredumpdelete
diagnostics
serialcapture
clearasrscreen
```

### Network tools

```text
arp
ifconfig
getniccfg
setniccfg
gethostnetworkinterfaces
netstat
nicstatistics
networktransceiverstatistics
ping
ping6
traceroute
traceroute6
switchconnection
```

### Hardware and storage

```text
hwinventory
swinventory
storage
pcieslotview
fcstatistics
infinibandstatistics
spdm
ackdriveremoval
```

Fibre Channel and InfiniBand commands matter only when those devices exist.

### Firmware, Lifecycle Controller and jobs

```text
update
fwupdate
rollback
recover
jobqueue
clearpending
driverpack
autoupdatescheduler
biosscan
exposeisminstallertohost
```

### Security, certificates and authentication

```text
bioscert
httpsbootcert
sshpkauth
sslcertview
sslcertupload
sslcertdownload
sslcertdelete
sslcsrgen
sslkeyupload
sslresetcfg
usercertupload
usercertview
krbkeytabupload
license
ilkm
sekm
```

### Alerts and event handling

```text
eventfilters
testalert
testemail
testtrap
testrsyslogconnection
```

### Remote media and support

```text
remoteimage
remoteimage2
vmdisconnect
vflashsd
vflashpartition
supportassist
techsupreport
plugin
```

### Reset, erase and specialised administration

```text
racreset
racresetcfg
systemerase
cmreset
groupmanager
```

Some older command names remain documented but newer replacements are preferred:

```text
getconfig     → get
config        → set
getuscversion → getversion
raid          → storage
```

Dell marks these as deprecated or replaced command names. ([Dell][6])

## Best initial PowerFlow vocabulary

Do not begin by implementing every specialist function. Start with this stable command tree:

```text
idrac info
idrac health
idrac versions
idrac power status
idrac power on
idrac power shutdown
idrac hardware
idrac storage status
idrac storage disks
idrac storage volumes
idrac logs sel
idrac logs lifecycle
idrac jobs
idrac sessions
idrac network
idrac ping
idrac controller restart
idrac help
```

Next, run:

```text
racadm help
```

Use that output as the exact source of truth for the PowerFlow module on your T440, rather than implementing commands that your firmware or hardware does not support.

[1]: https://www.dell.com/support/manuals/en-us/idrac9-lifecycle-controller-v5.x-series/idrac9_5.xx_racadm_pub/help-and-help-subcommand?guid=guid-478693f4-f49a-48a5-b02b-74562b05b0af&lang=en-us "Integrated Dell Remote Access Controller 9 RACADM CLI Guide | Dell Belgique"
[2]: https://www.dell.com/support/manuals/en-us/integrated-dell-remote-access-cntrllr-8-with-lifecycle-controller-v2.00.00.00/racadm_idrac_pub-v1/getsysinfo?guid=guid-13aa70a5-0957-4d2a-9259-24a471932274&lang=en-us&utm_source=chatgpt.com "getsysinfo"
[3]: https://www.dell.com/support/manuals/en-us/idrac9-lifecycle-controller-v7.x-series/idrac9_7.xx_racadm_pub/set?guid=guid-799c4585-0d9f-4e27-8c79-38525e9d5643&lang=en-us&utm_source=chatgpt.com "Integrated Dell Remote Access Controller 9 RACADM CLI Guide | Dell US"
[4]: https://www.dell.com/support/manuals/en-us/integrated-dell-remote-access-cntrllr-8-with-lifecycle-controller-v2.00.00.00/racadm_idrac_pub-v1/serveraction?guid=guid-69ea52c5-153d-4369-b7c4-6694a3b9e0d4&lang=en-us&utm_source=chatgpt.com "RACADM Command Options"
[5]: https://www.dell.com/support/manuals/en-us/idrac9-lifecycle-controller-v7.x-series/idrac9_7.xx_racadm_pub/using-autocomplete-feature?guid=guid-dc0696c6-8daa-4ead-b6df-e7d2a26cf5f6&lang=en-us "Integrated Dell Remote Access Controller 9 RACADM CLI Guide | Dell Belgique"
[6]: https://www.dell.com/support/manuals/en-us/idrac9-lifecycle-controller-v5.x-series/idrac9_5.xx_racadm_pub/deprecated-and-new-subcommands?guid=guid-9c6561ca-4562-46e1-bc91-c67c45c5dee7&lang=en-us&utm_source=chatgpt.com "Integrated Dell Remote Access Controller 9 RACADM CLI ..."


I ran: racadm help and this was the result: 


root@192.168.8.10's password:
racadm>>racadm serveraction powerup
Server power operation initiated successfully
racadm>>racadm help

 help                 -- Display list of RACADM sub commands with help string
 help [subcommand]    -- display usage summary for a subcommand
 arp                  -- display the networking ARP table
 autoupdatescheduler  -- Automatic Platform Update of the devices on the server.
 bioscert             -- Secure Boot Certificate Management operations
 biosscan             -- Performs BIOS live scanning or creates a recurrent job for live scanning.
 clearasrscreen       -- clear the last ASR (crash) screen
 clearpending         -- clear pending attribute(s) value of a Device Class
 closessn             -- close a session
 clrsel               -- clear the System Event Log (SEL)
 config               -- Deprecated: modify RAC configuration properties
 coredump             -- display the last RAC coredump
 coredumpdelete       -- delete the last RAC coredump
 driverpack           -- display driverpack info
 debug                -- Field Service Debug Authorization facility commands
 eventfilters         -- Alerts configuration commands
 exposeisminstallertohost -- Support Assist operations.
 fwupdate             -- update the RAC firmware
 get                  -- display RAC configuration properties
 getconfig            -- Deprecated: display RAC configuration properties
 gethostnetworkinterfaces -- Display host network interface details
 getled               -- Get the state of the LED on a module.
 getniccfg            -- display current network settings
 getraclog            -- display the RAC log
 getractime           -- display the current RAC time
 getremoteservicesstatus -- display remote services status
 getsel               -- display records from the System Event Log (SEL)
 getsensorinfo        -- display system sensors
 getssninfo           -- display session information
 getsvctag            -- display service tag information
 getsysinfo           -- display general RAC and system information
 gettracelog          -- display the RAC diagnostic trace log
 getuscversion        -- Deprecated: display the current USC version details
 getversion           -- display the current version details
 groupmanager         -- Groupmanager commands
 httpsbootcert        -- Bios HTTPS Boot Certificate Management operations
 ifconfig             -- display network interface information
 inlettemphistory     -- inlet temperature history operations
 idmconfig            -- modify RAC configuration properties through IDM
 license              -- License Manager commands
 lclog                -- LCLog operations
 frontpanelerror      -- hide LCD errors - color amber to blue
 netstat              -- display routing table and network statistics
 ping                 -- send ICMP echo packets on the network
 ping6                -- send ICMP echo packets on the network
 racdump              -- display RAC diagnostic information
 racreset             -- perform a RAC reset operation
 racresetcfg          -- restore the RAC configuration to factory defaults
 recover              -- Recover firmware to its previous version.
 remoteimage          -- make a remote ISO image available to the server
 rollback             -- Rollback firmware to its previous version.
 sekm                 -- SEKM commands
 serialcapture        -- Serial Data Capture Commands
 serveraction         -- perform system power management operations
 set                  -- modify RAC configuration properties
 setled               -- Set the state of the LED on a module.
 setniccfg            -- modify network configuration properties
 sshpkauth            -- manage SSH PK authentication keys on the RAC
 sslcertdelete        -- delete an SSL certificate on the iDRAC
 sslcertview          -- view SSL certificate information
 sslcsrgen            -- generate a certificate CSR from the RAC
 sslencryptionstrength -- Deprecated: Display or modify the SSL Encryption strength.
 sslresetcfg          -- Reset iDRAC to apply new certificate. Until iDRAC is reset old certificate will be active.
 supportassist        -- Support Assist operations.
 swinventory          -- Display the list of S/W Installed on the server.
 switchconnection     -- Display physical mapping of switch ports
 to server ports and iDRAC dedicated port
 systemconfig         -- Backup &/or Restore of iDRAC Config and Firmware
 systemerase          -- Performs system erase on a selected component.
 testemail            -- test RAC e-mail notifications
 testrsyslogconnection -- Display Testrsyslogconnection info.
 testtrap             -- test RAC SNMP trap notifications
 testalert            -- test RAC SNMP - FQDN trap notifications
 traceroute           -- print the route packets trace to network host
 traceroute6          -- print the route packets trace to network host
 techsupreport        -- Tech Support Report operations.
 usercertview         -- view user certificate information
 vflashpartition      -- manage partitions on the vFlash SD card
 vflashsd             -- perform vFlash SD Card initialization
 vmdisconnect         -- disconnect Virtual Media connections
 raid                 -- Monitoring and Inventory of H/W RAID connected to the server.
 storage              -- Monitoring and Inventory of H/W RAID connected to the server.
 hwinventory          -- Monitoring and Inventory of H/W NICs connected to the server.
 nicstatistics        -- Statistics for NICs connected to the server.
 fcstatistics         -- Statistics for FCs connected to the server.
 networktransceiverstatistics -- Statistics for NicTransceivers connected to the server.
 update               -- Platform Update of the devices on the server
 jobqueue             -- Jobqueue of of the jobs currently scheduled
 sensorsettings       -- Set the sensor threshold levels.
 diagnostics          -- Remote Diagnostic commands
 systemperfstatistics -- Display or Modify System Performance Statistics

 Groups

 BIOS                -- Configuration of BIOS attributes
 iDRAC               -- Configuration of iDRAC attributes
 LifecycleController -- Configuration of LifecycleController attributes
 Nic                 -- Configuration of NIC attributes
 Storage             -- Configuration of Storage attributes
 System              -- Configuration of System attributes
 FC                  -- Configuration of Fiber Channel attributes

For Help on configuring the properties of a group - racadm help set