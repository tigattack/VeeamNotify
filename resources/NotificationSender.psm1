# Relies on functions from NotificationBuilder.psm1

function Send-Payload {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory, ParameterSetName = 'Notification', Position = 0, ValueFromPipeline)]
		$Payload,
		[Parameter(Mandatory, ParameterSetName = 'Ping', Position = 0)]
		[Switch]$Ping,
		[Parameter(Mandatory, ParameterSetName = 'Notification', Position = 1)]
		[Parameter(Mandatory, ParameterSetName = 'Ping', Position = 1, ValueFromPipeline)]
		[String]$Uri,
		[Parameter(ParameterSetName = 'Notification', Position = 2)]
		[String]$ContentType = 'application/json',
		[Parameter(ParameterSetName = 'Notification', Position = 3)]
		[WebRequestMethod]$Method = 'Post',
		[Parameter(ParameterSetName = 'Notification', Position = 4)]
		[Switch]$JSONPayload
	)

	process {
		if ($JSONPayload) {
			$Payload = $Payload | ConvertTo-Json -Depth 11
		}

		$postParams = @{
			Uri         = $Uri
			Body        = $Payload
			Method      = $Method
			ContentType = $ContentType
			ErrorAction = 'Stop'
		}

		try {
			# Post payload
			$request = Invoke-RestMethod @postParams

			# Return request object
			return $request
		}
		catch [System.Net.WebException] {
			Write-LogMessage -Tag 'ERROR' -Message 'Unable to send payload.'
			throw $_
		}
	}
}

function Send-WebhookNotification {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[ValidateSet('Discord', 'Slack', 'Teams')]
		[string]$Service,
		[Parameter(Mandatory)]
		[Hashtable]$Parameters,
		[Parameter(Mandatory)]
		[PSObject]$ServiceConfig
	)

	# Return early if webhook is not configured
	if (-not $ServiceConfig.webhook -or -not $ServiceConfig.webhook.StartsWith('http')) {
		Write-LogMessage -Tag 'DEBUG' -Message "$Service is unconfigured (invalid URL). Skipping $Service notification."
		return $false
	}

	try {
		# Add user information for mention if relevant
		if ($Parameters.Mention) {
			$Parameters.UserId = $ServiceConfig.user_id
			
			# Set username if exists (Teams specific)
			if ($Service -eq 'Teams' -and $ServiceConfig.user_name -and $ServiceConfig.user_name -ne 'Your Name') {
				$Parameters.UserName = $ServiceConfig.user_name
			}
		}

		# Create payload and send notification
		$uri = $ServiceConfig.webhook
		New-Payload -Service $Service -Parameters $Parameters | Send-Payload -Uri $uri -JSONPayload | Out-Null
		Write-LogMessage -Tag 'INFO' -Message "Notification sent to $Service successfully."
		return $true
	}
	catch {
		Write-LogMessage -Tag 'ERROR' -Message "Unable to send $Service notification: $_"
		return $false
	}
}

function Send-TelegramNotification {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[Hashtable]$Parameters,
		[Parameter(Mandatory)]
		[PSObject]$ServiceConfig
	)

	# Return early if bot token or chat ID is not configured
	if ($ServiceConfig.bot_token -eq 'TelegramBotToken' -or $ServiceConfig.chat_id -eq 'TelegramChatID') {
		Write-LogMessage -Tag 'DEBUG' -Message 'Telegram is unconfigured (invalid bot_token or chat_id). Skipping Telegram notification.'
		return $false
	}

	try {
		# Add user information for mention if relevant
		if ($Parameters.Mention) {
			$Parameters.UserId = $ServiceConfig.user_id
			$Parameters.UserName = $ServiceConfig.user_name
		}

		# Create payload and send notification
		$uri = "https://api.telegram.org/bot$($ServiceConfig.bot_token)/sendMessage"
		$notificationText = New-Payload -Service 'Telegram' -Parameters $Parameters
		$payload = @{ 
			chat_id    = "$($ServiceConfig.chat_id)"
			parse_mode = 'MarkdownV2'
			text       = $notificationText 
		}
		Send-Payload -Uri $uri -Payload $payload -ContentType 'application/x-www-form-urlencoded' | Out-Null

		Write-LogMessage -Tag 'INFO' -Message 'Notification sent to Telegram successfully.'
		return $true
	}
	catch {
		Write-LogMessage -Tag 'ERROR' -Message "Unable to send Telegram notification: $_"
		return $false
	}
}

function Send-PingNotification {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[PSObject]$ServiceConfig
	)

	# Return early if webhook is not configured
	if (-not $ServiceConfig.webhook -or -not $ServiceConfig.webhook.StartsWith('http')) {
		Write-LogMessage -Tag 'DEBUG' -Message 'Ping service is unconfigured (invalid URL). Skipping HTTP Ping.'
		return $false
	}

	try {
		# Send the actual ping
		# TODO: support different methods
		Send-Payload -Ping -Uri $ServiceConfig.webhook | Out-Null
		Write-LogMessage -Tag 'INFO' -Message 'HTTP Ping sent successfully.'
		return $true
	}
	catch {
		Write-LogMessage -Tag 'ERROR' -Message "Unable to send HTTP Ping: $_"
		return $false
	}
}
