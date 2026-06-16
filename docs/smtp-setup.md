## Configure SMTP for Outbound Email

This guide explains how to enable SMTP for Apollo to send emails.
SMTP is also required for magic link login to work from the frontend.

### Prerequisites
- An SMTP provider (e.g., Resend, SendGrid, Mailgun, SES SMTP, etc.)
- SMTP connection string in the format: `smtp://<username>:<password>@<host>:<port>`
- The author/sender email you want to use

### 1) Create the Kubernetes Secret
Apollo reads SMTP credentials from a secret named `{release}-smtp-credentials` with key `SMTP_CONNECTION_STRING`.

Example (for release `composio` and namespace `composio`):

```bash
kubectl create secret generic composio-composio-secrets \
  -n composio \
  --from-literal=SMTP_CONNECTION_STRING="smtp://<username>:<password>@<host>:<port>"
```
OR reference the secret 

```yaml
 apollo: 
    smtp:
    enabled: false
    smtpAuthorEmail: "admin@yourdomain.com"
    secretRef: "composio-composio-secrets"
    key: "SMTP_CONNECTION_STRING"   
```

Notes:
- If you want to use a custom secret name, set `apollo.smtp.credentialsSecret` accordingly (see step 2).
- For Resend, the connection can look like: `smtp://resend:<API_KEY>@smtp.resend.com:2587`


### 2) Verify
```bash
# Check Apollo env contains SMTP variables
kubectl exec -n composio deploy/composio-apollo -- env | grep SMTP

# Inspect logs for email-related errors
kubectl logs -n composio deploy/composio-apollo --tail=200
```

You should see `SMTP_CONNECTION_STRING` present when `apollo.smtp.enabled` is true, and emails sent with `smtpAuthorEmail` as the from address (provider permitting).

### Tips
- Ensure your SMTP provider allows the configured `smtpAuthorEmail` (some require sender/domain verification).
- For TLS/STARTTLS options, consult your provider’s connection string format or additional parameters.
 - Magic link login: ensure `apollo.overwrite_fe_url` matches the externally reachable frontend URL so links in emails open correctly.


