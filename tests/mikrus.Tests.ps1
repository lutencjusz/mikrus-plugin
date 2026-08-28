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

Describe 'ConvertTo-MikrusShellSingleQuoted' {
    It 'otacza apostrofami zwykly ciag' {
        ConvertTo-MikrusShellSingleQuoted -Text '/root/plik.py' | Should -Be "'/root/plik.py'"
    }

    It 'escapuje apostrof wzorcem zamknij-escape-otworz' {
        ConvertTo-MikrusShellSingleQuoted -Text "it's" | Should -Be "'it'\''s'"
    }

    It 'radzi sobie z pustym ciagiem' {
        ConvertTo-MikrusShellSingleQuoted -Text '' | Should -Be "''"
    }
}

Describe 'New-MikrusHereDocDelimiter' {
    It 'zwraca domyslny ogranicznik gdy tresc go nie zawiera' {
        New-MikrusHereDocDelimiter -Content "print('ok')" | Should -Be 'MIKRUS_EOF'
    }

    It 'zmienia ogranicznik gdy tresc zawiera go w osobnej linii' {
        $content = "linia1`nMIKRUS_EOF`nlinia2"
        New-MikrusHereDocDelimiter -Content $content | Should -Be 'MIKRUS_EOF_1'
    }

    It 'szuka dalej gdy kolejne warianty tez wystepuja' {
        $content = "MIKRUS_EOF`nMIKRUS_EOF_1"
        New-MikrusHereDocDelimiter -Content $content | Should -Be 'MIKRUS_EOF_2'
    }
}

Describe 'New-MikrusRemoteWriteScript' {
    It 'buduje heredoc z trescia i tworzy katalog nadrzedny' {
        $s = New-MikrusRemoteWriteScript -Remote '/root/skrypty/x.py' -Content "print(1)"
        $s | Should -Match "cat > '/root/skrypty/x\.py' <<'MIKRUS_EOF'"
        $s | Should -Match 'mkdir -p'
        $s | Should -Match 'print\(1\)'
        $s | Should -Match 'md5sum'
    }

    It 'zamienia CRLF na LF (CRLF psuje shebang i skrypty bash)' {
        $s = New-MikrusRemoteWriteScript -Remote '/root/x.sh' -Content "#!/bin/bash`r`necho ok"
        $s | Should -Not -Match "`r"
    }

    It 'zostawia dokladnie jeden koncowy newline tresci' {
        # Nadmiarowy newline rozjezdzalby md5 wzgledem kopii lokalnej.
        $s = New-MikrusRemoteWriteScript -Remote '/root/x.sh' -Content "echo ok`n`n`n"
        $s | Should -Match "echo ok`nMIKRUS_EOF"
    }

    It 'dodaje chmod tylko gdy podano -Mode' {
        $bez = New-MikrusRemoteWriteScript -Remote '/root/x.sh' -Content 'echo ok'
        $bez | Should -Not -Match 'chmod'
        $z = New-MikrusRemoteWriteScript -Remote '/root/x.sh' -Content 'echo ok' -Mode '755'
        $z | Should -Match "chmod 755 '/root/x\.sh'"
    }

    It 'odrzuca niepoprawny tryb uprawnien' {
        { New-MikrusRemoteWriteScript -Remote '/root/x.sh' -Content 'echo ok' -Mode 'rwx' } | Should -Throw
    }

    It 'nie urywa pliku gdy tresc zawiera domyslny ogranicznik' {
        $s = New-MikrusRemoteWriteScript -Remote '/root/x.sh' -Content "echo a`nMIKRUS_EOF`necho b"
        $s | Should -Match "<<'MIKRUS_EOF_1'"
        $s | Should -Match 'echo b'
    }
}

