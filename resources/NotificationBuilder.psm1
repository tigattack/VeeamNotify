function New-DiscordPayload {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'None'
	)]
	[OutputType([System.Collections.Hashtable])]
	param (
		[string]$JobName,
		[string]$JobType,
		[string]$Status,
		[string]$DataSize,
		[string]$TransferSize,
		[int]$DedupRatio,
		[int]$CompressRatio,
		[string]$Speed,
		[string]$Bottleneck,
		[string]$Duration,
		[DateTime]$StartTime,
		[DateTime]$EndTime,
		[switch]$Mention,
		[string]$UserId,
		[string]$ThumbnailUrl,
		[string]$FooterMessage
	)

	if ($PSCmdlet.ShouldProcess('Output stream', 'Create payload')) {

		# Set Discord timestamps
		$timestampStart = "<t:$(([System.DateTimeOffset]$(Get-Date $StartTime)).ToUnixTimeSeconds())>"
		$timestampEnd = "<t:$(([System.DateTimeOffset]$(Get-Date $EndTime)).ToUnixTimeSeconds())>"

		# Switch for the session status to decide the embed colour.
		Switch ($status) {
			None { $colour = '16777215' }
			Warning { $colour = '16776960' }
			Success { $colour = '65280' }
			Failed { $colour = '16711680' }
			Default { $colour = '16777215' }
		}

		# Build footer object.
		$footerObject = [PSCustomObject]@{
			text     = $FooterMessage
			icon_url = 'https://avatars0.githubusercontent.com/u/10629864'
		}

		## Build thumbnail object.
		$thumbObject = [PSCustomObject]@{
			url = $ThumbnailUrl
		}

		# Build field object.
		$fieldArray = @(
			[PSCustomObject]@{
				name   = 'Backup Size'
				value  = [String]$DataSize
				inline = 'true'
			},
			[PSCustomObject]@{
				name   = 'Transferred Data'
				value  = [String]$TransferSize
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Dedup Ratio'
				value  = [String]$DedupRatio
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Compression Ratio'
				value  = [String]$CompressRatio
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Processing Rate'
				value  = $Speed
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Bottleneck'
				value  = [String]$Bottleneck
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Time Started'
				value  = $timestampStart
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Time Ended'
				value  = $timestampEnd
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Job Duration'
				value  = $Duration
				inline = 'true'
			}
		)

		# If agent backup, add notice to fieldArray.
		If ($JobType -eq 'Agent Backup') {
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
					description	= "Session result: $status`nJob type: $JobType"
					color       = $Colour
					thumbnail   = $thumbObject
					fields      = $fieldArray
					footer      = $footerObject
					timestamp   = $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK'))
				}
			)
		}

		# Mention user if configured to do so.
		If ($mention) {
			$payload += @{
				content = "<@!$($UserId)> Job $status!"
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
		[string]$JobName,
		[string]$JobType,
		[string]$Status,
		[string]$DataSize,
		[string]$TransferSize,
		[int]$DedupRatio,
		[int]$CompressRatio,
		[string]$Speed,
		[string]$Bottleneck,
		[string]$Duration,
		[DateTime]$StartTime,
		[DateTime]$EndTime,
		[switch]$Mention,
		[string]$UserId,
		[string]$ThumbnailUrl,
		[string]$FooterMessage
	)

	if ($PSCmdlet.ShouldProcess('Output stream', 'Create payload')) {

		# Set timestamps
		$timestampStart = $(Get-Date $StartTime -UFormat '%d %B %Y %R').ToString()
		$timestampEnd = $(Get-Date $EndTime -UFormat '%d %B %Y %R').ToString()

		# Add embedded URL to footer message
		$FooterMessage = $FooterMessage.Replace(
			'VeeamDiscordNotifications',
			'[VeeamDiscordNotifications](https://github.com/tigattack/VeeamDiscordNotifications)'
		)

		# Switch for the session status to decide the embed colour.
		Switch ($status) {
			None { $colour = '16777215' }
			Warning { $colour = '16776960' }
			Success { $colour = '65280' }
			Failed { $colour = '16711680' }
			Default { $colour = '16777215' }
		}

		# Build facts object.
		$factsArray = @(
			@{
				name       = 'Session result'
				value      = $Status
				startGroup = $true
			}
			@{
				name  = 'Job type'
				value = $JobType
			}
			@{
				name       = 'Backup size'
				value      = $DataSize
				startGroup = $true
			}
			@{
				name  = 'Transferred data'
				value = $TransferSize
			}
			@{
				name  = 'Dedup ratio'
				value = $DedupRatio.ToString()
			}
			@{
				name  = 'Compress ratio'
				value =	$CompressRatio.ToString()
			}
			@{
				name  = 'Processing rate'
				value = $Speed
			}
			@{
				name  = 'Bottleneck'
				value = $Bottleneck
			}
			@{
				name  = 'Time started'
				value = $timestampStart
			}
			@{
				name  = 'Time ended'
				value = $timestampEnd
			}
			@{
				name  = 'Job Duration'
				value = $Duration
			}
		)

		[PSCustomObject]$payload = @{
			'@type'    = 'MessageCard'
			'@context' = 'https: //schema.org/extensions'
			Summary    = "**$JobName**"
			themeColor = $colour
			sections   = @(
				@{
					activityImage    = $ThumbnailUrl
					activityTitle    = "**$JobName**"
					activitySubtitle = (Get-Date -Format U)
					facts            = $factsArray
				},
				@{
					text = $FooterMessage
				}
			)
		}
	}

	return $payload
}

