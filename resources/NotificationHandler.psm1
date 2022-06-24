function New-Payload {
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param (
		[Parameter(Mandatory=$true)]
		[ValidateSet('Discord', 'Slack', 'Teams', 'Telegram')]
		[string]$Service,

		[Parameter(Mandatory=$true)]
		[Hashtable]$Parameters
	)

	switch ($Service) {
		'Discord' {
			New-DiscordPayload @Parameters
		}
		'Slack' {
			New-SlackPayload @Parameters
		}
		'Teams' {
			New-TeamsPayload @Parameters
		}
		'Telegram' {
			New-TelegramPayload @Parameters
		}
		default {
			Write-LogMessage -Tag 'ERROR' -Message "Unknown service: $Service"
		}
	}
}

function New-DiscordPayload {
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param (
		[string]$JobName,
		[string]$JobType,
		[string]$Status,
		[string]$DataSize,
		[string]$TransferSize,
		[string]$ProcessedSize,
		[int]$DedupRatio,
		[int]$CompressRatio,
		[string]$Speed,
		[string]$Bottleneck,
		[string]$Duration,
		[DateTime]$StartTime,
		[DateTime]$EndTime,
		[boolean]$Mention,
		[string]$UserId,
		[string]$ThumbnailUrl,
		[string]$FooterMessage,
		[boolean]$UpdateNotification,
		[string]$LatestVersion
	)

	# Set Discord timestamps
	$timestampStart = "<t:$(([System.DateTimeOffset]$(Get-Date $StartTime)).ToUnixTimeSeconds())>"
	$timestampEnd = "<t:$(([System.DateTimeOffset]$(Get-Date $EndTime)).ToUnixTimeSeconds())>"

	# Switch for the session status to decide the embed colour.
	switch ($Status) {
		None { $colour = '16777215' }
		Warning { $colour = '16776960' }
		Success { $colour = '65280' }
		Failed { $colour = '16711680' }
		default { $colour = '16777215' }
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

	# TODO look furhter into what detail can be pulled out that is tape specefic, eg tapes used etc, requires splitting out payload creation
	if ($JobType.EndsWith('Agent Backup') -or $JobType.EndsWith('Tape Backup')) {
		$fieldArray = @(
			[PSCustomObject]@{
				name   = 'Processed Size'
				value  = $ProcessedSize
				inline	= 'true'
			}
			[PSCustomObject]@{
				name   = 'Transferred Data'
				value  = $TransferSize
				inline	= 'true'
			}
			[PSCustomObject]@{
				name   = 'Processing Rate'
				value  = $Speed
				inline	= 'true'
			}
			[PSCustomObject]@{
				name   = 'Bottleneck'
				value  = $Bottleneck
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Start Time'
				value  = $timestampStart
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'End Time'
				value  = $timestampEnd
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Duration'
				value  = $Duration
				inline = 'true'
			}
		)
	}
	else {
		$fieldArray = @(
			[PSCustomObject]@{
				name   = 'Backup Size'
				value  = $DataSize
				inline = 'true'
			},
			[PSCustomObject]@{
				name   = 'Transferred Data'
				value  = $TransferSize
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Dedup Ratio'
				value  = $DedupRatio
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Compression Ratio'
				value  = $CompressRatio
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Processing Rate'
				value  = $Speed
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Bottleneck'
				value  = $Bottleneck
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Start Time'
				value  = $timestampStart
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'End Time'
				value  = $timestampEnd
				inline = 'true'
			}
			[PSCustomObject]@{
				name   = 'Duration'
				value  = $Duration
				inline = 'true'
			}
		)
	}

	# Build payload object.
	[PSCustomObject]$payload = @{
		embeds = @(
			[PSCustomObject]@{
				title       = $JobName
				description	= "Session result: $Status`nJob type: $JobType"
				color       = $Colour
				thumbnail   = $thumbObject
				fields      = $fieldArray
				footer      = $footerObject
				timestamp   = $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK'))
			}
		)
	}

	# Mention user if configured to do so.
	if ($mention) {
		$payload += @{
			content = "<@!$($UserId)> Job $($Status.ToLower())!"
		}
	}

	# Add update notice if relevant and configured to do so.
	if ($UpdateNotification) {
		# Add embed to payload.
		$payload.embeds += @(
			@{
				title       = 'Update Available'
				description	= "A new version of VeeamNotify is available!`n[See release **$LatestVersion** on GitHub](https://github.com/tigattack/VeeamNotify/releases/$LatestVersion)."
				color       = 3429867
				footer      = $footerObject
				timestamp   = $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK'))
			}
		)
	}

	# Return payload object.
	return $payload
}

function New-TeamsPayload {
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param (
		[string]$JobName,
		[string]$JobType,
		[string]$Status,
		[string]$DataSize,
		[string]$TransferSize,
		[string]$ProcessedSize,
		[int]$DedupRatio,
		[int]$CompressRatio,
		[string]$Speed,
		[string]$Bottleneck,
		[string]$Duration,
		[DateTime]$StartTime,
		[DateTime]$EndTime,
		[boolean]$Mention,
		[string]$UserId,
		[string]$UserName,
		[string]$ThumbnailUrl,
		[string]$FooterMessage,
		[boolean]$UpdateNotification,
		[string]$LatestVersion
	)

	# Define username
	if (-not $UserName) {
		$UserName = $($UserId.Split('@')[0])
	}

	# Mention user if configured to do so.
	# Must be done at early stage to ensure this section is at the top of the embed object.
	if ($mention) {
		$bodyArray = @(
			@{
				type = 'TextBlock'
				text = "<at>$UserName</at> Job $($Status.ToLower())!"
				wrap = $true
			}
		)
	}
	else {
		$bodyArray = @()
	}

	# Set timestamps
	$timestampStart = $(Get-Date $StartTime -UFormat '%d %B %Y %R').ToString()
	$timestampEnd = $(Get-Date $EndTime -UFormat '%d %B %Y %R').ToString()

	# Add embedded URL to footer message
	$FooterMessage = $FooterMessage.Replace(
		'VeeamNotify',
		'[VeeamNotify](https://github.com/tigattack/VeeamNotify)'
	)

	# Add URL to update notice if relevant and configured to do so.
	if ($UpdateNotification) {
		# Add URL to update notice.
		$FooterMessage += "  `n[See release **$LatestVersion** on GitHub.](https://github.com/tigattack/VeeamNotify/releases/$LatestVersion)"
	}

	# Add header information to body array
	$bodyArray += @(
		@{ type = 'ColumnSet'; columns = @(
				@{ type = 'Column'; width = 'stretch'; items = @(
						@{
							type    = 'TextBlock'
							text    = "**$jobName**"
							wrap    = $true
							spacing = 'None'
						}
						@{
							type     = 'TextBlock'
							text     = [System.Web.HttpUtility]::HtmlEncode((Get-Date -UFormat '%d %B %Y %R').ToString())
							wrap     = $true
							isSubtle = $true
							spacing  = 'None'
						}
						@{ type = 'FactSet'; facts = @(
								@{
									title = 'Session Result'
									value = "$Status"
								}
								@{
									title = 'Job Type'
									value = "$jobType"
								}
							)
							spacing = 'Small'
						}
					)
				}
				@{ type = 'Column'; width = 'auto'; items = @(
						@{
							type   = 'Image'
							url    = "$thumbnailUrl"
							height = '80px'
						}
					)
				}
			)
		}
	)

	# Add job information to body array
	if (-not ($JobType.EndsWith('Agent Backup'))) {
		$bodyArray += @(
			@{ type = 'ColumnSet'; columns = @(
					@{ type = 'Column'; width = 'stretch'; items = @(
							@{
								type  = 'FactSet'
								facts = @(
									@{
										title = 'Backup size'
										value = "$DataSize"
									}
									@{
										title = 'Transferred data'
										value = "$transferSize"
									}
									@{
										title = 'Dedup ratio'
										value = "$DedupRatio"
									}
									@{
										title = 'Compress ratio'
										value = "$CompressRatio"
									}
									@{
										title = 'Processing rate'
										value = "$Speed"
									}
								)
							}
						)
					}
					@{ type = 'Column'; width = 'stretch'; items = @(
							@{ type = 'FactSet'; facts = @(
									@{
										title = 'Bottleneck'
										value = "$Bottleneck"
									}
									@{
										title = 'Start Time'
										value = [System.Web.HttpUtility]::HtmlEncode($timestampStart)
									}
									@{
										title = 'End Time'
										value = [System.Web.HttpUtility]::HtmlEncode($timestampEnd)
									}
									@{
										title = 'Duration'
										value = "$Duration"
									}
								)
							}
						)
					}
				)
			}
		)
	}

	elseif ($JobType.EndsWith('Agent Backup') -or $JobType.EndsWith('Tape Backup')) {
		$bodyArray += @(
			@{ type = 'ColumnSet'; columns = @(
					@{ type = 'Column'; width = 'stretch'; items = @(
							@{
								type  = 'FactSet'
								facts = @(
									@{
										title = 'Processed Size'
										value = "$ProcessedSize"
									}
									@{
										title = 'Transferred Data'
										value = "$transferSize"
									}
									@{
										title = 'Processing rate'
										value = "$Speed"
									}
									@{
										title = 'Bottleneck'
										value = "$Bottleneck"
									}
								)
							}
						)
					}
					@{ type = 'Column'; width = 'stretch'; items = @(
							@{ type = 'FactSet'; facts = @(
									@{
										title = 'Start Time'
										value = [System.Web.HttpUtility]::HtmlEncode($timestampStart)
									}
									@{
										title = 'End Time'
										value = [System.Web.HttpUtility]::HtmlEncode($timestampEnd)
									}
									@{
										title = 'Duration'
										value = "$Duration"
									}
								)
							}
						)
					}
				)
			}
		)
	}

	# Add footer information to the body array
	$bodyArray += @(
		@{ type = 'ColumnSet'; separator = $true ; columns = @(
				@{ type = 'Column'; width = 'auto'; items = @(
						@{
							type   = 'Image'
							url    = 'https://avatars0.githubusercontent.com/u/10629864'
							height = '20px'
						}
					)
				}
				@{ type = 'Column'; width = 'stretch'; items = @(
						@{
							type     = 'TextBlock'
							text     = "$FooterMessage"
							wrap     = $true
							isSubtle = $true
						}
					)
				}
			)
		}
	)

	[PSCustomObject]$payload = @{
		type        = 'message'
		attachments = @(
			@{
				contentType = 'application/vnd.microsoft.card.adaptive'
				contentUrl  = $null
				content     = @{
					'$schema' = 'http://adaptivecards.io/schemas/adaptive-card.json'
					type      = 'AdaptiveCard'
					version   = '1.4'
					body      = $bodyArray
				}
			}
		)
	}

	# Mention user if configured to do so.
	# Must be done at early stage to ensure this section is at the top of the embed object.
	if ($mention) {
		$payload.attachments[0].content += @{
			msteams = @{
				entities = @(
					@{
						type      = 'mention'
						text      = "<at>$UserName</at>"
						mentioned = @{
							id   = "$UserId"
							name = "$UserName"
						}
					}
				)
			}
		}
	}

	return $payload
}

function New-SlackPayload {
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param (
		[string]$JobName,
		[string]$JobType,
		[string]$Status,
		[string]$DataSize,
		[string]$TransferSize,
		[string]$ProcessedSize,
		[int]$DedupRatio,
		[int]$CompressRatio,
		[string]$Speed,
		[string]$Bottleneck,
		[string]$Duration,
		[DateTime]$StartTime,
		[DateTime]$EndTime,
		[boolean]$Mention,
		[string]$UserId,
		[string]$ThumbnailUrl,
		[string]$FooterMessage,
		[boolean]$UpdateNotification,
		[string]$LatestVersion
	)

	# Mention user if configured to do so.
	# Must be done at early stage to ensure this section is at the top of the embed object.
	if ($mention) {
		$payload = @{
			blocks = @(
				@{
					type = 'section'
					text = @{
						type = 'mrkdwn'
						text = "<@$UserId> Job $($Status.ToLower())!"
					}
				}
			)
		}
	}
	else {
		$payload = @{
			blocks = @()
		}
	}

	# Set timestamps
	$timestampStart = $(Get-Date $StartTime -UFormat '%d %B %Y %R').ToString()
	$timestampEnd = $(Get-Date $EndTime -UFormat '%d %B %Y %R').ToString()

	# Build blocks object.
	if (-not ($JobType.EndsWith('Agent Backup'))) {
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
				text = "*Start Time*`n$timestampStart"
			}
			[PSCustomObject]@{
				type = 'mrkdwn'
				text = "*End Time*`n$timestampEnd"
			}
			[PSCustomObject]@{
				type = 'mrkdwn'
				text = "*Duration*`n$Duration"
			}
		)
	}

	elseif ($JobType.EndsWith('Agent Backup') -or $JobType.EndsWith('Tape Backup')) {
		$fieldArray += @(
			[PSCustomObject]@{
				type = 'mrkdwn'
				text = "*Processed Size*`n$ProcessedSize"
			}
			[PSCustomObject]@{
				type = 'mrkdwn'
				text = "*Transferred Data*`n$TransferSize"
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
				text = "*Start Time*`n$timestampStart"
			}
			[PSCustomObject]@{
				type = 'mrkdwn'
				text = "*End Time*`n$timestampEnd"
			}
			[PSCustomObject]@{
				type = 'mrkdwn'
				text = "*Duration*`n$Duration"
			}
		)
	}

	# Build payload object.
	[PSCustomObject]$payload.blocks += @(
		@{
			type      = 'section'
			text      = @{
				type = 'mrkdwn'
				text = "*$JobName*`n`nSession result: $Status`nJob type: $JobType"
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
	)

	# Add footer to payload object.
	$payload.blocks += @(
		@{
			type = 'divider'
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

	# Add update notice if relevant and configured to do so.
	if ($UpdateNotification) {
		# Add block to payload.
		$payload.blocks += @(
			@{
				type      = 'section'
				text      = @{
					type = 'mrkdwn'
					text = "A new version of VeeamNotify is available! See release *$LatestVersion* on GitHub."
				}
				accessory = @{
					type      = 'button'
					text      = @{
						type = 'plain_text'
						text = 'Open on GitHub'
					}
					value     = 'open_github'
					url       = "https://github.com/tigattack/VeeamNotify/releases/$LatestVersion"
					action_id = 'button-action'
				}
			}
		)
	}

	# Remove obsolete extended-type system properties added by Add-Member ($payload.blocks +=)
	# https://stackoverflow.com/a/57599481
	Remove-TypeData System.Array -ErrorAction Ignore

	return $payload
}

function New-TelegramPayload {
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[string]$JobName,
		[string]$JobType,
		[string]$Status,
		[string]$DataSize,
		[string]$TransferSize,
		[string]$ProcessedSize,
		[int]$DedupRatio,
		[int]$CompressRatio,
		[string]$Speed,
		[string]$Bottleneck,
		[string]$Duration,
		[DateTime]$StartTime,
		[DateTime]$EndTime,
		[boolean]$Mention,
		[string]$UserId,
		[string]$ThumbnailUrl,
		[string]$FooterMessage,
		[boolean]$UpdateNotification,
		[string]$LatestVersion
	)

	# Mention user if configured to do so.
	# Must be done at early stage to ensure this section is at the top of the embed object.
	if ($mention) {
		$message =  "[$UserName](tg://user?id=$UserId) Job $($Status.ToLower())!`n"
	}
	else {
		$message = ''
	}

	# Build payload object.
	$message += "*$JobName*`n`n*Session result:* $Status`n*Job type:* $JobType`n`n"

	# Set timestamps
	$timestampStart = $(Get-Date $StartTime -UFormat '%d %B %Y %R').ToString()
	$timestampEnd = $(Get-Date $EndTime -UFormat '%d %B %Y %R').ToString()

	# Build blocks object.
	if (-not ($JobType.EndsWith('Agent Backup'))) {
		$message += @"
*Backup Size:* $DataSize
*Transferred Data:* $TransferSize
*Dedup Ratio:* $DedupRatio
*Compression Ratio:* $CompressRatio
*Processing Rate:* $Speed
*Bottleneck:* $Bottleneck
*Start Time:* $timestampStart
*End Time:* $timestampEnd
*Duration:* $Duration
"@
	}

	elseif ($JobType.EndsWith('Agent Backup') -or $JobType.EndsWith('Tape Backup')) {
		$message += @"
*Processed Size:* $ProcessedSize
*Transferred Data:* $TransferSize
*Processing Rate:* $Speed
*Bottleneck:* $Bottleneck
*Start Time:* $timestampStart
*End Time:* $timestampEnd
*Duration:* $Duration
"@
	}

	# Add footer to payload object.
	$message += "`n`n$FooterMessage"

	# Add update notice if relevant and configured to do so.
	if ($UpdateNotification) {
		# Add block to payload.
		$message += "`nA new version of VeeamNotify is available! See release [*$LatestVersion* on GitHub](https://github.com/tigattack/VeeamNotify/releases/$LatestVersion)."
	}

	# https://core.telegram.org/bots/api#markdownv2-style
	$escapes = '_', '[', ']', '(', ')', '~', '>', '#', '+', '-', '=', '|', '{', '}', '.', '!'

	foreach ($char in $escapes) {
		$message = $message.Replace("$char", "\$char")
	}

	return $message
}

function Send-Payload {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory,ParameterSetName='Notification', Position=0, ValueFromPipeline)]
		$Payload,
		[Parameter(Mandatory,ParameterSetName='Ping', Position=0)]
		[Switch]$Ping,
		[Parameter(Mandatory,ParameterSetName='Notification', Position=1)]
		[Parameter(Mandatory,ParameterSetName='Ping', Position=1, ValueFromPipeline)]
		[String]$Uri,
		$JSONPayload = $false
	)

	process {
		# Build post parameters
		if ($JSONPayload) {
			$postParams = @{
				Uri         = $Uri
				Body        = ($Payload | ConvertTo-Json -Depth 11)
				Method      = 'Post'
				ContentType = 'application/json'
				ErrorAction = 'Stop'
			}
		}
		else {
			$postParams = @{
				Body        = $Payload
				Method      = 'Post'
				ContentType = 'application/x-www-form-urlencoded'
				ErrorAction = 'Stop'
			}
		}

		try {
			# Post payload
			$request = Invoke-RestMethod @postParams

			# Return request object
			return $request
		}
		catch [System.Net.WebException] {
			Write-LogMessage -Tag 'ERROR' -Message 'Unable to send Payload. Check your Payload or network connection.'
			throw
		}
	}
}
