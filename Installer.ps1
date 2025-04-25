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

[CmdletBinding(DefaultParameterSetName = 'None')]
param(
	[Parameter(ParameterSetName = 'Version', Position = 0, Mandatory)]
	# Built-in parameter validation disabled - See https://github.com/tigattack/VeeamNotify/issues/50
	# [ValidatePattern('^v(\d+\.)?(\d+\.)?(\*|\d+)$')]
	[String]$Version,

	[Parameter(ParameterSetName = 'Release', Position = 0, Mandatory)]
	# Built-in parameter validation disabled - See https://github.com/tigattack/VeeamNotify/issues/50
	# [ValidateSet('Release', 'Prerelease')]
	[String]$Latest,

	[Parameter(ParameterSetName = 'Branch', Position = 0, Mandatory)]
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

#region Functions

function Test-InstallationPrerequisites {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$Project,

		[Parameter(Mandatory)]
		[string]$InstallPath,

		[Parameter()]
		[string]$Version,

		[Parameter()]
		[string]$Latest
	)

	# Check if this project is already installed and if so, exit
	if (Test-Path "$InstallPath\$Project\resources\version.txt") {
		$installedVersion = (Get-Content -Raw "$InstallPath\$Project\resources\version.txt").Trim()
		Write-Output "`n$Project ($installedVersion) is already installed. This script cannot update an existing installation."
		Write-Output "Please manually update or delete/rename the existing installation and retry.`n`n"
		return $false
	}
	elseif ((Test-Path "$InstallPath\$Project") -and (Get-ChildItem "$InstallPath\$Project").Count -gt 0) {
		"`nThe install path ($InstallPath\$Project) already exists with children, " `
			+ "but an existing installation couldn't be detected (looking for $InstallPath\$Project\resources\version.txt)." | Write-Output
		Write-Output "Please remove the install path and retry.`n`n"
		return $false
	}

	# Validate Version parameter if provided
	if ($Version -and $Version -notmatch '^v(\d+\.)?(\d+\.)?(\*|\d+)$') {
		Write-Warning "Version parameter value '$Version' does not match the version naming structure."
		return $false
	}

	# Validate Latest parameter if provided
	if ($Latest -and $Latest -notin 'Release', 'Prerelease') {
		Write-Warning "Latest parameter value must be one of 'Release' or 'Prelease'."
		return $false
	}

	return $true
}

function Get-GitHubReleaseInfo {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$Project
	)

	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	try {
		$releases = Invoke-RestMethod -Uri "https://api.github.com/repos/tigattack/$Project/releases" -Method Get
		$branches = (Invoke-RestMethod -Uri "https://api.github.com/repos/tigattack/$Project/branches" -Method Get).name

		# Parse latest release and latest prerelease
		$latestPrerelease = $null
		$latestStable = $null

		foreach ($i in $releases) {
			if ($i.prerelease -and -not $latestPrerelease) {
				$latestPrerelease = $i.tag_name
			}
		}

		foreach ($i in $releases) {
			if (-not $i.prerelease -and -not $latestStable) {
				$latestStable = $i.tag_name
			}
		}

		return @{
			Releases         = $releases
			Branches         = $branches
			LatestPrerelease = $latestPrerelease
			LatestStable     = $latestStable
		}
	}
	catch {
		$versionStatusCode = $_.Exception.Response.StatusCode.value__
		Write-Warning "Failed to query GitHub for $Project releases."
		throw "HTTP status code: $versionStatusCode"
	}
}

function Get-InstallationSource {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$Project,

		[Parameter()]
		[string]$Version,

		[Parameter()]
		[string]$Latest,

		[Parameter()]
		[string]$Branch,

		[Parameter()]
		[switch]$NonInteractive,

		[Parameter(Mandatory)]
		[hashtable]$GitHubInfo
	)

	$releases = $GitHubInfo.Releases
	$branches = $GitHubInfo.Branches
	$latestStable = $GitHubInfo.LatestStable
	$latestPrerelease = $GitHubInfo.LatestPrerelease

	# If no installation source provided and interactive mode enabled, query user
	if (-not $Version -and -not $Latest -and -not $Branch -and -not $NonInteractive) {
		# Query download type / release stream
		if ($releases) {
			[System.Management.Automation.Host.ChoiceDescription[]]$downloadQuery_opts = @()
			$downloadQuery_opts += New-Object System.Management.Automation.Host.ChoiceDescription '&Release', "Download the latest release or prerelease. You will be prompted if there's a choice between the two."
			$downloadQuery_opts += New-Object System.Management.Automation.Host.ChoiceDescription '&Version', 'Download a specific version.'
			$downloadQuery_opts += New-Object System.Management.Automation.Host.ChoiceDescription '&Branch', 'Download a branch.'
			$downloadQuery_result = $host.UI.PromptForChoice(
				'Download type',
				"Please select how you would like to download $Project.",
				$downloadQuery_opts,
				0
			)
		}
		else {
			$branchQuery_yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Install from a branch.'
			$branchQuery_no = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Cancel installation.'
			$host.UI.PromptForChoice(
				'Would you like to install from a branch?',
				"There are currently no releases or prereleases available for $Project.",
				@($branchQuery_yes, $branchQuery_no),
				0
			) | ForEach-Object {
				if ($_ -eq 0) { $downloadQuery_result = 2 }
				else { exit }
			}
		}

		# Set download type
		$releasePrompt = $false
		switch ($downloadQuery_result) {
			0 {
				if ($latestStable -and $latestPrerelease) {
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

					switch ($versionQuery_result) {
						0 {
							$Latest = 'Release'
						}
						1 {
							$Latest = 'Prerelease'
						}
					}
				}
				elseif ($latestStable) {
					$Latest = 'Release'
				}
				elseif ($latestPrerelease) {
					$prereleaseQuery_yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Install the latest prerelease.'
					$prereleaseQuery_no = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Cancel installation.'
					$host.UI.PromptForChoice(
						'Do you wish to install the latest prerelease?',
						'You chose release, but the only available releases are prereleases.',
						@($prereleaseQuery_yes, $prereleaseQuery_no),
						0
					) | ForEach-Object {
						if ($_ -eq 0) { $Latest = 'Prerelease' }
						else { exit }
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
					if ($releases.tag_name -notcontains $Version) { Write-Output "`nInvalid version, please try again." }
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
					if ($branches -notcontains $Branch) { Write-Output "`nInvalid branch name, please try again." }
				} until (
					$branches -contains $Branch
				)
			}
		}
	}

	# Determine download properties
	$downloadProperties = @{}

	# Download branch if specified
	if ($Branch) {
		# Throw if branch not found
		if (-not $branches.Contains($Branch)) {
			throw "Branch '$Branch' not found. Will not prompt for branch in non-interactive mode."
		}

		# Set $releaseName to branch name
		$releaseName = $Branch

		# Define download URL
		$downloadUrl = "https://api.github.com/repos/tigattack/$Project/zipball/$Branch"
		$downloadProperties.IsBranch = $true
	}
	# Otherwise work with versions
	else {
		# Define release to use
		if ($Latest) {
			switch ($Latest) {
				'Release' {
					$releaseName = $latestStable
				}
				'Prerelease' {
					$releaseName = $latestPrerelease
				}
			}
		}
		elseif ($Version) {
			$releaseName = $Version
		}

		if (($Latest -or $releasePrompt) -and (-not $releaseName)) {
			Write-Warning 'A release of the specified type could not found.'
			exit
		}

		# Define download URL
		$downloadUrl = Invoke-RestMethod "https://api.github.com/repos/tigattack/$Project/releases" | ForEach-Object {
			if ($_.tag_name -eq $releaseName) {
				$_.assets[0].browser_download_url
			}
		}
		$downloadProperties.IsBranch = $false
	}

	# Sanitise releaseName for OutFile if installing from branch
	if ($Branch) {
		$outFile = "$Project-$($releaseName -replace '[\W]','-')"
	}
	else {
		$outFile = "$Project-$releaseName"
	}

	$downloadProperties.ReleaseName = $releaseName
	$downloadProperties.OutFile = $outFile
	$downloadProperties.DownloadUrl = $downloadUrl

	return $downloadProperties
}

