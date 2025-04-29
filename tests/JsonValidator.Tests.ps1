[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute(
	'PSUseCompatibleCommands',
	'',
	Justification = 'Pester tests are run in modern PowerShell'
)]
param ()

BeforeAll {
	# Import the module to test
	$modulePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'resources\JsonValidator.psm1')
	Import-Module $modulePath -Force

	# Create a temporary directory for test files
	$script:tempDir = Join-Path -Path $TestDrive -ChildPath 'JsonValidatorTests'
	New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null
}

AfterAll {
	# Clean up temporary directory
	if (Test-Path -Path $script:tempDir) {
		Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
	}
}

Describe 'Test-JsonValid' {
	Context 'Valid JSON validation' {
		BeforeAll {
			# Simple schema requiring a string name and integer age
			$schema = @'
            {
                "$schema": "http://json-schema.org/draft-04/schema#",
                "type": "object",
                "properties": {
                    "name": { "type": "string" },
                    "age": { "type": "integer" }
                },
                "required": ["name", "age"]
            }
'@

			# Valid JSON matching the schema
			$validJson = @'
            {
                "name": "John Doe",
                "age": 30
            }
'@
			# Create temporary files for the test
			$schemaPath = Join-Path -Path $script:tempDir -ChildPath 'valid-schema.json'
			$jsonPath = Join-Path -Path $script:tempDir -ChildPath 'valid-test.json'

			Set-Content -Path $schemaPath -Value $schema
			Set-Content -Path $jsonPath -Value $validJson

			$result = Test-JsonValid -JsonPath $jsonPath -SchemaPath $schemaPath
		}

		It 'Should return a JsonValidationResult object' {
			$result | Should -Not -Be $null
			# Check properties instead of type
			$result.PSObject.Properties.Name | Should -Contain 'IsValid'
			$result.PSObject.Properties.Name | Should -Contain 'Message'
		}

		It 'Should return IsValid as true for valid JSON' {
			$result.IsValid | Should -Be $true
		}

		It 'Should return a success message for valid JSON' {
			$result.Message | Should -Be 'JSON validation succeeded.'
		}
	}

	Context 'Invalid JSON validation' {
		BeforeAll {
			# Simple schema requiring a string name and integer age
			$schema = @'
            {
                "$schema": "http://json-schema.org/draft-04/schema#",
                "type": "object",
                "properties": {
                    "name": { "type": "string" },
                    "age": { "type": "integer" }
                },
                "required": ["name", "age"]
            }
'@

			# Invalid JSON - wrong type for age
			$invalidJson = @'
            {
                "name": "John Doe",
                "age": "thirty"
            }
'@
			# Create temporary files for the test
			$schemaPath = Join-Path -Path $script:tempDir -ChildPath 'invalid-schema.json'
			$jsonPath = Join-Path -Path $script:tempDir -ChildPath 'invalid-test.json'

			Set-Content -Path $schemaPath -Value $schema
			Set-Content -Path $jsonPath -Value $invalidJson

			$result = Test-JsonValid -JsonPath $jsonPath -SchemaPath $schemaPath
		}

		It 'Should return IsValid as false for invalid JSON' {
			$result.IsValid | Should -Be $false
		}

		It 'Should include error details in the Message' {
			$result.Message | Should -Match 'invalid'
		}
	}

	Context 'Malformed JSON' {
		BeforeAll {
			$schema = '{ "type": "object" }'
			# Malformed JSON with missing closing brace
			$malformedJson = '{ "name": "John Doe"'

			# Create temporary files for the test
			$schemaPath = Join-Path -Path $script:tempDir -ChildPath 'malformed-schema.json'
			$jsonPath = Join-Path -Path $script:tempDir -ChildPath 'malformed-test.json'

			Set-Content -Path $schemaPath -Value $schema
			Set-Content -Path $jsonPath -Value $malformedJson

			$result = Test-JsonValid -JsonPath $jsonPath -SchemaPath $schemaPath
		}

		It 'Should return IsValid as false for malformed JSON' {
			$result.IsValid | Should -Be $false
		}

		It 'Should include "Unexpected error" in the Message' {
			$result.Message | Should -Match 'Unexpected error'
		}
	}

	Context 'Invalid schema' {
		BeforeAll {
			$json = '{ "name": "John Doe" }'
			# Malformed schema with missing closing brace
			$invalidSchema = '{ "type": "object"'

			# Create temporary files for the test
			$schemaPath = Join-Path -Path $script:tempDir -ChildPath 'bad-schema.json'
			$jsonPath = Join-Path -Path $script:tempDir -ChildPath 'good-test.json'

			Set-Content -Path $schemaPath -Value $invalidSchema
			Set-Content -Path $jsonPath -Value $json

			$result = Test-JsonValid -JsonPath $jsonPath -SchemaPath $schemaPath
		}

		It 'Should return IsValid as false for invalid schema' {
			$result.IsValid | Should -Be $false
		}

		It 'Should return error message for invalid schema' {
			$result.Message | Should -Not -BeNullOrEmpty
		}
	}

	Context 'File not found' {
		It 'Should throw an exception for non-existent JSON file' {
			{ Test-JsonValid -JsonPath 'nonexistent.json' -SchemaPath "$script:tempDir\schema.json" } |
				Should -Throw 'JSON file not found: nonexistent.json'
		}

		It 'Should throw an exception for non-existent schema file' {
			# Create a temporary JSON file
			$jsonPath = Join-Path -Path $script:tempDir -ChildPath 'exists.json'
			'{}' | Set-Content -Path $jsonPath

			{ Test-JsonValid -JsonPath $jsonPath -SchemaPath 'nonexistent.json' } |
				Should -Throw 'Schema file not found: nonexistent.json'
		}
	}
}
