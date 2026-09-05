# pbs-immutable-offsite

Drugi, trwały, tylko-do-odczytu datastore w Proxmox Backup Server, wskazujący
wprost na offsite (np. Hetzner Storage Box), obok normalnego lokalnego
datastore. Po co: żeby odtworzyć backup z offsite dało się zrobić jednym
kliknięciem w GUI PBS (Restore), bez pamiętania procedury "ściągnij rsync,
podepnij, odtwórz" i bez ryzyka, że PBS kiedykolwiek coś zapisze na offsite.

## Problem, który to rozwiązuje

PBS trzyma dane jako chunk-store (deduplikowane bloki + indeksy). Standardowa
architektura 3-2-1 robi lokalny backup i osobno kopiuje go (np. rsyncem) na
zewnętrzny storage. To dobre dla bezpieczeństwa, ale oznacza, że odtworzenie
z offsite po katastrofie wymaga pamiętania nietrywialnej procedury.

Naiwne rozwiązanie — zamontowanie offsite wprost jako datastore PBS — nie
działa z dwóch powodów:

1. **PBS przy każdej operacji (nawet samym listowaniu) próbuje otworzyć plik
   `.lock` do zapisu** (`open(..., O_RDWR|O_CREAT)`), więc czysty
   read-only mount kończy się błędem "Read-only file system" nawet dla
   odczytu.
2. Naturalna próba obejścia tego przez `overlayfs` (warstwa zapisu nad
   read-only mountem) **psuje wskaźnik zajętości miejsca** — `df`/`statfs`
   na overlayfs zawsze odpowiada stanem warstwy zapisu, nigdy nie licząc
   realnej zawartości warstwy źródłowej. Nie da się tego skonfigurować
   inaczej, to ograniczenie jądra Linuksa.

## Rozwiązanie

Zamiast overlaya na całym drzewie — chirurgiczna podmiana **jednego pliku**:

1. **Na hoście**: czysty `sshfs -o ro` montujący offsite. Żadnego overlay.
   Dzięki temu `df` faktycznie pyta serwer SFTP o prawdziwe zajęcie miejsca
   (sprawdzone: Storage Box odpowiada poprawnie przez rozszerzenie
   `statvfs@openssh.com`).
2. **Wewnątrz kontenera PBS**: osobna usługa podmienia `.lock` lokalnym,
   zapisywalnym plikiem przez `mount --bind`. To jedyny plik wymagający
   zapisu — reszta (wszystkie dane) to czyste odczyty z offsite.

### Dlaczego dwie warstwy (host + kontener)?

Bind-mount `.lock` zrobiony na hoście **nie propaguje się** do wnętrza
kontenera LXC, jeśli mountpoint kontenera (`mp`) jest podpięty jako zwykły,
nierekurencyjny `mount --bind` (tak robi to domyślnie Proxmox) — a taki bind
nie pokazuje mountów dorobionych później (ani wcześniej) na tej samej
ścieżce na hoście. Dlatego podmiana `.lock` musi się odbyć osobno, w
mount-namespace kontenera, nie hosta.

## Instalacja

Zakłada Proxmox VE + PBS uruchomiony w uprzywilejowanym kontenerze LXC oraz
Hetzner Storage Box (lub inny serwer SFTP) jako cel rsync z istniejącymi
danymi PBS.

**Na hoście PVE:**

1. `apt install sshfs`
2. Skopiuj `host/immutable-backup-mount.sh` do `/usr/local/bin/`, ustaw
   `chmod +x`, podmień `STORAGEBOX_USER` i `SSH_KEY` na swoje wartości.
3. Skopiuj `host/immutable-backup.service` do `/etc/systemd/system/`,
   podmień `CTID` w `Before=pve-container@CTID.service` na ID kontenera PBS.
4. `systemctl daemon-reload && systemctl enable --now immutable-backup.service`

**Wewnątrz kontenera PBS** (`pct exec <CTID> -- bash`):

1. Skopiuj `container/immutable-backup-lock-shim.sh` do `/usr/local/bin/`,
   `chmod +x`.
2. Skopiuj `container/immutable-backup-lock-shim.service` do
   `/etc/systemd/system/`.
3. `systemctl daemon-reload && systemctl enable --now immutable-backup-lock-shim.service`

**Rejestracja datastore w PBS** — ręczny wpis w
`/etc/proxmox-backup/datastore.cfg` (komenda `datastore create` odmawia,
bo wymaga pustego katalogu, a tu już są dane):

```
datastore: Immutable-backup
	path /mnt/immutable-backup
	comment Read-only mirror offsite (nie modyfikuje zrodla)
```

Potem `systemctl reload-or-restart proxmox-backup-proxy proxmox-backup`
wewnątrz kontenera, żeby PBS podjął nowy wpis.

## Ograniczenia

- Zakłada, że host PVE żyje. Nie zastępuje procedury pełnej katastrofy
  (utrata całego hypervisora) — do tego nadal potrzebny klucz szyfrowania
  datastore z kopii offline.
- Jeśli PBS w przyszłej wersji zmieni nazwę/ścieżkę pliku blokady albo
  zacznie zapisywać coś jeszcze przy starcie datastore, trzeba powtórzyć
  diagnozę (`strace -f -p <pid proxmox-backup-proxy> -e trace=openat`
  podczas żywego zapytania do API) i dopisać analogiczny shim.

## Licencja

MIT — patrz [LICENSE](LICENSE).
