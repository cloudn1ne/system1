# SIEM Log Preanalysis — curl samples

These sample `curl` calls exercise the Laya `/v1/systemone` endpoint for **SIEM log preanalysis** — triaging raw log lines *before* they hit deep analytics. Each call sends a `state` (the log line, as plain text or structured fields) plus typed `questions`, and gets back typed answers with calibrated probabilities in one forward pass.

Base URL: `http://localhost:8000` (override the port with `PORT` / `make test`).

## 1. Single-question triage (is this log line suspicious?)

```bash
curl -s localhost:8000/v1/systemone -H 'Content-Type: application/json' -d '{
  "state": {
    "source": "windows.eventlog/4625",
    "message": "An account failed to log on. Subject: USER1. Logon type 3. Source: 10.20.1.44. 14 failed attempts in the last 2 minutes."
  },
  "questions": {
    "suspicious": {
      "type": "noul",
      "instructions": "Is this a sign of a brute-force or credential-stuffing attack?"
    }
  }
}'
```

```json
{"answers": {"suspicious": {"noul": 0.97}}, "routing": {"model": "english"}}
```

## 2. Multi-question triage in one call (severity + decision)

```bash
curl -s localhost:8000/v1/systemone -H 'Content-Type: application/json' -d '{
  "state": {
    "timestamp": "2026-09-23T19:12:33Z",
    "vendor": "crowdstrike",
    "detection": "Potential privilege escalation: svchost.exe spawned powershell.exe -enc with command line containing 'whoami /priv'."
  },
  "questions": {
    "severity": {
      "type": "score",
      "instructions": "Rate the severity of this event.",
      "criteria": ["informational", "low", "medium", "high", "critical"]
    },
    "is_attack": {
      "type": "noul",
      "instructions": "Does this event indicate active malicious activity?"
    },
    "escalate": {
      "type": "noul",
      "instructions": "Should this be escalated to a human analyst now?"
    }
  }
}'
```

## 3. MITRE ATT&CK technique classification (choice with criteria)

```bash
curl -s localhost:8000/v1/systemone -H 'Content-Type: application/json' -d '{
  "state": "FIREWALL: blocked outbound connection from 10.30.2.7 to 185.220.101.44:4444 (TLS). Repeated every 5s for 10 minutes. Destination is on a known blocklist.",
  "questions": {
    "category": {
      "type": "choice",
      "instructions": "Classify the likely MITRE ATT&CK tactic of this outbound beaconing.",
      "criteria": {
        "command-and-control": "regular outbound callbacks to a suspicious external host",
        "exfiltration": "bulk transfer of internal data to an external destination",
        "lateral-movement": "access attempts to other internal hosts",
        "reconnaissance": "scanning or probing of internal or external targets",
        "benign": "normal expected network behaviour"
      }
    },
    "act": {
      "type": "noul",
      "instructions": "Should the source host be isolated automatically?"
    }
  }
}'
```

## 4. Long-structured JSON event (email / phishing preanalysis)

```bash
curl -s localhost:8000/v1/systemone -H 'Content-Type: application/json' -d '{
  "state": {
    "from": "invoice@external-notice-2.top",
    "subject": "URGENT: your invoice is overdue",
    "body": "Your account will be suspended unless you click this link within 24h to confirm your billing details.",
    "has_link": true,
    "link_domain_age_days": 1
  },
  "questions": {
    "phishing": {
      "type": "noul",
      "instructions": "Is this a phishing or business-email-compromise attempt?"
    },
    "confidence": {
      "type": "score",
      "instructions": "How confident are you that this email is malicious?",
      "criteria": ["low", "medium", "high"]
    }
  }
}'
```

## 5. Using `make test` as the local smoke check

```bash
make test          # hits localhost:8000 with a simple triage sample
make test PORT=8001
```

## Notes

- **Question shapes** follow the Jev API: `noul` (yes/no probability), `score` (ordinal rating), `choice` (classification against `criteria`). `criteria` may also be given as a list.
- The `state` can be a raw string, structured JSON fields, or both — Laya reads the relevant text.
- Unknown fields are ignored; a malformed question returns `422` naming the problem.
- With `LAYA_API_KEY` set, add `-H "Authorization: Bearer <key>"` to every request.
- The model ships **over-confident by default** (known laya calibration note): for production gating, calibrate per (question-type, option-count) or treat probabilities as relative rankings.