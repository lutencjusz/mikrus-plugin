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
        # Prefiks bazowy stabilny; host i komenda zawsze na koncu.
        $a[0..5] | Should -Be @('-p','10123','-i','C:\keys\mikrus_ed25519','-o','BatchMode=yes')
        $a[-2] | Should -Be 'root@srv03.mikr.us'
        $a[-1] | Should -Be 'echo ok'
    }

    It 'dodaje opcje limitu czasu (ConnectTimeout + ServerAlive)' {
        $a = New-MikrusSSHArgs -Config $script:cfg -Command 'echo ok'
        ($a -join ' ') | Should -Match 'ConnectTimeout=\d+'
        ($a -join ' ') | Should -Match 'ServerAliveInterval=\d+'
        ($a -join ' ') | Should -Match 'ServerAliveCountMax=\d+'
    }

    It 'pola config nadpisuja domyslne limity' {
        $cfg2 = [pscustomobject]@{
            srv='a123'; host='srv03.mikr.us'; sshPort=10123; user='root'
            identityFile='C:\keys\mikrus_ed25519'; apiKey='SECRET'; apiBase='https://api.mikr.us'
            connectTimeout=7
        }
        $a = New-MikrusSSHArgs -Config $cfg2 -Command 'echo ok'
        $a | Should -Contain 'ConnectTimeout=7'
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
        $a[0..5] | Should -Be @('-P','10123','-i','C:\keys\mikrus_ed25519','-o','BatchMode=yes')
        ($a -join ' ') | Should -Match 'ConnectTimeout=\d+'
        $a[-2] | Should -Be 'C:\plik.txt'
        $a[-1] | Should -Be 'root@srv03.mikr.us:/root/plik.txt'
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

Describe 'New-MikrusApiRequest' {
    BeforeAll {
        $script:cfg = [pscustomobject]@{
            srv='a123'; host='srv03.mikr.us'; sshPort=10123; user='root'
            identityFile='C:\keys\mikrus_ed25519'; apiKey='SECRET'; apiBase='https://api.mikr.us'
        }
    }

    It 'buduje URL z apiBase i endpointu oraz dodaje srv' {
        $r = New-MikrusApiRequest -Config $script:cfg -Endpoint '/info'
        $r.Url | Should -Be 'https://api.mikr.us/info'
        $r.Fields['srv'] | Should -Be 'a123'
    }

    It 'normalizuje ukosniki (brak podwojnego /)' {
        $cfg2 = $script:cfg.PSObject.Copy(); $cfg2.apiBase = 'https://api.mikr.us/'
        $r = New-MikrusApiRequest -Config $cfg2 -Endpoint 'stats'
        $r.Url | Should -Be 'https://api.mikr.us/stats'
    }

    It 'dolacza dodatkowe pola z Body (np. domain/port)' {
        $r = New-MikrusApiRequest -Config $script:cfg -Endpoint '/domain' -Body @{ port='30123'; domain='example.com' }
        $r.Fields['port'] | Should -Be '30123'
        $r.Fields['domain'] | Should -Be 'example.com'
        $r.Fields['srv'] | Should -Be 'a123'
    }
}

Describe 'New-MikrusCurlArgs' {
    It 'uzywa --data-urlencode dla pol (kodowanie wartosci)' {
        $a = New-MikrusCurlArgs -Url 'https://api.mikr.us/exec' -Fields @{ cmd = 'a && b' }
        $a | Should -Contain '--data-urlencode'
        $a | Should -Contain 'cmd=a && b'
        $a | Should -Not -Contain '-d'
    }

    It 'czyta klucz z stdin (-K -), wiec nie ma go w argumentach' {
        $a = New-MikrusCurlArgs -Url 'https://api.mikr.us/info' -Fields @{ srv = 'a123' }
        $a | Should -Contain '-K'
        ($a -join ' ') | Should -Not -Match 'Authorization'
    }

    It 'zawiera URL oraz metode POST' {
        $a = New-MikrusCurlArgs -Url 'https://api.mikr.us/info' -Fields @{ srv = 'a123' }
        $a | Should -Contain 'https://api.mikr.us/info'
        $a | Should -Contain 'POST'
    }
}

Describe 'New-MikrusCurlConfig' {
    It 'buduje linie naglowka z kluczem (do podania przez stdin)' {
        $c = New-MikrusCurlConfig -ApiKey 'SECRET'
        $c | Should -Be 'header = "Authorization: SECRET"'
    }
}

Describe 'Invoke-MikrusApi' {
    BeforeAll {
        $script:cfg = [pscustomobject]@{
            srv='a123'; host='srv03.mikr.us'; sshPort=10123; user='root'
            identityFile='C:\keys\mikrus_ed25519'; apiKey='SECRET'; apiBase='https://api.mikr.us'
        }
    }

    It 'parsuje poprawny JSON na obiekt' {
        InModuleScope mikrus {
            Mock Invoke-MikrusCurl { '{"server_id":"a123","status":"running"}' }
            $cfg = [pscustomobject]@{ srv='a123'; host='h'; sshPort=10123; user='root'; identityFile='k'; apiKey='SECRET'; apiBase='https://api.mikr.us' }
            $r = Invoke-MikrusApi -Endpoint '/info' -Config $cfg
            $r.server_id | Should -Be 'a123'
            $r.status | Should -Be 'running'
        }
    }

    It 'rzuca czytelny blad gdy API zwraca pole error' {
        InModuleScope mikrus {
            Mock Invoke-MikrusCurl { '{"error":"nieprawidlowy klucz"}' }
            $cfg = [pscustomobject]@{ srv='a123'; host='h'; sshPort=10123; user='root'; identityFile='k'; apiKey='SECRET'; apiBase='https://api.mikr.us' }
            { Invoke-MikrusApi -Endpoint '/info' -Config $cfg } | Should -Throw -ExpectedMessage '*nieprawidlowy klucz*'
        }
    }

    It 'rzuca blad gdy odpowiedz nie jest JSON-em' {
        InModuleScope mikrus {
            Mock Invoke-MikrusCurl { '<html>502 Bad Gateway</html>' }
            $cfg = [pscustomobject]@{ srv='a123'; host='h'; sshPort=10123; user='root'; identityFile='k'; apiKey='SECRET'; apiBase='https://api.mikr.us' }
            { Invoke-MikrusApi -Endpoint '/info' -Config $cfg } | Should -Throw -ExpectedMessage '*Niepoprawna odpowiedz*'
        }
    }

    It 'nie wywala sie gdy odpowiedz JSON jest golym skalarem' {
        InModuleScope mikrus {
            Mock Invoke-MikrusCurl { '42' }
            $cfg = [pscustomobject]@{ srv='a123'; host='h'; sshPort=10123; user='root'; identityFile='k'; apiKey='SECRET'; apiBase='https://api.mikr.us' }
            $r = Invoke-MikrusApi -Endpoint '/info' -Config $cfg
            $r | Should -Be 42
        }
    }
}
