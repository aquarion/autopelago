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

Hardlinks cannot cross mount points, so downloads must move under the media
root and every container mounts the same parent:

- Downloads: `/home/medialibrary/torrents` (was `/home/docker/vpn/torrential`).
- Every container mounts `/home/medialibrary` as `/data`:
  `/data/torrents`, `/data/Media/...`.
- Transmission's download/incomplete/watch dirs are set under `/data/torrents`.
- Rejected: mounting `/home` (exposes other apps' secrets); copy-imports
  (doubles disk for seeded files).

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
  `Star-Wars`, `Taskmaster`. These are the dirs `sync_or_swim` routes into,
  plus `Star-Wars`, which holds shows but had no match in `TV/` at survey time.
- **Radarr roots:** `Movies`, `Bond`, `Disney`, `Tolkien`.
- **Out of scope, untouched:** `Anime`, `Music`, `Radio`, `idents`, `iPlayer`,
  `Youtube`, `Kickstarted`. `Kickstarted` and `Youtube` are externally
  managed.
  Filebot and `get_iplayer` keep handling Anime and iPlayer.
- `Star-Trek.orig` is a stray temp dir; excluded.
- Existing files are adopted via library import, not renamed. Sonarr's episode
  format is set to match `TV/{n}/S{s}/{s00e00} - {t}`.
- `sync_or_swim` is retired after import is verified. Its only other behaviour
  (skipping `Music`) is irrelevant once it is gone.

### 4. Ansible

New role `firth_media_stack` (host-specific naming), after `firth_docker`:

- Creates `/home/aquarion/docker/vpn` and templates `docker-compose.yml`.
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
   avoids inode/hardlink confusion mid-move). Move torrents to
   `/home/medialibrary/torrents`, switch download dirs, bring the stack up.
   Update `transmission_complete` so Filebot keeps working during the
   transition.
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

- Torrents mid-seed when `torrential` moves: Transmission needs the new
  locations set, not a plain restart. With the container stopped during the
  move, resume state in `/config` must still be repointed.
- Prowlarr indexer traffic: egress via VPN or directly is undecided; defaults
  to direct.
- Port `9091` loopback-only breaks any remote use of the Transmission web UI;
  Tailscale-IP binding is the fallback.
