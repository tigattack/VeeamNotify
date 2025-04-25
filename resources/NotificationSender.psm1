# Relies on functions from NotificationBuilder.psm1

class NotificationResult {
	[ValidateNotNullOrEmpty()][bool]$Success
	[string]$Message
	[hashtable]$Detail
}

function Send-Payload {
	[CmdletBinding()]
	[OutputType([NotificationResult])]
	param (
		[Parameter(Mandatory, ParameterSetName = 'Notification', Position = 0, ValueFromPipeline)]
		[PSCustomObject]$Payload,
		[Parameter(Mandatory, ParameterSetName = 'Ping', Position = 0)]
		[Switch]$Ping,
		[Parameter(Mandatory, ParameterSetName = 'Notification', Position = 1)]
		[Parameter(Mandatory, ParameterSetName = 'Ping', Position = 1, ValueFromPipeline)]
		[String]$Uri,
		[Parameter(ParameterSetName = 'Notification', Position = 2)]
		[String]$ContentType = 'application/json',
		[Parameter(ParameterSetName = 'Notification', Position = 3)]
		[String]$Method = 'Post',
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
			return [NotificationResult]@{
				Success = $true
				Message = $request
			}
		}
		catch {
			return [NotificationResult]@{
				foo = "bar"
				Success = $false
				Message = 'Unable to send payload'
				Detail  = @{
					StatusCode        = $_.Exception.Response.StatusCode.value__
					StatusDescription = $_.Exception.Response.StatusDescription
					Message           = $_.ErrorDetails.Message
				}
			}
		}
	}
}

function Send-WebhookNotification {
	[CmdletBinding()]
	[OutputType([NotificationResult])]
	param (
		[Parameter(Mandatory)]
		[ValidateSet('Discord', 'Slack', 'Teams')]
		[string]$Service,
		[Parameter(Mandatory)]
		[Hashtable]$Parameters,
		[Parameter(Mandatory)]
		[PSCustomObject]$ServiceConfig
	)

	# Return early if webhook is not configured or appears incorrect
	if (-not $ServiceConfig.webhook -or -not $ServiceConfig.webhook.StartsWith('http')) {
		return [NotificationResult]@{
			Success = $false
			Message = "$Service is unconfigured (invalid URL). Skipping $Service notification."
		}
	}

	# Check if user should be mentioned
	try {
		if ($Parameters.Mention) {
			$Parameters.UserId = $ServiceConfig.user_id

			# Set username if exists (Teams specific)
			if ($Service -eq 'Teams' -and $ServiceConfig.user_name -and $ServiceConfig.user_name -ne 'Your Name') {
				$Parameters.UserName = $ServiceConfig.user_name
			}
		}
	}
	catch {
		return [NotificationResult]@{
			Success = $false
			Message = 'Unable to add user information for mention'
			Detail  = $_.Exception.Message
		}
	}

	# Create payload and send notification
	try {
		$response = New-Payload -Service $Service -Parameters $Parameters | Send-Payload -Uri $ServiceConfig.webhook -JSONPayload
		return $response
	}
	catch {
		return [NotificationResult]@{
			Success = $false
			Message = "Unable to send $Service notification"
			Detail  = $_.Exception.Message
		}
	}
}

function Send-TelegramNotification {
	[CmdletBinding()]
	[OutputType([NotificationResult])]
	param (
		[Parameter(Mandatory)]
		[Hashtable]$Parameters,
		[Parameter(Mandatory)]
		[PSCustomObject]$ServiceConfig
	)

	# Return early if bot token or chat ID is not configured or appears incorrect
	if ($ServiceConfig.bot_token -eq 'TelegramBotToken' -or $ServiceConfig.chat_id -eq 'TelegramChatID') {
		return [NotificationResult]@{
			Success = $false
			Message = "Telegram is unconfigured (invalid bot_token or chat_id). Skipping Telegram notification."
		}
	}

	# Check if user should be mentioned
	try {
		if ($Parameters.Mention) {
			$Parameters.UserId = $ServiceConfig.user_id
			$Parameters.UserName = $ServiceConfig.user_name
		}
	}
	catch {
		return [NotificationResult]@{
			Success = $false
			Message = 'Unable to add user information for mention'
			Detail  = $_.Exception.Message
		}
	}

	# Create payload and send notification
	try {
		$uri = "https://api.telegram.org/bot$($ServiceConfig.bot_token)/sendMessage"
		$notificationText = New-Payload -Service 'Telegram' -Parameters $Parameters
		$payload = [PSCustomObject]@{
			chat_id    = "$($ServiceConfig.chat_id)"
			parse_mode = 'MarkdownV2'
			text       = $notificationText
		}
		$response = Send-Payload -Uri $uri -Payload $payload -ContentType 'application/x-www-form-urlencoded'
		return $response
	}
	catch {
		return [NotificationResult]@{
			Success = $false
			Message = "Unable to send Telegram notification"
			Detail  = $_.Exception.Message
		}
	}
}

function Send-PingNotification {
	[CmdletBinding()]
	[OutputType([NotificationResult])]
	param (
		[Parameter(Mandatory)]
		[PSCustomObject]$ServiceConfig
	)

	# Return early if URL is not configured or appears incorrect
	if (-not $ServiceConfig.url -or -not $ServiceConfig.url.StartsWith('http')) {
		return [NotificationResult]@{
			Success = $false
			Message = "Ping service is unconfigured (invalid URL). Skipping HTTP Ping."
		}
	}

	# Create payload and send notification
	try {
		# TODO: support different methods
		$response = Send-Payload -Ping -Uri $ServiceConfig.url
		return $response
	}
	catch {
		return [NotificationResult]@{
			Success = $false
			Message = "Unable to send HTTP Ping"
			Detail  = $_.Exception.Message
		}
	}
}
