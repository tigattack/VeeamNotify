<#
	.SYNOPSIS
	Installer script for VeeamNotify.
	.DESCRIPTION
	Installs VeeamNotify from one of the following:
		1) Latest release;
		2) Latest prerelease;
		3) Specific version;
		4) A named branch.
	This script can also optionally launch a deployment script to apply the VeeamNotify configuration to all or selected Veeam jobs. You will be prompted for this after installation.
	.PARAMETER Latest
	Choose between "Release" or "Prerelease" to install the latest release or prerelease.
	.PARAMETER Version
	Specify a version to install (e.g. 'v1.0').
	.PARAMETER Branch
	Specify a branch name to install from. Useful for testing.
	.PARAMETER NonInteractive
	Switch for noninteractive installation. No prompts to choose versions or configurations will appear when specified, and one of the above parameters must also be specified.
	.PARAMETER InstallParentPath
	Path to Telegraf destination directory. Defaults to 'C:\VeeamScripts'.
	.INPUTS
	None.
	.OUTPUTS
	None.
	.EXAMPLE
	PS> Installer.ps1
	.EXAMPLE
	PS> Installer.ps1 -Latest release
	.EXAMPLE
	PS> Installer.ps1 -Version 'v1.0' -NonInteractive
	.NOTES
	Authors: tigattack, philenst
	.LINK
	https://github.com/tigattack/VeeamNotify/wiki
#>

#Requires -RunAsAdministrator

[CmdletBinding(DefaultParameterSetName='None')]
param(
	[Parameter(ParameterSetName = 'Version', Position = 0, Mandatory = $true)]
	# Built-in parameter validation disabled - See https://github.com/tigattack/VeeamNotify/issues/50
	# [ValidatePattern('^v(\d+\.)?(\d+\.)?(\*|\d+)$')]
	[String]$Version,

	[Parameter(ParameterSetName = 'Release', Position = 0, Mandatory = $true)]
	# Built-in parameter validation disabled - See https://github.com/tigattack/VeeamNotify/issues/50
	# [ValidateSet('Release', 'Prerelease')]
	[String]$Latest,

	[Parameter(ParameterSetName = 'Branch', Position = 0, Mandatory = $true)]
	[String]$Branch,

	[Parameter(ParameterSetName = 'Version', Position = 1)]
	[Parameter(ParameterSetName = 'Release', Position = 1)]
	[Parameter(ParameterSetName = 'Branch', Position = 1)]
	[String]$InstallParentPath = 'C:\VeeamScripts',

	[Parameter(ParameterSetName = 'Version', Position = 2)]
	[Parameter(ParameterSetName = 'Release', Position = 2)]
	[Parameter(ParameterSetName = 'Branch', Position = 2)]
	[Switch]$NonInteractive
)

# Prepare variables
$project = 'VeeamNotify'
$ErrorActionPreference = 'Stop'

Write-Output @'
#######################################
#                                     #
#        VeeamNotify Installer        #
#                                     #
#######################################
'@

# Check if this project is already installed and if so, exit
if (Test-Path "$InstallParentPath\$project") {
	$installedVersion = (Get-Content -Raw "$InstallParentPath\$project\resources\version.txt").Trim()
	Write-Output "`n$project ($installedVersion) is already installed. This script cannot update an existing installation."
	Write-Output "Please manually update or delete/rename the existing installation and retry.`n`n"
	exit
}

If ($Version -and $Version -notmatch '^v(\d+\.)?(\d+\.)?(\*|\d+)$') {
	Write-Warning "Version parameter value '$Version' does not match the version naming structure."
	exit 1
}
If ($Latest -and $Latest -notin 'Release', 'Prerelease') {
	Write-Warning "Latest parameter value must be one of 'Release' or 'Prelease'."
	exit 1
}

# Get releases and branches from GitHub
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
	$releases = Invoke-RestMethod -Uri "https://api.github.com/repos/tigattack/$project/releases" -Method Get
	$branches = (Invoke-RestMethod -Uri "https://api.github.com/repos/tigattack/$project/branches" -Method Get).name
}
catch {
	$versionStatusCode = $_.Exception.Response.StatusCode.value__
	Write-Warning "Failed to query GitHub for $project releases."
	throw "HTTP status code: $versionStatusCode"
}