function Install-DownloadedProject {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$Project,

		[Parameter(Mandatory)]
		[string]$InstallParentPath,

		[Parameter(Mandatory)]
		[string]$DownloadUrl,

		[Parameter(Mandatory)]
		[string]$OutFile,

		[Parameter(Mandatory)]
		[string]$ReleaseName,

		[Parameter(Mandatory)]
		[bool]$IsBranch
	)

	# Download parameters
	$DownloadParams = @{
		Uri     = $DownloadUrl
		OutFile = "$env:TEMP\$OutFile.zip"
	}

	# Download project from GitHub
	try {
		Write-Output "`nDownloading $Project $ReleaseName from GitHub..."
		Invoke-WebRequest @DownloadParams
	}
	catch {
		$downloadStatusCode = $_.Exception.Response.StatusCode.value__
		Write-Warning "Failed to download $Project $ReleaseName."
		throw "HTTP status code: $downloadStatusCode"
	}

	# Unblock downloaded ZIP
	try {
		Write-Output 'Unblocking ZIP...'
		Unblock-File -Path "$env:TEMP\$OutFile.zip"
	}
	catch {
		Write-Warning 'Failed to unblock downloaded files. You will need to run the following commands manually once installation is complete:'
		Write-Output "Get-ChildItem -Path $InstallParentPath -Filter *.ps* -Recurse | Unblock-File"
	}

	# Extract release to destination path
	Write-Output "Extracting files to '$InstallParentPath'..."
	Expand-Archive -Path "$env:TEMP\$OutFile.zip" -DestinationPath "$InstallParentPath" -Force

	# Rename destination and tidy up
	Write-Output 'Renaming directory and tidying up...'
	if (Test-Path "$InstallParentPath\$OutFile") {
		Rename-Item -Path "$InstallParentPath\$OutFile" -NewName "$Project"
	}
	else {
		# Necessary to handle branch downloads, which come as a ZIP containing a directory named similarly to "tigattack-VeeamNotify-2100906".
		# Look for a directory less than 5 minutes old which matches the example name stated above.
        (Get-ChildItem $InstallParentPath | Where-Object {
			$_.LastWriteTime -gt (Get-Date).AddMinutes(-5) -and
			$_.Name -match "tigattack-$Project-.*" -and
			$_.PsIsContainer
		})[0] | Rename-Item -NewName "$Project"
	}

	# Clean up temp files
	Remove-Item -Path "$env:TEMP\$OutFile.zip"
}