Describe 'Set-MikrusRemoteFile -DryRun' {
    BeforeAll {
        $script:cfg = [pscustomobject]@{
            srv='a123'; host='srv03.mikr.us'; sshPort=10123; user='root'
            identityFile='C:\keys\mikrus_ed25519'; apiKey='SECRET'; apiBase='https://api.mikr.us'
        }
    }

    It 'zwraca komende ssh z zdalnym skryptem zapisu' {
        $cmd = Set-MikrusRemoteFile -Remote '/root/x.sh' -Content 'echo ok' -Config $script:cfg -DryRun
        $cmd[0] | Should -Be 'ssh'
        $cmd | Should -Contain 'root@srv03.mikr.us'
        $cmd[-1] | Should -Match "cat > '/root/x\.sh'"
    }

    It 'czyta tresc z pliku lokalnego' {
        $path = Join-Path $TestDrive 'lokalny.sh'
        Set-Content -Path $path -Value 'echo z-pliku' -Encoding utf8
        $cmd = Set-MikrusRemoteFile -Remote '/root/x.sh' -Local $path -Config $script:cfg -DryRun
        $cmd[-1] | Should -Match 'echo z-pliku'
    }

    It 'rzuca blad gdy plik lokalny nie istnieje' {
        $path = Join-Path $TestDrive 'nieistnieje.sh'
        { Set-MikrusRemoteFile -Remote '/root/x.sh' -Local $path -Config $script:cfg -DryRun } |
            Should -Throw -ExpectedMessage '*Brak pliku lokalnego*'
    }
}

Describe 'New-MikrusCronEntry' {
    It 'sklada wpis z 5-polowego harmonogramu' {
        $e = New-MikrusCronEntry -Schedule '35 21 * * *' -Command '/root/skrypty/prune.py'
        $e.Entry | Should -Be '35 21 * * * /root/skrypty/prune.py'
        $e.Lines.Count | Should -Be 1
    }

    It 'przyjmuje harmonogramy specjalne (@daily, @reboot)' {
        (New-MikrusCronEntry -Schedule '@daily' -Command 'echo ok').Entry | Should -Be '@daily echo ok'
        (New-MikrusCronEntry -Schedule '@reboot' -Command 'echo ok').Entry | Should -Be '@reboot echo ok'
    }

    It 'poprzedza wpis komentarzem z prefiksem #' {
        $e = New-MikrusCronEntry -Schedule '0 5 * * *' -Command 'echo ok' -Comment 'backup nocny'
        $e.Lines[0] | Should -Be '# backup nocny'
        $e.Lines[1] | Should -Be '0 5 * * * echo ok'
    }

    It 'nie dubluje # gdy komentarz juz go ma' {
        $e = New-MikrusCronEntry -Schedule '0 5 * * *' -Command 'echo ok' -Comment '# juz z krata'
        $e.Lines[0] | Should -Be '# juz z krata'
    }

    It 'odrzuca harmonogram o zlej liczbie pol' {
        { New-MikrusCronEntry -Schedule '35 21 * *' -Command 'echo ok' } |
            Should -Throw -ExpectedMessage '*5 pol*'
    }

    It 'odrzuca komende z nowa linia (crontab czyta linie osobno)' {
        { New-MikrusCronEntry -Schedule '0 5 * * *' -Command "echo a`necho b" } |
            Should -Throw -ExpectedMessage '*nowej linii*'
    }
}

Describe 'New-MikrusCronAddScript' {
    BeforeAll {
        $script:entry = New-MikrusCronEntry -Schedule '35 21 * * *' -Command '/root/prune.py' -Comment 'retencja'
    }

    It 'robi backup crontaba przed zmiana' {
        $s = New-MikrusCronAddScript -CronEntry $script:entry
        $s | Should -Match 'crontab\.bak-'
        $s | Should -Match 'crontab -l'
    }

    It 'jest idempotentny — sprawdza duplikat przez grep -qxF' {
        $s = New-MikrusCronAddScript -CronEntry $script:entry
        $s | Should -Match "grep -qxF '35 21 \* \* \* /root/prune\.py'"
        $s | Should -Match 'juz istnieje'
    }

    It 'instaluje nowy crontab przez potok do crontab -' {
        $s = New-MikrusCronAddScript -CronEntry $script:entry
        $s | Should -Match '\| crontab -'
        $s | Should -Match "'# retencja'"
    }
}

