Describe 'EMS.Jwt' {
    BeforeAll {
        Import-Module "$PSScriptRoot\..\Modules\Security\EMS.Jwt.psm1" -Force
        $script:secret = 'a-very-long-test-secret-please-change-me'
    }

    It 'round-trips a valid token' {
        $t = New-EMSJwt -Subject 'alice' -Role 'admin' -Groups @('g1','g2') -Secret $secret
        $c = ConvertFrom-EMSJwt -Token $t -Secret $secret
        $c.sub  | Should -Be 'alice'
        $c.role | Should -Be 'admin'
    }

    It 'rejects tampered payload' {
        $t = New-EMSJwt -Subject 'alice' -Role 'user' -Secret $secret
        $parts = $t -split '\.'
        $bad = "$($parts[0]).eyJzdWIiOiJhbGljZSIsInJvbGUiOiJhZG1pbiJ9.$($parts[2])"
        ConvertFrom-EMSJwt -Token $bad -Secret $secret | Should -BeNullOrEmpty
    }

    It 'rejects wrong secret' {
        $t = New-EMSJwt -Subject 'alice' -Role 'admin' -Secret $secret
        ConvertFrom-EMSJwt -Token $t -Secret 'different-secret' | Should -BeNullOrEmpty
    }

    It 'rejects expired token' {
        $t = New-EMSJwt -Subject 'alice' -Role 'admin' -Secret $secret -ExpiresIn -40
        ConvertFrom-EMSJwt -Token $t -Secret $secret | Should -BeNullOrEmpty
    }

    It 'rejects alg=none / wrong alg' {
        # craft a token with alg=none
        $h = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"alg":"none","typ":"JWT"}')).TrimEnd('=').Replace('+','-').Replace('/','_')
        $p = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"sub":"x","role":"admin","exp":9999999999,"nbf":0,"iss":"ems-api","aud":"ems-webui"}')).TrimEnd('=').Replace('+','-').Replace('/','_')
        ConvertFrom-EMSJwt -Token "$h.$p." -Secret $secret | Should -BeNullOrEmpty
    }
}
