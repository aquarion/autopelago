# \*arr stack on firth — design

## Goal

Replace FlexGet + Filebot (TV and movies only) with Sonarr, Radarr, Prowlarr and
Jellyseerr for requests-driven media management. Keep the existing
`haugene/transmission-openvpn` container and Jellyfin. Bring the currently
hand-managed VPN compose file under Ansible.

`hxck/arrsuite` is a curated link list, not a deployable stack; "the arr suite"
here means the apps above.

## Current state

- Compose project `vpn` at `/home/aquarion/docker/vpn/docker-compose.yml`
  (hand-managed, not in this repo), data in `/home/docker/vpn/`:
  `torrential` -> `/data`, `config` -> `/config`.
- Container runs as `PUID=114` (`jellyfin`) / `PGID=1004` (`medialibrary`).
- Network `vpn_default` is `172.22.0.0/16`; `LOCAL_NETWORK` is
  `172.16.0.0/16`, which does not cover it.
- `9091` is published on all interfaces.
- Filebot (`fn:amc`) hardlinks `transmission_complete` into
  `/home/medialibrary/Media`, then `sync_or_swim.sh` moves new episodes from
  `TV/<Show>` into whichever top-level dir already holds that show.
- Jellyfin, FlexGet and Filebot run on the host, not in Docker.
- Downloads and library are on the same filesystem.

## Design

### 1. Storage layout (hardlinks)

Hardlinks cannot cross mount points, so Sonarr/Radarr must see downloads and
library under one mount:

- Downloads move (a same-filesystem `mv`, so inodes are preserved) from
  `/home/docker/vpn/torrential` to `/home/medialibrary/torrents`.
- Transmission mounts `/home/medialibrary/torrents` as `/data`, exactly as
  before, so its container paths and bencoded resume state do not change.
- Sonarr and Radarr mount `/home/medialibrary` as `/data` and get a Remote Path
  Mapping (`transmission-openvpn`: `/data/` -> `/data/torrents/`) in their UI.
- Sonarr/Radarr download into `/data/arr/{tv,movies}` (Transmission's view),
  a sibling of `completed/`, so Filebot's `completed/` watcher never sees them.
- Rejected: mounting `/home` (exposes other apps' secrets); copy-imports
  (doubles disk for seeded files); re-rooting Transmission under `/data/torrents`
  (needs editing bencoded resume files).

### 2. Containers (project `vpn`)

| Service | Notes |
|---|---|
| `transmission-openvpn` | Existing. `LOCAL_NETWORK` -> `172.22.0.0/16`; publish `9091` on `127.0.0.1` only. |
| `sonarr`, `radarr`, `prowlarr` | `PUID=114`, `PGID=1004`; config under `/home/docker/vpn/config/<app>`. |
| `jellyseerr` | Talks to host Jellyfin, Sonarr, Radarr. Nginx vhost alongside the existing `jellyfin` one. |

The \*arrs reach Transmission at `transmission-openvpn:9091` over `vpn_default`.

### 3. Library mapping and `sync_or_swim`

`sync_or_swim` exists because Filebot lands everything in `TV/`. Sonarr supports
several root folders and a path per series, so shows are imported straight to
where they live and the script is no longer needed.

- **Sonarr roots** (allowlist, `TV` default): `TV`, `Drag`, `Star-Trek`,
  `Star-Wars`, `Taskmaster`, `Anime`. These are the dirs `sync_or_swim` routes
  into, plus `Star-Wars` (holds shows, no match in `TV/` at survey time) and
  `Anime` (series type "anime"; existing files adopted in place).
- **Radarr roots:** `Movies`, `Bond`, `Disney`, `Tolkien`.
- **Bazarr** (subtitles, replacing Filebot's `subtitles=en`) reads Sonarr and
  Radarr and writes next to the media.
- **Out of scope, untouched:** `Music`, `Radio`, `idents`, `iPlayer`, `Youtube`,
  `Kickstarted`. `Kickstarted` and `Youtube` are externally managed. Music and
  full Filebot removal are tracked in a separate GitHub issue.
  `get_iplayer` keeps handling iPlayer.
- `Star-Trek.orig` is a stray temp dir; excluded.
- Existing files are adopted via library import, not renamed. Sonarr's episode
  format is set to match `TV/{n}/S{s}/{s00e00} - {t}`.
- `sync_or_swim` is retired after import is verified. Its only other behaviour
  (skipping `Music`) is irrelevant once it is gone.

### 4. Ansible

New role `firth_media_stack` (host-specific naming), after `firth_docker`:

- The stack moves from `aquarion`'s home to `{{ docker_root }}/vpn` (the
  `firth_elasticsearch` pattern), owned by `jellyfin:docker`. `jellyfin` is
  already in the `docker` and `medialibrary` groups and matches `PUID=114`.
  Container config dirs are `jellyfin:medialibrary`; `/home/medialibrary/torrents`
  is `jellyfin:medialibrary` mode `2775` so `aquarion` and Filebot's
  `media_user` can still read and write it.
- Templates `docker-compose.yml` there.
- Filebot's cron fallback path in `organise_media_downloads` changes from
  `transmission_complete` to `transmission_complete/completed` to match its
  inotify watcher, so it never scans `arr/`.
- Runs it with `community.docker.docker_compose_v2` (same module as
  `firth_elasticsearch` and `firth_laravel_app`).
- All secrets (`OPENVPN_USERNAME` / `OPENVPN_PASSWORD` and any \*arr API keys
  the templates need) go in the existing
  `host_vars/firth.water.gkhs.net/media.vault.yml`.
- Compose-file change must be applied with no behaviour change first.

Removal tasks must be explicit (`state: absent`), per the repo rule that Ansible
does not garbage-collect: FlexGet role pieces, the Filebot amc
cron/inotify/`organise_media_downloads` path for TV/movies, and
`sync_or_swim` templates and cron.

### 5. Cutover order

1. Take over the compose file; `docker compose config` matches the running
   container; no restart needed beyond Ansible's own.
2. The VPN container is shut down for the duration (downtime accepted, which
   avoids inode/hardlink confusion mid-move). `mv` the torrent tree to
   `/home/medialibrary/torrents`, point the bind mount at it, bring the stack up.
   Update `transmission_complete` to the new host path so Filebot keeps working
   during the transition.
3. Add Prowlarr, Sonarr, Radarr, Jellyseerr; add root folders; library import.
4. Disable FlexGet and Filebot amc for TV/movies; remove `sync_or_swim`; add
   cleanup tasks.

### 6. Verification

- `docker compose config` diff before/after takeover.
- Hardlink test: same inode between `/data/torrents/x` and `/data/Media/...`.
- One Sonarr and one Radarr end-to-end grab, import, and appearance in Jellyfin.
- Sonarr/Radarr can reach Transmission (confirms `LOCAL_NETWORK`).
- `ansible-playbook --check --diff` clean on second run (idempotent).

## Open risks

- Torrent cleanup: Sonarr and Radarr remove their own torrents ("Remove
  Completed": only after import and once seed limits are met).
  `remove_completed_torrents` is changed to skip anything under `/data/arr/` and
  keeps handling manual torrents and Filebot's `completed/`.
- Prowlarr indexer traffic: egress via VPN or directly is undecided; defaults
  to direct.
- Port `9091` loopback-only breaks any remote use of the Transmission web UI;
  Tailscale-IP binding is the fallback.
