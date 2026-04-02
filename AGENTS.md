# IsoPod Development Log

## Overview

IsoPod provides an isolated Ubuntu KDE desktop environment running in Docker, designed for safe Claude Code development with full GUI access via browser.

## Architecture

### Container Setup

- **Base Image**: `lscr.io/linuxserver/webtop:ubuntu-kde`
- **Access**: Browser-based desktop at http://localhost:3000
- **Persistence**: Full system persistence via Docker volumes

### Volume Strategy

The key insight is mounting system directories as named volumes, which Docker initializes with the image contents on first run:

```yaml
volumes:
  - ubuntu-config:/config    # User home directory
  - ubuntu-usr:/usr          # apt packages, binaries
  - ubuntu-opt:/opt          # Optional software
  - ubuntu-var:/var          # apt database, logs
  - ubuntu-root:/root        # Root home
```

This allows:
- `docker compose down/up` without losing installed software
- Manual `apt install`, `pip install`, `npm install` all persist
- Only `docker compose down -v` removes data

### Project Mounting

Projects are mounted from a config file (`projects.conf`):

```
/path/to/project:include_git
```

- `include_git: true` - Mount entire project including .git
- `include_git: false` - Shadow .git with empty volume (safer for isolated work)

The `isopod.sh` script parses this config and generates `docker-compose.yml`.

## Components

### isopod.sh

Main control script with commands:
- `up` - Start container, generate compose if needed
- `down` - Stop container
- `setup` - Install dev tools (Python, Poetry, Claude CLI)
- `regenerate` - Rebuild compose from projects.conf

### setup-container.sh

Installs development environment inside container:
- Python 3.14 (via deadsnakes PPA)
- tkinter support
- Poetry (to /config/.local)
- Node.js 20
- Claude Code CLI

### projects.conf

User-specific project mounts. Gitignored to keep local paths private.

## Design Decisions

1. **Webtop over plain Docker**: Provides full KDE desktop accessible via browser, no VNC client needed

2. **Volume persistence over Dockerfile**: User wanted to install software manually and have it persist, rather than baking into image

3. **Config-driven mounts**: Allows multiple projects with per-project .git inclusion choice

4. **Generated docker-compose.yml**: Gitignored since it contains local paths; regenerated from projects.conf

## Usage Workflow

```bash
# First time setup
cp projects.conf.example projects.conf
# Edit projects.conf with your project paths
./isopod.sh up
./isopod.sh setup

# Daily use
./isopod.sh up
# Open http://localhost:3000
# Work in isolated environment
./isopod.sh down

# After editing projects.conf
./isopod.sh regenerate
./isopod.sh down && ./isopod.sh up
```

## Future Improvements

- [ ] Support for multiple desktop environments (XFCE, MATE)
- [ ] VNC access option for native client
- [ ] Backup/restore of volumes
- [ ] Pre-built image with tools installed
- [x] SSH access to container
