# The synthetic CLI shares test-only state across child script scopes and removes
# it in AfterAll. Production code does not use these global variables.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Synthetic CLI test state; cleaned in AfterAll.')]
param()

BeforeAll {
    $script:Entry = Join-Path (Split-Path $PSScriptRoot) 'codex-mode.ps1'
    $script:OriginalHome = $env:CODEX_HOME
    $script:Fixture = @'
# Synthetic configuration; no credentials or personal paths.
model = "deepseek-test"
model_provider = "deepseek" # active provider
model_catalog_json = 'catalog#test.json'
openai_base_url = "https://example.invalid/openai"
chatgpt_base_url = "https://example.invalid/chatgpt"
forced_login_method = "api"
approval_policy = "on-request"
sandbox_mode = "workspace-write"

[model_providers.deepseek]
name = "DeepSeek test endpoint"
base_url = "https://example.invalid/v1"
wire_api = "responses"
env_key = "CODEX_MODE_TEST_KEY"
requires_openai_auth = false

[model_providers.deepseek.env_http_headers]
X-Test = "CODEX_MODE_TEST_HEADER"

[model_providers.deepseek-other]
name = "Unrelated provider"
base_url = "https://example.invalid/other"

[mcp_servers.example]
command = "example-command"
args = ["--test"]

[sandbox_workspace_write]
network_access = false

[projects."example-project"]
trust_level = "trusted"

[[unrelated_entries]]
name = "array boundary"
'@
    function Invoke-Mode([string]$Selection) {
        & $script:Entry $Selection -NoLogin -SkipDoctor 6>$null 3>$null
    }
    function Read-TestConfig { [IO.File]::ReadAllText($script:Config) }
    function Read-TestState { [IO.File]::ReadAllText($script:State) | ConvertFrom-Json -AsHashtable }
}
AfterAll { $env:CODEX_HOME = $script:OriginalHome }

