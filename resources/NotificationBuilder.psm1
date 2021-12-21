function New-DiscordPayload {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'None'
	)]
	[OutputType([System.Collections.Hashtable])]
	param (
		$JobName
	)

	if ($PSCmdlet.ShouldProcess('Output stream', 'Create payload')) {
		# Build footer object.
		$footerObject = [PSCustomObject]@{
			text     = $FooterMessage
			icon_url = 'https://avatars0.githubusercontent.com/u/10629864'
		}

		## Build thumbnail object.
		If ($Thumbnail) {
			$thumbObject = [PSCustomObject]@{
				url = $Thumbnail
			}
		}
		Else {
			$thumbObject = [PSCustomObject]@{
				url = 'https://raw.githubusercontent.com/tigattack/VeeamDiscordNotifications/master/asset/thumb01.png'
			}
		}

		# Build field object.
		$fieldArray = @(
			[PSCustomObject]@{
				name   = 'Backup Size'
				value  = [String]$JobSizeRound
				inline = 'true'
			},
			[PSCustomObject]@{
				name   = 'Transferred Data'
				value  = [String]$TransferSizeRound
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Dedup Ratio'
				value  = [String]$Session.BackupStats.DedupRatio
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Compression Ratio'
				value  = [String]$Session.BackupStats.CompressRatio
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Processing Rate'
				value  = $SpeedRound
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Bottleneck'
				value  = [String]$Bottleneck
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Job Duration'
				value  = $DurationFormatted
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Time Started'
				value  = "<t:$(([System.DateTimeOffset]$(Get-Date $JobStartTime)).ToUnixTimeSeconds())>"
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Time Ended'
				value  = "<t:$(([System.DateTimeOffset]$(Get-Date $JobEndTime)).ToUnixTimeSeconds())>"
				inline = 'true'
			}
		)

		# If agent backup, add notice to fieldArray.
		If ($JobType -eq 'EpAgentBackup') {
			$fieldArray += @(
				[PSCustomObject]@{
					name   = 'Notice'
					value  = "Further details are missing due to limitations in Veeam's PowerShell module."
					inline = 'false'
				}
			)
		}

		# Build payload object.
		[PSCustomObject]$payload = @{
			embeds = @(
				[PSCustomObject]@{
					title       = $JobName
					description	= "Session result: $status`nJob type: $JobTypeNice"
					color       = $Colour
					thumbnail   = $thumbObject
					fields      = $fieldArray
					footer      = $footerObject
					timestamp   = $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK'))
				}
			)
		}

		# Mention user on job failure if configured to do so.
		If ($mention) {
			$payload += @{
				content = "<@!$($UserID)> Job $status!"
			}
		}

		# Return payload object.
		return $payload
	}
}

function New-TeamsPayload {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'None'
	)]
	[OutputType([System.Collections.Hashtable])]
	param (
		$JobName
	)

	if ($PSCmdlet.ShouldProcess('Output stream', 'Create payload')) {
		$TeamsJSON = @{
			'@type'         = 'MessageCard'
			'@context'      = 'http=//schema.org/extensions'
			'correlationId' = $Session.Id
			'themeColor'    = $Color
			'title'         = $Title
			'summary'       = $Title
			'sections'      = @(
				@{
					'facts' = @(
						@{ 'name' = 'Duration'; 'value' = $Duration }
						@{ 'name' = 'Processing rate';	'value' = $Rate }
						@{ 'name' = 'Bottleneck'; 'value' = $Bottleneck }
						@{ 'name' = 'Data Processed';	'value' = $Processed }
						@{ 'name' = 'Data Read'; 'value' = $Read }
						@{ 'name' = 'Data Transferred';	'value' = $Transferred }
						@{ 'name' = 'Success'; 'value' = $SuccessFormat -f $SuccessCount, $SuccessIcon }
						@{ 'name' = 'Warning'; 'value' = $WarningFormat -f $WarningCount, $WarningIcon }
						@{ 'name' = 'Error'; 'value' = $FailureFormat -f $FailureCount, $FailureIcon }
					)
				}
			)
		}

		[PSCustomObject]$payload = @{
			Summary    = 'Veeam B&R Report - ' + ($JobName)
			themeColor = $Colour
			sections   = @(
				@{
					title            = '**Veeam Backup & Replication**'
					activityImage    = $StatusImg
					activityTitle    = $JobName
					activitySubtitle = (Get-Date -Format U)
					facts            = @(
						@{
							name  = 'Job status:'
							value = [String]$Status
						},
						@{
							name  = 'Backup size:'
							value = $JobSizeRound
						},
						@{
							name  = 'Transferred data:'
							value = $TransfSizeRound
						},
						@{
							name  = 'Dedupe ratio:'
							value = $session.BackupStats.DedupRatio
						},
						@{
							name  = 'Compress ratio:'
							value =	$session.BackupStats.CompressRatio
						},
						@{
							name  = 'Duration:'
							value = $Duration
						}
					)
				}
			)
		}
	}

	return $TeamsJSON
}

function New-SlackPayload {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'None'
	)]
	[OutputType([System.Collections.Hashtable])]
	param (
		$JobName
	)

	if ($PSCmdlet.ShouldProcess('Output stream', 'Create payload')) {
		# Switch on the session status
		switch ($Status) {
			None { $emoji = ':thought _ balloon: ' }
			Warning { $emoji = ':warning: ' }
			Success { $emoji = ':white_check_mark:  ' }
			Failed { $emoji = ':x: ' }
			Default { $emoji = '' }
		}

		# Build the details string
		$details = 'Backup Size - ' + [String]$JobSizeRound + ' / Transferred Data - ' + [String]$TransfSizeRound + ' / Dedup Ratio - ' + [String]$session.BackupStats.DedupRatio + ' / Compress Ratio - ' + [String]$session.BackupStats.CompressRatio + ' / Duration - ' + $Duration

		# Build the payload
		$slackJSON = @{}
		$slackJSON.channel = $config.channel
		$slackJSON.username = $config.service_name
		$slackJSON.icon_url = $config.icon_url
		$slackJSON.text = $emoji + '**Job:** ' + $JobName + "`n" + $emoji + '**Status:** ' + $Status + "`n" + $emoji + '**Details:** ' + $details
	}

	return $SlackJSON
}
