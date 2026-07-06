# Service Account Notifications

## Purpose

Monitors Active Directory service account passwords in the `example.domain.net` domain and sends Teams channel notifications when a password is approaching expiration or has already expired.

---

## Script

`SA_Notifications.ps1`

---

## Functions

### `Get-User`
Queries Active Directory via LDAP for a given user and returns account details.

**Returns a PSCustomObject with:**
| Property | Description |
|---|---|
| `UserName` | SAM account name |
| `FullName` | Display name |
| `Comment` | Account description |
| `PasswordLastSet` | Date/time password was last changed |
| `PasswordExpires` | Computed password expiry date (from AD) |
| `AccountExpires` | Date account expires, or `"Never"` |

---

### `Send-TWebhook`
Posts an Adaptive Card message to a Teams channel via a Power Automate webhook URL.

**Parameters:**
| Parameter | Required | Description |
|---|---|---|
| `-Webhook` | Yes | Power Automate HTTP trigger URL |
| `-Header` | No | Card title (bold) |
| `-Body` | No | Card body text |

---

### `Send-SANotification`
Main function. Looks up a user, evaluates password expiry, and sends the appropriate Teams notification.

**Parameters:**
| Parameter | Required | Default | Description |
|---|---|---|---|
| `-TargetUser` | Yes | — | SAM account name to check |
| `-TargetDomain` | Yes | — | LDAP domain (e.g. `svc.nordstrom.com`) |
| `-NotificationThreshold` | No | `10` | Days before expiry to begin sending warnings |
| `-Webhook` | Yes | — | Teams webhook URL |

**Notification behavior:**
| Condition | Action |
|---|---|
| Password expires within threshold (and not yet expired) | Sends warning with days remaining |
| Password is already expired (`DaysUntilExpire <= 0`) | Sends urgent expiry alert |
| User not found in AD | Sends "Could Not Find User" alert |
| Password expires beyond threshold | No notification sent |

---


## Scheduled Task

- **Host:** Example Host
- **Run as:** `SYSTEM`
- **Frequency:** Daily
- **Script path:** Update task action to point to the location of `SA_Notifications.ps1`

> **Note:** The Webhook should be an environment variable must be set at **machine scope** (not user scope) for `SYSTEM` to access it.

---

## Monitored Accounts

| Account | Domain |
|---|---|
| `example_user` | `example.domain.net` |


To add additional accounts, append calls to the bottom of the script:
```powershell
Send-SANotification -TargetUser 'account_name' -TargetDomain "example.domain.net" -Webhook $ENV:TeamsWebhook
```