function Set-ProjectConfiguration {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$Project,

		[Parameter(Mandatory)]
		[string]$InstallParentPath
	)

	Write-Output "`nBeginning configuration..."

	# Join config path
	$configPath = Join-Path -Path $InstallParentPath -ChildPath $Project | Join-Path -ChildPath 'config\conf.json'

	# Create config from example if it doesn't exist
	if (-not (Test-Path $configPath)) {
		Write-Output "`nCreating configuration file..."
		$exampleConfig = Join-Path -Path $InstallParentPath -ChildPath $Project | Join-Path -ChildPath 'config\conf.example.json'
		Copy-Item -Path $exampleConfig -Destination $configPath
	}

	# Get config
	$config = Get-Content "$configPath" -Raw | ConvertFrom-Json

	# Configure service
	$config = Set-NotificationService -Config $config

	# Configure mentions
	$config = Set-MentionPreference -Config $config

	# Write config
	try {
		Write-Output "`nSetting configuration..."
		ConvertTo-Json $config | Set-Content "$configPath"
		Write-Output "`nConfiguration set successfully. Configuration can be found in `"$configPath`"."
	}
	catch {
		Write-Warning "Failed to write configuration file at `"$configPath`". Please open the file and complete configuration manually."
	}

	# Run configuration deployment tool if requested
	Invoke-DeploymentTool -InstallParentPath $InstallParentPath -Project $Project -ConfigPath $configPath

	return $configPath
}