Describe 'New-MikrusCronRemoveScript' {
    It 'dopasowuje doslownie przez awk index po backupie' {
        $s = New-MikrusCronRemoveScript -Match '/root/prune.py'
        $s | Should -Match 'index\(lines\[i\], pat\)'
        $s | Should -Match 'crontab\.bak-'
    }

    It 'przekazuje wzorzec przez ENVIRON (awk -v zjadloby sekwencje z backslashem)' {
        $s = New-MikrusCronRemoveScript -Match '/root/prune.py'
        $s | Should -Match "MIKRUS_CRON_PATTERN='/root/prune\.py'"
        $s | Should -Match 'ENVIRON\["MIKRUS_CRON_PATTERN"\]'
    }

    It 'kasuje takze blok komentarza nad wpisem i pusty separator' {
        $s = New-MikrusCronRemoveScript -Match '/root/prune.py'
        $s | Should -Match 'lines\[j\] ~ /\^\[\[:space:\]\]\*#/'
        $s | Should -Match 'wraz z komentarzem'
    }

    It 'odrzuca pusty wzorzec (skasowalby caly crontab)' {
        { New-MikrusCronRemoveScript -Match '   ' } | Should -Throw -ExpectedMessage '*caly crontab*'
    }
}

Describe 'Skrypty zdalne nie zawieraja CR' {
    # Regresja: pliki repo maja CRLF, wiec here-stringi PowerShella przenosily \r
    # do skryptu. Bash doklada CR do ostatniego argumentu w linii — `set -e<CR>`
    # konczy sie "invalid option", a sciezka z CR tworzy katalog-widmo.
    It 'New-MikrusRemoteWriteScript' {
        $s = New-MikrusRemoteWriteScript -Remote '/root/x.sh' -Content 'echo ok' -Mode '755'
        $s | Should -Not -Match "`r"
    }

    It 'New-MikrusCronAddScript' {
        $e = New-MikrusCronEntry -Schedule '35 21 * * *' -Command '/root/prune.py' -Comment 'retencja'
        (New-MikrusCronAddScript -CronEntry $e) | Should -Not -Match "`r"
    }

    It 'New-MikrusCronRemoveScript' {
        (New-MikrusCronRemoveScript -Match '/root/prune.py') | Should -Not -Match "`r"
    }

    It 'ConvertTo-MikrusLfText zamienia CRLF i samotny CR na LF' {
        ConvertTo-MikrusLfText -Text "a`r`nb`rc" | Should -Be "a`nb`nc"
    }
}

Describe 'Add-MikrusCronEntry / Remove-MikrusCronEntry -DryRun' {
    BeforeAll {
        $script:cfg = [pscustomobject]@{
            srv='a123'; host='srv03.mikr.us'; sshPort=10123; user='root'
            identityFile='C:\keys\mikrus_ed25519'; apiKey='SECRET'; apiBase='https://api.mikr.us'
        }
    }

    It 'Add zwraca komende ssh ze skryptem dodania' {
        $cmd = Add-MikrusCronEntry -Schedule '35 21 * * *' -Command '/root/prune.py' -Config $script:cfg -DryRun
        $cmd[0] | Should -Be 'ssh'
        $cmd[-1] | Should -Match '\| crontab -'
    }

    It 'Remove zwraca komende ssh ze skryptem usuniecia' {
        $cmd = Remove-MikrusCronEntry -Match '/root/prune.py' -Config $script:cfg -DryRun
        $cmd[-1] | Should -Match 'MIKRUS_CRON_PATTERN'
    }

    It 'Get-MikrusCron zwraca crontab -l' {
        $cmd = Get-MikrusCron -Config $script:cfg -DryRun
        $cmd[-1] | Should -Be 'crontab -l'
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