Describe 'Codex provider switching in an isolated CODEX_HOME' {
    BeforeEach {
        $env:CODEX_HOME = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $env:CODEX_HOME | Out-Null
        $script:Config = Join-Path $env:CODEX_HOME 'config.toml'
        $script:State = Join-Path $env:CODEX_HOME 'mode-switcher/deepseek-state.json'
        [IO.File]::WriteAllText($script:Config, $script:Fixture)
    }
    It 'Status reports the active provider and does not create state' {
        $output = & $script:Entry Status -NoLogin -SkipDoctor 6>&1 | Out-String
        $output | Should -Match 'Provider\s+: deepseek'
        $output | Should -Match 'Model\s+: deepseek-test'
        Test-Path (Split-Path $script:State) | Should -BeFalse
        Read-TestConfig | Should -BeExactly $script:Fixture
    }
    It 'defaults to Status' {
        $output = & $script:Entry -NoLogin -SkipDoctor 6>&1 | Out-String
        $output | Should -Match 'Provider\s+: deepseek'
    }
    It 'honors a custom CODEX_HOME including spaces' {
        $env:CODEX_HOME = Join-Path $env:CODEX_HOME 'custom home'
        Invoke-Mode GPT
        Test-Path (Join-Path $env:CODEX_HOME 'config.toml') | Should -BeTrue
        Read-TestConfig | Should -BeExactly $script:Fixture
    }
    It 'Init captures root selectors and nested provider tables without changing config' {
        Invoke-Mode Init
        $state = Read-TestState
        $state.provider_id | Should -Be 'deepseek'
        $state.model_catalog_json | Should -Be "model_catalog_json = 'catalog#test.json'"
        $state.provider_tables | Should -Match 'model_providers.deepseek.env_http_headers'
        $state.provider_tables | Should -Not -Match 'mcp_servers|unrelated_entries|deepseek-other'
        Read-TestConfig | Should -BeExactly $script:Fixture
    }
    It 'backs up the exact bytes before GPT modification' {
        $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:Config))
        Invoke-Mode GPT
        $backup = Get-ChildItem (Join-Path $env:CODEX_HOME 'mode-switcher/backups') -Filter 'config.*.toml'
        @($backup).Count | Should -Be 1
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($backup.FullName)) | Should -BeExactly $before
    }
    It 'sets GPT to openai and ChatGPT without a hardcoded model or custom endpoints' {
        Invoke-Mode GPT
        $text = Read-TestConfig
        $text | Should -Match '(?m)^model_provider = "openai"$'
        $text | Should -Match '(?m)^forced_login_method = "chatgpt"$'
        $text | Should -Not -Match '(?m)^(model|model_catalog_json|openai_base_url|chatgpt_base_url)\s*='
        $text | Should -Not -Match '\[model_providers.deepseek\]'
    }
    It 'repeated GPT is byte stable and preserves saved state' {
        Invoke-Mode GPT
        $once = Read-TestConfig
        $saved = [IO.File]::ReadAllText($script:State)
        Invoke-Mode GPT
        Read-TestConfig | Should -BeExactly $once
        [IO.File]::ReadAllText($script:State) | Should -BeExactly $saved
    }
    It 'Init in GPT does not overwrite saved custom state' {
        Invoke-Mode GPT
        $saved = [IO.File]::ReadAllText($script:State)
        Invoke-Mode Init
        [IO.File]::ReadAllText($script:State) | Should -BeExactly $saved
    }
    It 'repeated Init creates unique config and state backups' {
        Invoke-Mode Init
        Invoke-Mode Init
        $dir = Join-Path $env:CODEX_HOME 'mode-switcher/backups'
        @(Get-ChildItem $dir -Filter 'config.*.toml').Count | Should -Be 2
        @(Get-ChildItem $dir -Filter 'state.*.json').Count | Should -Be 1
    }
    It 'restores all custom selectors and provider tables' {
        Invoke-Mode GPT
        Invoke-Mode DeepSeek
        $text = Read-TestConfig
        foreach ($line in ($script:Fixture -split '\r?\n' | Where-Object { $_ -match '^(model|model_provider|model_catalog_json|openai_base_url|chatgpt_base_url|forced_login_method)\s*=' })) {
            $text.Contains($line) | Should -BeTrue
        }
        $text | Should -Match '\[model_providers.deepseek.env_http_headers\]'
    }
    It 'repeated DeepSeek is byte stable without duplicate tables or comments' {
        Invoke-Mode GPT
        Invoke-Mode DeepSeek
        $once = Read-TestConfig
        Invoke-Mode DeepSeek
        Read-TestConfig | Should -BeExactly $once
        ([regex]::Matches((Read-TestConfig), '# Managed provider/auth selection')).Count | Should -Be 1
    }
    It 'Toggle switches both directions and can repeat' {
        Invoke-Mode Toggle
        Read-TestConfig | Should -Match 'model_provider = "openai"'
        Invoke-Mode Toggle
        Read-TestConfig | Should -Match 'model_provider = "deepseek"'
        Invoke-Mode Toggle
        Read-TestConfig | Should -Match 'model_provider = "openai"'
    }
    It 'preserves unrelated MCP, sandbox, project, other provider and array table configuration' {
        Invoke-Mode GPT
        $text = (Read-TestConfig) -replace 'network_access = false', 'network_access = true'
        [IO.File]::WriteAllText($script:Config, $text)
        Invoke-Mode DeepSeek
        $text = Read-TestConfig
        foreach ($expected in @('[mcp_servers.example]', 'command = "example-command"', 'args = ["--test"]',
            '[sandbox_workspace_write]', 'network_access = true', '[projects."example-project"]',
            'trust_level = "trusted"', '[model_providers.deepseek-other]', '[[unrelated_entries]]',
            'approval_policy = "on-request"', 'sandbox_mode = "workspace-write"')) {
            $text.Contains($expected) | Should -BeTrue
        }
    }
    It 'does not touch credential, database or session files' {
        # Synthetic sentinel only; never reads the real credential store.
        $sentinel = Join-Path $env:CODEX_HOME 'auth.json'
        [IO.File]::WriteAllText($sentinel, '{"test_sentinel":true}')
        Invoke-Mode GPT
        Invoke-Mode DeepSeek
        [IO.File]::ReadAllText($sentinel) | Should -BeExactly '{"test_sentinel":true}'
        @(Get-ChildItem $env:CODEX_HOME -Filter '*.sqlite').Count | Should -Be 0
    }
    It 'supports legacy state without schema_version' {
        Invoke-Mode GPT
        $saved = Read-TestState
        $saved.Remove('schema_version')
        [IO.File]::WriteAllText($script:State, ($saved | ConvertTo-Json))
        Invoke-Mode DeepSeek
        Read-TestConfig | Should -Match 'model_provider = "deepseek"'
    }
    It 'can recover custom state when config has gone missing' {
        Invoke-Mode GPT
        Remove-Item -LiteralPath $script:Config
        Invoke-Mode DeepSeek
        Read-TestConfig | Should -Match 'model_provider = "deepseek"'
    }
    It 'fails safely when custom state is missing' {
        { Invoke-Mode DeepSeek } | Should -Throw '*No saved custom provider*'
        Read-TestConfig | Should -BeExactly $script:Fixture
    }
    It 'fails safely when saved JSON is corrupt' {
        Invoke-Mode GPT
        $before = Read-TestConfig
        [IO.File]::WriteAllText($script:State, '{')
        { Invoke-Mode DeepSeek } | Should -Throw
        Read-TestConfig | Should -BeExactly $before
    }
    It 'rejects injected unrelated tables in state' {
        Invoke-Mode GPT
        $before = Read-TestConfig
        $saved = Read-TestState
        $saved.provider_tables += "`n[projects.injected]`ntrust_level = 'trusted'"
        [IO.File]::WriteAllText($script:State, ($saved | ConvertTo-Json))
        { Invoke-Mode DeepSeek } | Should -Throw '*unrelated configuration*'
        Read-TestConfig | Should -BeExactly $before
    }
    It 'rejects mismatched state selectors' {
        Invoke-Mode GPT
        $saved = Read-TestState
        $saved.model_provider = 'model_provider = "other"'
        [IO.File]::WriteAllText($script:State, ($saved | ConvertTo-Json))
        { Invoke-Mode DeepSeek } | Should -Throw '*selector mismatch*'
    }
    It 'rejects unknown state schema versions' {
        Invoke-Mode GPT
        $saved = Read-TestState
        $saved.schema_version = 99
        [IO.File]::WriteAllText($script:State, ($saved | ConvertTo-Json))
        { Invoke-Mode DeepSeek } | Should -Throw '*state version*'
    }
    It 'fails before altering custom config without a provider table' {
        [IO.File]::WriteAllText($script:Config, 'model_provider = "missing"')
        { Invoke-Mode GPT } | Should -Throw '*no supported table*'
        Read-TestConfig | Should -BeExactly 'model_provider = "missing"'
    }
    It 'refuses multiline TOML instead of corrupting table boundaries' {
        $text = $script:Fixture + "`n" + 'note = """' + "`n[hidden.table]`n" + '"""'
        [IO.File]::WriteAllText($script:Config, $text)
        { Invoke-Mode GPT } | Should -Throw '*Multiline*'
        Read-TestConfig | Should -BeExactly $text
    }
    It 'refuses quoted managed provider tables' {
        $text = $script:Fixture.Replace('[model_providers.deepseek]', '[model_providers."deepseek"]')
        [IO.File]::WriteAllText($script:Config, $text)
        { Invoke-Mode GPT } | Should -Throw '*bare model_providers*'
        Read-TestConfig | Should -BeExactly $text
    }
    It 'refuses duplicate managed root keys' {
        $text = 'model = "duplicate"' + "`n" + $script:Fixture
        [IO.File]::WriteAllText($script:Config, $text)
        { Invoke-Mode GPT } | Should -Throw '*Duplicate managed key*'
    }
    It 'does not overwrite an unsaved different active provider during restore' {
        Invoke-Mode GPT
        $text = $script:Fixture.Replace('deepseek', 'other')
        [IO.File]::WriteAllText($script:Config, $text)
        { Invoke-Mode DeepSeek } | Should -Throw '*different custom provider*'
        Read-TestConfig | Should -BeExactly $text
    }
    It 'refuses concurrent switch operations' {
        Invoke-Mode Init
        $handle = [IO.File]::Open((Join-Path $env:CODEX_HOME 'mode-switcher/.lock'), 'Open', 'ReadWrite', 'None')
        try { { Invoke-Mode GPT } | Should -Throw }
        finally { $handle.Dispose() }
        Read-TestConfig | Should -BeExactly $script:Fixture
    }
    It 'Status with missing config is read-only' {
        Remove-Item -LiteralPath $script:Config
        $output = & $script:Entry Status -NoLogin 6>&1 | Out-String
        $output | Should -Match 'Config\s+: missing'
        Test-Path (Split-Path $script:State) | Should -BeFalse
    }
    It 'Init with missing config preserves the absence of config and state' {
        Remove-Item -LiteralPath $script:Config
        Invoke-Mode Init
        Test-Path $script:Config | Should -BeFalse
        Test-Path $script:State | Should -BeFalse
    }
    It 'Toggle with missing config and state fails without creating config' {
        Remove-Item -LiteralPath $script:Config
        { Invoke-Mode Toggle } | Should -Throw '*No saved custom provider*'
        Test-Path $script:Config | Should -BeFalse
    }
    It 'leaves config unchanged if the saved-state replacement fails' {
        Invoke-Mode Init
        $handle = [IO.File]::Open($script:State, 'Open', 'Read', 'Read')
        try { { Invoke-Mode GPT } | Should -Throw }
        finally { $handle.Dispose() }
        Read-TestConfig | Should -BeExactly $script:Fixture
    }
    It 'handles a quoted # and comments in managed values' {
        Invoke-Mode GPT
        Invoke-Mode DeepSeek
        $output = & $script:Entry Status -NoLogin 6>&1 | Out-String
        $output | Should -Match 'Provider\s+: deepseek\s'
        Read-TestConfig | Should -Match "catalog#test.json"
    }
}

