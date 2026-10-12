# Verschlüsselte Secrets (Sealed Secrets)

Hier liegen **nur** mit `kubeseal` verschlüsselte Secrets (`kind: SealedSecret`), sortiert nach Namespace:

```
secrets/
├── argocd/
│   └── repo-homelab.yaml       (nur bei privatem Repository)
├── tailscale/
│   └── operator-oauth.yaml     (Kapitel 12)
├── nextcloud/
│   └── nextcloud-secrets.yaml  (Kapitel 14)
├── pihole/
│   └── pihole-secrets.yaml     (Kapitel 15)
├── media/
│   └── gluetun-protonvpn.yaml  (Kapitel 21)
├── homepage/
│   └── homepage-keys.yaml      (Kapitel 25)
├── immich/
│   └── immich-db.yaml          (Kapitel 26)
├── paperless/
│   └── paperless-secrets.yaml  (Kapitel 27)
├── backup/
│   └── restic-backup.yaml      (Kapitel 29)
└── monitoring/
    └── grafana-admin.yaml      (Kapitel 33)
```

⚠️ Niemals ein normales `kind: Secret` hier ablegen! Wie das Verschlüsseln geht, steht in Kapitel 12.
