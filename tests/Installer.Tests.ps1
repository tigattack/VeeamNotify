Describe 'Installer.ps1' {
	BeforeAll {
		# Create temp install dir
		$installDir = New-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'test-install') -Type Directory -Force

		# Get installer path
		$installerPath = (Get-ChildItem -Path (Split-Path -Path $PSScriptRoot -Parent) -Filter 'Installer.ps1').FullName

		# Define installer params
		$installerParams = @{
			NonInteractive    = $true
			InstallParentPath = $installDir
		}

		# Define required files
		$expectedFiles = @(
			'Bootstrap.ps1',
			'AlertSender.ps1'
		)
		$expectedFiles += $(
			foreach ($dir in 'resources', 'config') {
				$files = Get-ChildItem -Path "$(Split-Path -Path $PSScriptRoot -Parent)\$dir"
				foreach ($file in $files) {
					[string](Join-Path -Path $file.Directory.Name -ChildPath $file.Name)
				}
			}
		)

		# Define required files check
		[scriptblock]$expectedFilesCheck = {
			foreach ($file in $expectedFiles) {
				Join-Path -Path "$installDir" -ChildPath 'VeeamNotify' | Join-Path -ChildPath $file | Should -Exist
			}
		}
	}

	It 'Install from specific version' {
		# Run installer
		& $installerPath -Version 'v1.0' @installerParams

		# Check for expected files
		Invoke-Command -ScriptBlock $expectedFilesCheck
	}

	It 'Install from latest release' {
		# Run installer
		& $installerPath -Latest Release @installerParams

		# Check for expected files
		Invoke-Command -ScriptBlock $expectedFilesCheck
	}

	It 'Install from branch' {
		# Run installer
		& $installerPath -Branch main @installerParams

		# Check for expected files
		Invoke-Command -ScriptBlock $expectedFilesCheck
	}

	AfterEach {
		# Remove temp install dir
		Remove-Item -Path $installDir -Recurse -Force
	}
}
