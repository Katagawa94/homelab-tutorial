# Verschlüsselte Secrets (Sealed Secrets)

Hier liegen **nur** mit `kubeseal` verschlüsselte Secrets (`kind: SealedSecret`), sortiert nach Namespace:

```
secrets/
├── argocd/
│   └── repo-homelab.yaml     (nur bei privatem Repository)
└── tailscale/
    └── operator-oauth.yaml
```

⚠️ Niemals ein normales `kind: Secret` hier ablegen! Wie das Verschlüsseln geht, steht in Kapitel 14.
