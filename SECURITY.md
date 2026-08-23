# Security Policy

YO Voice is a voice-first social platform that handles accounts, user-generated content, messaging, live-room participation and moderation data. Security reports must therefore be handled privately and with particular care for user data.

For the project's internal authorization model, Firebase rules principles and security architecture, see [`docs/SECURITY.md`](docs/SECURITY.md).

## Supported versions

Security fixes are provided for the latest production deployment and the current `main` branch.

| Target | Supported |
| --- | --- |
| Latest production deployment | Yes |
| Current `main` branch | Yes |
| Older deployments, tags and feature branches | No |

## Reporting a vulnerability

Please do not report suspected vulnerabilities through public GitHub issues, discussions or pull requests.

Use GitHub's private vulnerability reporting feature for this repository:

1. Open the repository's **Security** tab.
2. Choose **Advisories**.
3. Select **Report a vulnerability**.

Include as much of the following information as possible:

- a clear description of the vulnerability;
- the affected client, backend service, rule set, Cloud Function or integration;
- the affected platform, such as Android, iOS, web or desktop;
- exact reproduction steps;
- the account type and permissions used during testing;
- the potential impact on confidentiality, integrity or availability;
- relevant screenshots, redacted logs or a minimal proof of concept;
- any suggested mitigation, if known.

Never include access tokens, API keys, private user content, unredacted personal data or credentials in a public issue.

## Responsible testing

When investigating a suspected vulnerability:

- use accounts and data that you control;
- stop once you have enough evidence to demonstrate the issue;
- do not access, modify, download, retain or disclose another user's data;
- do not attempt account takeover against real users;
- do not record or disrupt live voice rooms without permission;
- do not send spam, abusive content or large volumes of notifications;
- do not degrade service availability or perform denial-of-service testing;
- do not use social engineering, phishing or credential attacks;
- do not run broad automated scans against production without prior permission;
- do not publish exploit details before a fix or coordinated disclosure date is agreed.

If you accidentally encounter sensitive data, stop testing, do not retain or share the data, and describe the exposure in the private report without copying more information than necessary.

## Response process

We aim to:

- acknowledge a report within 5 business days;
- provide an initial assessment within 10 business days;
- share progress updates when additional investigation is required;
- correct confirmed vulnerabilities as soon as reasonably possible, based on severity and complexity.

A report may be accepted, declined or classified as informational after investigation. The reporter will receive an explanation whenever possible.

## Scope

This policy covers the YO Voice application, Firebase configuration and rules, Cloud Functions, browser test surface and integrations represented in this repository, together with the current production deployment.

Vulnerabilities that exist only in Firebase, Flutter, LiveKit or another unrelated third-party product should be reported to that product's maintainer, unless the issue is caused by YO Voice's integration or configuration.

Thank you for helping protect the YO Voice community.
