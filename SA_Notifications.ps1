function Get-User {
    param (
        [Parameter(Mandatory=$true)][string]$TargetDomain,
        [Parameter(Mandatory=$true)][string]$TargetUser
    )
	$DomainDN   = ([ADSI]"LDAP://$TargetDomain/RootDSE").defaultNamingContext
	$SearchRoot = [ADSI]"LDAP://$TargetDomain/$DomainDN"

	$Searcher = [adsisearcher]"(samAccountName=$TargetUser)"
	$Searcher.SearchRoot = $SearchRoot


	$Searcher.PropertiesToLoad.AddRange(@("samaccountname", "displayname", "description", "pwdlastset", "accountexpires", "msDS-UserPasswordExpiryTimeComputed"))

	$User = $Searcher.FindOne()

    if ($null -ne $User) {
        $rawPwdLastSet = $User.Properties["pwdlastset"][0]
        $pwdLastSet    = [datetime]::FromFileTime($rawPwdLastSet)

    
        $rawPwdExpires = $User.Properties["msDS-UserPasswordExpiryTimeComputed"][0]
        $pwdExpires    = [datetime]::FromFileTime($rawPwdExpires)

        $rawAccExpires = $User.Properties["accountexpires"][0]
        $acctExpires   = if ($rawAccExpires -eq 9223372036854775807 -or $rawAccExpires -eq 0) { "Never" } else { [datetime]::FromFileTime($rawAccExpires) }


        [PSCustomObject]@{
            UserName        = [string]$User.Properties["samaccountname"][0]
            FullName        = [string]$User.Properties["displayname"][0]
            Comment         = [string]$User.Properties["description"][0]
            PasswordLastSet = $pwdLastSet
            PasswordExpires = $pwdExpires
            AccountExpires  = $acctExpires
        }
    } else {
        Write-Warning "Could not find user '$TargetUser' inside '$TargetDomain' via LDAP path."
    }
}


function Send-TWebhook {
    param (
        [Parameter(Mandatory=$true)][string]$Webhook,
        [Parameter(Mandatory=$false)][string]$Header = 'Place Holder Header',
        [Parameter(Mandatory=$false)][string]$Body = 'Place Holder Body'
    )

    $Payload = [Ordered]@{
    type       = "message"
    attachments = @(
        @{
            contentType = "application/vnd.microsoft.card.adaptive"
            content     = @{
                '$schema' = "http://adaptivecards.io"
                type      = "AdaptiveCard"
                version   = "1.4"
                body      = @(
                    @{
                        type   = "TextBlock"
                        text   = $Header
                        weight = "Bolder"
                        size   = "Medium"
                    },
                    @{
                        type = "TextBlock"
                        text = $Body
                        wrap = $true
                    }
                )
            }
        }
    )
}

$JsonBody = $Payload | ConvertTo-Json -Depth 10

Invoke-RestMethod -Method Post -ContentType "application/json" -Body $JsonBody -Uri $Webhook


}


function Send-SANotification {
    param (
        [Parameter(Mandatory=$true)][String]$TargetUser,
        [Parameter(Mandatory=$true)][String]$TargetDomain,
        [Parameter(Mandatory=$false)][Int]$NotificationThreshold = 10,
        [Parameter(Mandatory=$true)][String]$Webhook
    )

    $user = Get-User -TargetDomain $TargetDomain -TargetUser $TargetUser

    if ($null -ne $user) {
        $ExpireDate = [datetime]$user.PasswordExpires
        $TodaysDate = Get-Date
        $DaysUntilExpire = ($ExpireDate - $TodaysDate).Days


        if ($DaysUntilExpire -le $NotificationThreshold -and $DaysUntilExpire -gt 0) {
            $MessageBody = "Username: $($user.UserName)`nPassword Last Set: $($user.PasswordLastSet)`nPassword Expires: $($user.PasswordExpires)"
            $MessageHeader = "$($user.UserName) Password will expire in $DaysUntilExpire days"

            Send-TWebhook -Webhook $Webhook -Header $MessageHeader -Body $MessageBody
        } elseif ($DaysUntilExpire -le 0) {
            $MessageBody = "Username: $($user.UserName)`nPassword Last Set: $($user.PasswordLastSet)`nPassword Expired: $($user.PasswordExpires)`nPlease Reset Password as soon as possible"
            $MessageHeader = "$($user.UserName) Password Is Expired!"

            Send-TWebhook -Webhook $Webhook -Header $MessageHeader -Body $MessageBody
        }
    } else {
        $MessageBody = "User $TargetUser could not be found in target domain $TargetDomain"
        $MessageHeader = "Could Not Find User $TargetUser"

        Send-TWebhook -Webhook $Webhook -Header $MessageHeader -Body $MessageBody
    }
}





