# Aktive Applications

Argo CD rollt **jede YAML-Datei in diesem Ordner** aus (über die Application `root`, siehe
[`../bootstrap/root.yaml`](../bootstrap/root.yaml)).

Eine App aktivieren:

```bash
cp kubernetes/katalog/<app>.yaml kubernetes/aktiv/
git add kubernetes/aktiv/<app>.yaml
git commit -m "<app> aktivieren"
git push
```

Eine App deaktivieren: Datei hier löschen, committen, pushen. Die Application verschwindet,
die von ihr angelegten Kubernetes-Objekte bleiben aber stehen (siehe Kapitel 13).