Describe 'Optional Codex commands with a synthetic CLI' {
    BeforeAll {
        # Function precedence replaces the installed CLI in this test process.
        function global:codex {
            $global:CodexModeCalls.Add(($args -join ' '))
            $global:LASTEXITCODE = 0
            switch ($args -join ' ') {
                'login status' { $global:LASTEXITCODE = $global:CodexModeStatusExit; return $global:CodexModeStatusText }
                'login' { $global:LASTEXITCODE = $global:CodexModeLoginExit }
                '--help' { return $global:CodexModeHelp }
                'doctor' { $global:LASTEXITCODE = $global:CodexModeDoctorExit }
                default { throw 'Unexpected synthetic CLI command.' }
            }
        }
    }
    BeforeEach {
        $env:CODEX_HOME = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $global:CodexModeCalls = [Collections.Generic.List[string]]::new()
        $global:CodexModeStatusExit = 0
        $global:CodexModeLoginExit = 0
        $global:CodexModeDoctorExit = 0
        $global:CodexModeStatusText = 'Logged in using ChatGPT'
        $global:CodexModeHelp = '  doctor  Synthetic diagnostics'
    }
    AfterAll {
        Remove-Item Function:\codex
        foreach ($name in @('CodexModeCalls', 'CodexModeStatusExit', 'CodexModeLoginExit',
            'CodexModeDoctorExit', 'CodexModeStatusText', 'CodexModeHelp')) {
            Remove-Variable -Name $name -Scope Global
        }
    }
    It 'queries login and runs supported doctor without relogin for ChatGPT' {
        & $script:Entry GPT 6>$null
        ($global:CodexModeCalls -join ',') | Should -BeExactly 'login status,--help,doctor'
    }
    It 'requests login when successful status identifies an API key' {
        $global:CodexModeStatusText = 'Logged in using an API key'
        & $script:Entry GPT -SkipDoctor 6>$null
        ($global:CodexModeCalls -join ',') | Should -BeExactly 'login status,login'
    }
    It 'requests login when status fails' {
        $global:CodexModeStatusExit = 1
        & $script:Entry GPT -SkipDoctor 6>$null
        ($global:CodexModeCalls -join ',') | Should -BeExactly 'login status,login'
    }
    It 'reports login failure after preserving the selected configuration' {
        $global:CodexModeStatusExit = 1
        $global:CodexModeLoginExit = 1
        { & $script:Entry GPT -SkipDoctor 6>$null } | Should -Throw '*login failed*'
        [IO.File]::ReadAllText((Join-Path $env:CODEX_HOME 'config.toml')) | Should -Match 'forced_login_method = "chatgpt"'
    }
    It 'skips an unsupported doctor without failing the selection' {
        $global:CodexModeHelp = '  exec  Synthetic execution'
        & $script:Entry GPT -NoLogin 6>$null 3>$null
        ($global:CodexModeCalls -join ',') | Should -BeExactly '--help'
    }
    It 'keeps configuration when optional diagnostics fail' {
        $global:CodexModeDoctorExit = 1
        { & $script:Entry GPT -NoLogin 6>$null 3>$null } | Should -Not -Throw
        [IO.File]::ReadAllText((Join-Path $env:CODEX_HOME 'config.toml')) | Should -Match 'model_provider = "openai"'
    }
    It 'NoLogin and SkipDoctor prevent every CLI call' {
        & $script:Entry GPT -NoLogin -SkipDoctor 6>$null
        & $script:Entry Status -NoLogin 6>$null
        & $script:Entry Init -NoLogin 6>$null
        $global:CodexModeCalls.Count | Should -Be 0
    }
    It 'Status queries login but hides raw CLI output' {
        $global:CodexModeStatusText = 'synthetic-private-account-label'
        $output = & $script:Entry Status 6>&1 | Out-String
        $output | Should -Not -Match 'synthetic-private-account-label'
        ($global:CodexModeCalls -join ',') | Should -BeExactly 'login status'
    }
}
