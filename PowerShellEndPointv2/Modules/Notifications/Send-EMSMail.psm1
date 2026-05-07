<#
    Send-EMSMail.psm1
    EMS v3.0 — Email Notification Module
    Sends customizable emails for reboot reminders, alerts, and reports.
#>

function Send-RebootNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$RecipientEmail,

        [string]$RecipientName = '',

        [int]$UptimeDays = 0,

        [string]$DueDate = '',

        [string]$CustomMessage = ''
    )

    $config = $Global:EMSConfig

    if (-not $config.SMTP) {
        Write-EMSLog -Message "SMTP not configured. Cannot send mail." -Severity Warning -Category Notification
        throw "SMTP configuration missing in EMSConfig.json"
    }

    $smtp = $config.SMTP

    $subject = "Action Required: Please Reboot $ComputerName (Uptime: $UptimeDays days)"

    $body = @"
<!DOCTYPE html>
<html>
<head><style>
body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #f4f6f9; padding: 20px; }
.container { max-width: 600px; margin: auto; background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
.header { background: linear-gradient(135deg, #1a237e, #283593); color: #fff; padding: 20px 30px; }
.header h1 { margin: 0; font-size: 20px; }
.content { padding: 30px; color: #333; line-height: 1.6; }
.alert-box { background: #fff3e0; border-left: 4px solid #f57c00; padding: 15px; margin: 15px 0; border-radius: 4px; }
.info-table { width: 100%; border-collapse: collapse; margin: 15px 0; }
.info-table td { padding: 8px 12px; border-bottom: 1px solid #eee; }
.info-table td:first-child { font-weight: 600; color: #555; width: 40%; }
.footer { background: #f4f6f9; padding: 15px 30px; font-size: 12px; color: #999; text-align: center; }
</style></head>
<body>
<div class="container">
    <div class="header">
        <h1>EMS — Reboot Required</h1>
    </div>
    <div class="content">
        <p>Dear $(if ($RecipientName) { $RecipientName } else { 'User' }),</p>
        <div class="alert-box">
            <strong>Your computer <code>$ComputerName</code> has not been restarted in $UptimeDays days.</strong><br/>
            Regular reboots are essential for security patches, performance, and system stability.
        </div>
        <table class="info-table">
            <tr><td>Computer Name</td><td>$ComputerName</td></tr>
            <tr><td>Uptime</td><td>$UptimeDays days</td></tr>
            $(if ($DueDate) { "<tr><td>Reboot Due By</td><td>$DueDate</td></tr>" })
        </table>
        $(if ($CustomMessage) { "<p>$CustomMessage</p>" })
        <p>Please save your work and restart your computer at your earliest convenience.</p>
        <p>Thank you,<br/>IT Infrastructure Team</p>
    </div>
    <div class="footer">
        This is an automated message from the Enterprise Endpoint Monitoring System (EMS).
    </div>
</div>
</body>
</html>
"@

    try {
        $mailParams = @{
            From       = $smtp.FromAddress
            To         = $RecipientEmail
            Subject    = $subject
            Body       = $body
            SmtpServer = $smtp.Server
            Port       = if ($smtp.Port) { $smtp.Port } else { 25 }
            BodyAsHtml = $true
        }

        if ($smtp.UseSsl) { $mailParams['UseSsl'] = $true }
        if ($smtp.Username -and $smtp.Password) {
            $secPwd = ConvertTo-SecureString $smtp.Password -AsPlainText -Force
            $mailParams['Credential'] = [PSCredential]::new($smtp.Username, $secPwd)
        }

        Send-MailMessage @mailParams

        # Log to database
        Invoke-PGQuery -NonQuery -Query @"
INSERT INTO mail_log (sent_by, recipient_email, recipient_name, subject, template_name, computer_name, status)
VALUES (@sentBy, @recipientEmail, @recipientName, @subject, 'reboot_notification', @computerName, 'sent');
"@ -Parameters @{
            sentBy         = $Global:EMSConfig.Security.AdminGroup
            recipientEmail = $RecipientEmail
            recipientName  = $RecipientName
            subject        = $subject
            computerName   = $ComputerName
        }

        Write-EMSLog -Message "Reboot notification sent to $RecipientEmail for $ComputerName" -Category Notification
        return @{ success = $true; message = "Mail sent to $RecipientEmail" }
    }
    catch {
        # Log failure
        Invoke-PGQuery -NonQuery -Query @"
INSERT INTO mail_log (sent_by, recipient_email, recipient_name, subject, template_name, computer_name, status, error_message)
VALUES (@sentBy, @recipientEmail, @recipientName, @subject, 'reboot_notification', @computerName, 'failed', @errorMsg);
"@ -Parameters @{
            sentBy         = 'system'
            recipientEmail = $RecipientEmail
            recipientName  = $RecipientName
            subject        = $subject
            computerName   = $ComputerName
            errorMsg       = $_.Exception.Message
        }

        Write-EMSLog -Message "Failed to send mail to $RecipientEmail : $($_.Exception.Message)" -Severity Error -Category Notification
        throw
    }
}

Export-ModuleMember -Function Send-RebootNotification