function Set-NotificationService {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[PSCustomObject]$Config
	)

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

	# TODO: support Telegram & ping
	$webhookPrompt = "`nPlease enter your webhook URL"
	switch ($servicePrompt_result) {
		0 {
			$Config.services.discord.webhook = Read-Host -Prompt $webhookPrompt
		}
		1 {
			$Config.services.slack.webhook = Read-Host -Prompt $webhookPrompt
		}
		2 {
			$Config.services.teams.webhook = Read-Host -Prompt $webhookPrompt
		}
	}

	return $Config, $servicePrompt_result
}

function Set-MentionPreference {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[PSCustomObject]$Config,

		[Parameter()]
		[int]$ServiceType
	)

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

	if ($mentionPreference_result -ne 0) {
		switch ($ServiceType) {
			0 {
				$Config.services.discord.user_id = Read-Host -Prompt "`nPlease enter your Discord user ID"
			}
			1 {
				$Config.services.slack.user_id = Read-Host -Prompt "`nPlease enter your Slack member ID"
			}
			2 {
				$Config.services.teams.user_id = Read-Host -Prompt "`nPlease enter your Teams email address"
				Write-Output "`nTeams also requires a name to be specified for mentions.`nIf you do not specify anything, your username (from your email address) will be used."
				$Config.services.teams.user_name = Read-Host -Prompt 'Please enter your name on Teams (e.g. John Smith)'
			}
		}
	}

	# Set config values
	switch ($mentionPreference_result) {
		0 {
			$Config.mentions.on_failure = $false
			$Config.mentions.on_warning = $false
		}
		1 {
			$Config.mentions.on_failure = $false
			$Config.mentions.on_warning = $true
		}
		2 {
			$Config.mentions.on_failure = $true
			$Config.mentions.on_warning = $false
		}
		3 {
			$Config.mentions.on_failure = $true
			$Config.mentions.on_warning = $true
		}
	}

	return $Config
}

function Invoke-DeploymentTool {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$InstallParentPath,

		[Parameter(Mandatory)]
		[string]$Project,

		[Parameter(Mandatory)]
		[string]$ConfigPath
	)

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
		if ($_ -eq 0) {
			Write-Output "`nRunning configuration deployment script...`n"
			& "$InstallParentPath\$Project\resources\DeployVeeamConfiguration.ps1" -InstallParentPath $InstallParentPath
		}
	}
}

#endregion Functions

# Main execution block
$project = 'VeeamNotify'
$ErrorActionPreference = 'Stop'

Write-Output @'
#######################################
#                                     #
#        VeeamNotify Installer        #
#                                     #
#######################################
'@

# Validate prerequisites
$validPrereqs = Test-InstallationPrerequisites -Project $project -InstallPath $InstallParentPath -Version $Version -Latest $Latest
if (-not $validPrereqs) { exit 1 }

# Get GitHub release info
$gitHubInfo = Get-GitHubReleaseInfo -Project $project

# Determine what to download and install
$downloadProperties = Get-InstallationSource -Project $project -Version $Version -Latest $Latest -Branch $Branch -NonInteractive:$NonInteractive -GitHubInfo $gitHubInfo

# Download and install the project
Install-DownloadedProject -Project $project `
	-InstallParentPath $InstallParentPath `
	-DownloadUrl $downloadProperties.DownloadUrl `
	-OutFile $downloadProperties.OutFile `
	-ReleaseName $downloadProperties.ReleaseName `
	-IsBranch $downloadProperties.IsBranch

# Configure the installation if not running in non-interactive mode
if (-not $NonInteractive) {
	$configPath = Set-ProjectConfiguration -Project $project -InstallParentPath $InstallParentPath
}
else {
	$configPath = Join-Path -Path $InstallParentPath -ChildPath $project | Join-Path -ChildPath 'config\conf.json'
	Write-Output "`nWill not prompt for VeeamNotify configuration, or to run Veeam configuration deployment script in non-interactive mode.`n"
	Write-Output "`nConfiguration can be found in `"$configPath`"."
}

Write-Output "`nInstallation complete!`n"