function New-SlackPayload {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'None'
	)]
	[OutputType([System.Collections.Hashtable])]
	param (
		[string]$JobName,
		[string]$JobType,
		[string]$Status,
		[string]$DataSize,
		[string]$TransferSize,
		[int]$DedupRatio,
		[int]$CompressRatio,
		[string]$Speed,
		[string]$Bottleneck,
		[string]$Duration,
		[DateTime]$StartTime,
		[DateTime]$EndTime,
		[switch]$Mention,
		[string]$UserId,
		[string]$ThumbnailUrl,
		[string]$FooterMessage
	)

	if ($PSCmdlet.ShouldProcess('Output stream', 'Create payload')) {


		# Set timestamps
		$timestampStart = $(Get-Date $StartTime -UFormat '%d %B %Y %R').ToString()
		$timestampEnd = $(Get-Date $EndTime -UFormat '%d %B %Y %R').ToString()

		# Build blocks object.
		$fieldArray = @(
			[PSCustomObject]@{
				type = 'mrkdwn'
				text = "*Backup Size*`n$DataSize"
			},
			[PSCustomObject]@{
				type = 'mrkdwn'
				text = "*Transferred Data*`n$TransferSize"
			}
			[PSCustomObject]@{
				type = 'mrkdwn'
				text = "*Dedup Ratio*`n$DedupRatio"
			}
			[PSCustomObject]@{
				type = 'mrkdwn'
				text = "*Compression Ratio*`n$CompressRatio"
			}
			[PSCustomObject]@{
				type = 'mrkdwn'
				text = "*Processing Rate*`n$Speed"
			}
			[PSCustomObject]@{
				type = 'mrkdwn'
				text = "*Bottleneck*`n$Bottleneck"
			}
			[PSCustomObject]@{
				type = 'mrkdwn'
				text = "*Time Started*`n$timestampStart"
			}
			[PSCustomObject]@{
				type = 'mrkdwn'
				text = "*Time Ended*`n$timestampEnd"
			}
			[PSCustomObject]@{
				type = 'mrkdwn'
				text = "*Job Duration*`n$Duration"
			}
		)

		# If agent backup, add notice to fieldArray.
		If ($JobType -eq 'Agent Backup') {
			$fieldArray += @(
				[PSCustomObject]@{
					type = 'mrkdwn'
					text = "Notice`nFurther details are missing due to limitations in Veeam's PowerShell module."
				}
			)
		}

		# Build payload object.
		[PSCustomObject]$payload = @{
			blocks = @(
				@{
					type      = 'section'
					text      = @{
						type = 'mrkdwn'
						text = "*$JobName*`nSession result: $Status`nJob type: $JobType"
					}
					accessory = @{
						type      = 'image'
						image_url = "$ThumbnailUrl"
						alt_text  = 'Veeam Backup & Replication logo'
					}
				}
				@{
					type   = 'section'
					fields = $fieldArray
				}
				@{
					type     = 'context'
					elements = @(
						@{
							type      = 'image'
							image_url = 'https://avatars0.githubusercontent.com/u/10629864'
							alt_text  = "tigattack's avatar"
						}
						@{
							type = 'plain_text'
							text = $FooterMessage
						}
					)
				}
			)
		}

		return $payload
	}
}