# Parse latest release and latest prerelease
foreach ($i in $releases) {
	if ($i.prerelease) {
		$latestPrerelease = $i.tag_name
		break
	}
}
foreach ($i in $releases) {
	if (-not $i.prerelease) {
		$latestStable = $i.tag_name
		break
	}
}


# Query download type if not specified
If (-not $Version -and
	-not $Latest -and
	-not $Branch -and
	-not $NonInteractive) {

	# Query download type / release stream
	If ($releases) {
		[System.Management.Automation.Host.ChoiceDescription[]]$downloadQuery_opts = @()
		$downloadQuery_opts += New-Object System.Management.Automation.Host.ChoiceDescription '&Release', "Download the latest release or prerelease. You will be prompted if there's a choice between the two."
		$downloadQuery_opts += New-Object System.Management.Automation.Host.ChoiceDescription '&Version', 'Download a specific version.'
		$downloadQuery_opts += New-Object System.Management.Automation.Host.ChoiceDescription '&Branch', 'Download a branch.'
		$downloadQuery_result = $host.UI.PromptForChoice(
			'Download type',
			"Please select how you would like to download $project.",
			$downloadQuery_opts,
			0
		)
	}
	Else {
		$branchQuery_yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Install from a branch.'
		$branchQuery_no = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Cancel installation.'
		$host.UI.PromptForChoice(
			'Would you like to install from a branch?',
			"There are currently no releases or prereleases available for $project.",
			@($branchQuery_yes, $branchQuery_no),
			0
		) | ForEach-Object {
			If ($_ -eq 0) { $downloadQuery_result = 2 }
			Else { exit }
		}
	}

	# Set download type
	Switch ($downloadQuery_result) {
		0 {
			If ($latestStable -and $latestPrerelease) {
				# Query release stream
				$releasePrompt = $true
				# Query release stream
				$versionQuery_stable = New-Object System.Management.Automation.Host.ChoiceDescription 'Latest &stable', "Latest stable: $latestStable."
				$versionQuery_prerelease = New-Object System.Management.Automation.Host.ChoiceDescription 'Latest &prerelease', "Latest prelease: $latestPrerelease."
				$versionQuery_result = $host.UI.PromptForChoice(
					'Release Selection',
					"Which release type would you like to install?`nEnter '?' to see versions.",
					@(
						$versionQuery_stable,
						$versionQuery_prerelease),
					0
				)

				Switch ($versionQuery_result) {
					0 {
						$Latest = 'Release'
					}
					1 {
						$Latest = 'Prerelease'
					}
				}
			}
			ElseIf ($latestStable) {
				$Latest = 'Release'
			}
			ElseIf ($latestPrerelease) {
				$prereleaseQuery_yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Install the latest prerelease.'
				$prereleaseQuery_no = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Cancel installation.'
				$host.UI.PromptForChoice(
					'Do you wish to install the latest prerelease?',
					'You chose release, but the only available releases are prereleases.',
					@($prereleaseQuery_yes, $prereleaseQuery_no),
					0
				) | ForEach-Object {
					If ($_ -eq 0) { $Latest = 'Prerelease' }
					Else { exit }
				}
			}
		}
		1 {
			do {
				$Version = ($host.UI.Prompt(
						'Version Selection',
						"Please enter the version you wish to install.`nAvailable versions:`n $(foreach ($tag in $releases.tag_name) {"$tag`n"})",
						'Version'
					)).Version
				If ($releases.tag_name -notcontains $Version) { Write-Output "`nInvalid version, please try again." }
			} until (
				$releases.tag_name -contains $Version
			)
		}
		2 {
			do {
				$Branch = ($host.UI.Prompt(
						'Branch Selection',
						"Please enter the name of the branch you wish to install.`nAvailable branches:`n $(foreach ($branch in $branches) {"$branch`n"})",
						'Branch'
					)).Branch
				If ($branches -notcontains $Branch) { Write-Output "`nInvalid branch name, please try again." }
			} until (
				$branches -contains $Branch
			)
		}
	}
}

# Download branch if specified
If ($Branch) {

	# Throw if branch not found
	If (-not $branches.Contains($Branch)) {

		throw "Branch '$Branch' not found. Will not prompt for branch in non-interactive mode."
	}

	# Set $releaseName to branch name
	$releaseName = $Branch

	# Define download URL
	$downloadUrl = "https://api.github.com/repos/tigattack/$project/zipball/$Branch"
}

# Otherwise work with versions
Else {

	# Define release to use
	If ($Latest) {
		Switch ($Latest) {
			'Release' {
				$releaseName = $latestStable
			}
			'Prerelease' {
				$releaseName = $latestPrerelease
			}
		}
	}
	ElseIf ($Version) {
		$releaseName = $Version
	}

	If (($Latest -or $releasePrompt) -and (-not $releaseName)) {
		Write-Warning 'A release of the specified type could not found.'
		exit
	}

	# Define download URL
	$downloadUrl = Invoke-RestMethod "https://api.github.com/repos/tigattack/$project/releases" | ForEach-Object {
		If ($_.tag_name -eq $releaseName) {
			$_.assets[0].browser_download_url
		}
	}
}

# Sanitise releaseName for OutFile if installing from branch
If ($Branch) {
	$outFile = "$project-$($releaseName -replace '[\W]','-')"
}
Else {
	$outFile = "$project-$releaseName"
}

# Download project from GitHub
$DownloadParams = @{
	Uri     = $downloadUrl
	OutFile = "$env:TEMP\$outFile.zip"
}

Try {
	Write-Output "`nDownloading $project $releaseName from GitHub..."
	Invoke-WebRequest @DownloadParams
}
catch {
	$downloadStatusCode = $_.Exception.Response.StatusCode.value__
	Write-Warning "Failed to download $project $releaseName."
	throw "HTTP status code: $downloadStatusCode"
}

# Unblock downloaded ZIP
try {
	Write-Output 'Unblocking ZIP...'
	Unblock-File -Path "$env:TEMP\$outFile.zip"
}
catch {
	Write-Warning 'Failed to unblock downloaded files. You will need to run the following commands manually once installation is complete:'
	Write-Output "Get-ChildItem -Path $InstallParentPath -Filter *.ps* -Recurse | Unblock-File"
}

# Extract release to destination path
Write-Output "Extracting files to '$InstallParentPath'..."
Expand-Archive -Path "$env:TEMP\$outFile.zip" -DestinationPath "$InstallParentPath" -Force

# Rename destination and tidy up
Write-Output 'Renaming directory and tidying up...'
If (Test-Path "$InstallParentPath\$outFile") {
	Rename-Item -Path "$InstallParentPath\$outFile" -NewName "$project"
}
Else {
	# Necessary to handle branch downloads, which come as a ZIP containing a directory named similarly to "tigattack-VeeamNotify-2100906".
	# Look for a directory less than 5 minutes old which matches the example name stated above.
	(Get-ChildItem $InstallParentPath | Where-Object {
		$_.LastWriteTime -gt (Get-Date).AddMinutes(-5) -and
		$_.Name -match "tigattack-$project-.*" -and
		$_.PsIsContainer
	})[0] | Rename-Item -NewName "$project"
}

Remove-Item -Path "$env:TEMP\$outFile.zip"

If (-not $NonInteractive) {
	Write-Output "`nBeginning configuration..."

	# Join config path
	$configPath = Join-Path -Path $InstallParentPath -ChildPath $project | Join-Path -ChildPath 'config\conf.json'

	# Get config
	$config = Get-Content "$configPath" -Raw | ConvertFrom-Json

	# Prompt user with config options
	$servicePrompt_discord = New-Object System.Management.Automation.Host.ChoiceDescription '&Discord', 'Send notifications to Discord.'
	$servicePrompt_slack = New-Object System.Management.Automation.Host.ChoiceDescription '&Slack', 'Send notifications to Slack.'
	$servicePrompt_teams = New-Object System.Management.Automation.Host.ChoiceDescription '&Teams', 'Send notifications to Teams.'
	$servicePrompt_result = $host.UI.PromptForChoice(
		'Notification Service',
		'Which service do you wish to send notifications to?',
		@(
			$servicePrompt_discord,
			$servicePrompt_slack,
			$servicePrompt_teams
		),
		-1
	)

	$webhookPrompt = "`nPlease enter your webhook URL"
	Switch ($servicePrompt_result) {
		0 {
			$config.services.discord.webhook = Read-Host -Prompt $webhookPrompt
		}
		1 {
			$config.services.slack.webhook = Read-Host -Prompt $webhookPrompt
		}
		2 {
			$config.services.teams.webhook = Read-Host -Prompt $webhookPrompt
		}
	}

	$mentionPreference_no = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Do not mention me.'
	$mentionPreference_warn = New-Object System.Management.Automation.Host.ChoiceDescription '&Warning', 'Mention me when a session finishes in a warning state.'
	$mentionPreference_fail = New-Object System.Management.Automation.Host.ChoiceDescription '&Failure', 'Mention me when a session finishes in a failed state.'
	$mentionPreference_warnfail = New-Object System.Management.Automation.Host.ChoiceDescription '&Both', 'Notify me when a session finishes in either a warning or a failed state.'
	$mentionPreference_result = $host.UI.PromptForChoice(
		'Mention Preference',
		'Do you wish to be mentioned/tagged when a session finishes in one of the following states?',
		@(
			$mentionPreference_no,
			$mentionPreference_warn,
			$mentionPreference_fail,
			$mentionPreference_warnfail
		),
		2
	)

	If ($mentionPreference_result -ne 0) {
		Switch ($servicePrompt_result) {
			0 {
				$config.services.discord.user_id = Read-Host -Prompt "`nPlease enter your Discord user ID"
			}
			1 {
				$config.services.slack.user_id = Read-Host -Prompt "`nPlease enter your Slack member ID"
			}
			2 {
				$config.services.teams.user_id = Read-Host -Prompt "`nPlease enter your Teams email address"
				Write-Output "`nTeams also requires a name to be specified for mentions.`nIf you do not specify anything, your username (from your email address) will be used."
				$config.services.teams.user_name = Read-Host -Prompt 'Please enter your name on Teams (e.g. John Smith)'
			}
		}
	}

	# Set config values
	Switch ($mentionPreference_result) {
		0 {
			$config.mentions.on_failure = $false
			$config.mentions.on_warning = $false
		}
		1 {
			$config.mentions.on_failure = $false
			$config.mentions.on_warning = $true
		}
		2 {
			$config.mentions.on_failure = $true
			$config.mentions.on_warning = $false
		}
		3 {
			$config.mentions.on_failure = $true
			$config.mentions.on_warning = $true
		}
	}

	# Write config
	Try {
		Write-Output "`nSetting configuration..."
		ConvertTo-Json $config | Set-Content "$configPath"
		Write-Output "`nConfiguration set successfully. Configuration can be found in `"$configPath`"."
	}
	catch {
		Write-Warning "Failed to write configuration file at `"$configPath`". Please open the file and complete configuration manually."
	}

	# Query for configuration deployment script.
	$configPrompt_yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Execute configuration deployment tool.'
	$configPrompt_no = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Skip configuration deployment tool.'
	$host.UI.PromptForChoice(
		'Configuration Deployment Tool',
		"Would you like to to run the VeeamNotify configuration deployment tool?`nNone of your job configurations will be modified without confirmation.",
		@(
			$configPrompt_yes,
			$configPrompt_no
		),
		0
	) | ForEach-Object {
		If ($_ -eq 0) {
			Write-Output "`nRunning configuration deployment script...`n"
			& "$InstallParentPath\$project\resources\DeployVeeamConfiguration.ps1" -InstallParentPath $InstallParentPath
		}
	}

}
Else {
	Write-Output "`nWill not prompt for VeeamNotify configuration, or to run Veeam configuration deployment script in non-interactive mode.`n"
	Write-Output "`nConfiguration can be found in `"$configPath`"."
}

Write-Output "`nInstallation complete!`n"
