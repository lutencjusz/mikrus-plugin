Import-Module "$PSScriptRoot/../lib/mikrus.psm1" -Force

Describe 'Modul mikrus laduje sie' {
    It 'importuje sie bez bledu' {
        Get-Module mikrus | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-MikrusConfig' {
    BeforeAll {
        $script:validCfg = @{
            srv = 'a123'; host = 'srv03.mikr.us'; sshPort = 10123; user = 'root'
            identityFile = 'C:\keys\mikrus_ed25519'; apiKey = 'SECRET'; apiBase = 'https://api.mikr.us'
        }
    }

    It 'wczytuje poprawny config z pliku' {
        $path = Join-Path $TestDrive 'config.json'
        $script:validCfg | ConvertTo-Json | Set-Content -Path $path -Encoding utf8
        $cfg = Get-MikrusConfig -Path $path
        $cfg.host | Should -Be 'srv03.mikr.us'
        $cfg.sshPort | Should -Be 10123
    }

    It 'rzuca blad z instrukcja mikrus-setup gdy brak pliku' {
        $path = Join-Path $TestDrive 'nieistnieje.json'
        { Get-MikrusConfig -Path $path } | Should -Throw -ExpectedMessage '*mikrus-setup*'
    }

    It 'rzuca blad gdy brakuje wymaganego pola' {
        $path = Join-Path $TestDrive 'incomplete.json'
        $incomplete = $script:validCfg.Clone(); $incomplete.Remove('apiKey')
        $incomplete | ConvertTo-Json | Set-Content -Path $path -Encoding utf8
        { Get-MikrusConfig -Path $path } | Should -Throw -ExpectedMessage '*apiKey*'
    }
}
