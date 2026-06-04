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

Describe 'New-MikrusSSHArgs' {
    BeforeAll {
        $script:cfg = [pscustomobject]@{
            srv='a123'; host='srv03.mikr.us'; sshPort=10123; user='root'
            identityFile='C:\keys\mikrus_ed25519'; apiKey='SECRET'; apiBase='https://api.mikr.us'
        }
    }

    It 'buduje argumenty ssh z portem, kluczem i BatchMode' {
        $a = New-MikrusSSHArgs -Config $script:cfg -Command 'echo ok'
        $a | Should -Be @('-p','10123','-i','C:\keys\mikrus_ed25519','-o','BatchMode=yes','root@srv03.mikr.us','echo ok')
    }
}

Describe 'Invoke-MikrusSSH -DryRun' {
    It 'zwraca pelna komende ssh bez wykonania' {
        $cfg = [pscustomobject]@{
            srv='a123'; host='srv03.mikr.us'; sshPort=10123; user='root'
            identityFile='C:\keys\mikrus_ed25519'; apiKey='SECRET'; apiBase='https://api.mikr.us'
        }
        $cmd = Invoke-MikrusSSH -Command 'uptime' -Config $cfg -DryRun
        $cmd[0] | Should -Be 'ssh'
        $cmd | Should -Contain 'root@srv03.mikr.us'
        $cmd[-1] | Should -Be 'uptime'
    }
}

Describe 'New-MikrusScpArgs' {
    BeforeAll {
        $script:cfg = [pscustomobject]@{
            srv='a123'; host='srv03.mikr.us'; sshPort=10123; user='root'
            identityFile='C:\keys\mikrus_ed25519'; apiKey='SECRET'; apiBase='https://api.mikr.us'
        }
    }

    It 'upload: lokalny przed zdalnym, port wielka P' {
        $a = New-MikrusScpArgs -Config $script:cfg -Direction up -Local 'C:\plik.txt' -Remote '/root/plik.txt'
        $a | Should -Be @('-P','10123','-i','C:\keys\mikrus_ed25519','-o','BatchMode=yes','C:\plik.txt','root@srv03.mikr.us:/root/plik.txt')
    }

    It 'download: zdalny przed lokalnym' {
        $a = New-MikrusScpArgs -Config $script:cfg -Direction down -Local 'C:\plik.txt' -Remote '/root/plik.txt'
        $a[-2] | Should -Be 'root@srv03.mikr.us:/root/plik.txt'
        $a[-1] | Should -Be 'C:\plik.txt'
    }

    It 'dodaje -r dla katalogow' {
        $a = New-MikrusScpArgs -Config $script:cfg -Direction up -Local 'C:\dir' -Remote '/root/dir' -Recurse
        $a | Should -Contain '-r'
    }
}

Describe 'Send-MikrusFile -DryRun' {
    It 'zwraca komende scp upload' {
        $cfg = [pscustomobject]@{
            srv='a123'; host='srv03.mikr.us'; sshPort=10123; user='root'
            identityFile='C:\keys\mikrus_ed25519'; apiKey='SECRET'; apiBase='https://api.mikr.us'
        }
        $cmd = Send-MikrusFile -Local 'C:\plik.txt' -Remote '/root/plik.txt' -Config $cfg -DryRun
        $cmd[0] | Should -Be 'scp'
        $cmd[-1] | Should -Be 'root@srv03.mikr.us:/root/plik.txt'
    }
}
