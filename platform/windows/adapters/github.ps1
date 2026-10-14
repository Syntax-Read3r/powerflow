# ==============================================================================
# PowerFlow — GitHub Credentials Adapter (Windows)
# Domain   : Platform / Windows
# File     : platform/windows/adapters/github.ps1
# Purpose  : Preserve the existing Windows Credential Manager token store
# Contract : Get-GitHubSavedToken, Set-GitHubSavedToken, Remove-GitHubSavedToken, Show-GitHubTokenStatus
# Depends  : cmdkey, Windows credential API
# ==============================================================================

function Set-GitHubSavedToken {
    param([string]$Token)
    $credentialName = "gh-l-github-token"
    try {
        $result = & cmdkey /generic:$credentialName /user:github /pass:$Token 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Token saved securely in Windows Credential Manager" -ForegroundColor Green
            return $true
        } else {
            Write-Host "⚠️ Could not save to Credential Manager." -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "⚠️ Could not save token to Credential Manager." -ForegroundColor Yellow
        return $false
    }
}

function Get-GitHubSavedToken {
    $credentialName = "gh-l-github-token"
    try {
        $result = & cmdkey /list:$credentialName 2>&1
        if ($LASTEXITCODE -eq 0 -and $result -match "GENERIC") {
            if (-not ([System.Management.Automation.PSTypeName]'CredentialManager').Type) {
                Add-Type -TypeDefinition @"
                using System;
                using System.Runtime.InteropServices;
                using System.Text;

                public class CredentialManager
                {
                    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
                    public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

                    [DllImport("advapi32.dll", SetLastError = true)]
                    public static extern void CredFree(IntPtr cred);

                    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
                    public struct CREDENTIAL
                    {
                        public int Flags;
                        public int Type;
                        public string TargetName;
                        public string Comment;
                        public long LastWritten;
                        public int CredentialBlobSize;
                        public IntPtr CredentialBlob;
                        public int Persist;
                        public int AttributeCount;
                        public IntPtr Attributes;
                        public string TargetAlias;
                        public string UserName;
                    }

                    public static string GetPassword(string target)
                    {
                        IntPtr credPtr;
                        if (CredRead(target, 1, 0, out credPtr))
                        {
                            var credential = (CREDENTIAL)Marshal.PtrToStructure(credPtr, typeof(CREDENTIAL));
                            var password = Marshal.PtrToStringUni(credential.CredentialBlob, credential.CredentialBlobSize / 2);
                            CredFree(credPtr);
                            return password;
                        }
                        return null;
                    }
                }
"@
            }
            $password = [CredentialManager]::GetPassword($credentialName)
            if ($password) {
                Write-Host "🔐 Using saved token from Credential Manager" -ForegroundColor DarkGreen
                return $password
            }
        }
        return $null
    } catch {
        return $null
    }
}

function Remove-GitHubSavedToken {
    $credentialName = "gh-l-github-token"
    try {
        $result = & cmdkey /delete:$credentialName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "🗑️ GitHub token removed from Credential Manager" -ForegroundColor Green
        } else {
            Write-Host "ℹ️ No saved token found in Credential Manager" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "⚠️ Could not remove the saved GitHub token." -ForegroundColor Yellow
    }
}

function Show-GitHubTokenStatus {
    $credentialName = "gh-l-github-token"
    try {
        $result = & cmdkey /list:$credentialName 2>&1
        if ($LASTEXITCODE -eq 0 -and $result -match "GENERIC") {
            Write-Host "✅ GitHub token is saved in Credential Manager" -ForegroundColor Green
        } else {
            Write-Host "ℹ️ No GitHub token saved" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "ℹ️ No GitHub token saved" -ForegroundColor Yellow
    }
}
