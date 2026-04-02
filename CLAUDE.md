# Instructions for IsoPod

## Project Overview

IsoPod is a Docker-based isolated Ubuntu desktop environment for Claude development. It provides a full KDE desktop accessible via browser with persistent storage.

## Key Files

- `isopod.sh` - Main control script (all commands in one file)
- `scripts/setup-container.sh` - Dev tools installer run inside container
- `projects.conf` - User's project mount configuration (gitignored)
- `projects.conf.example` - Template for new users
- `docker-compose.yml` - Generated file (gitignored)

## Commands

```bash
./isopod.sh up              # Start container
./isopod.sh down            # Stop container
./isopod.sh restart         # Rebuild container with current config
./isopod.sh setup           # Install Python/Poetry/AI tools
./isopod.sh browser         # Open desktop in browser
./isopod.sh regenerate      # Rebuild compose from projects.conf
./isopod.sh claude          # Launch AI CLI
./isopod.sh bash            # Bash shell in project
./isopod.sh code            # VS Code remote
./isopod.sh windsurf        # Windsurf remote
./isopod.sh arch            # Show current CPU architecture
./isopod.sh arch amd64      # Switch to amd64 emulation
./isopod.sh arch native     # Switch to native (default)
```

## Port Mappings

| Container | Host (native) | Host (amd64) | Service |
|-----------|---------------|--------------|---------|
| 3000 | 3000 | 3100 | Desktop (noVNC) |
| 22 | 2222 | 2322 | SSH |
| 8000-8999 | 9000-9999 | 10000-10999 | All 8xxx ports |
| 3001 | 3010 | 3110 | Node.js |
| 5000 | 5010 | 5110 | Flask |

## Important Notes

### File Generation
- `docker-compose.yml` is auto-generated from `projects.conf`
- Never edit docker-compose.yml directly; edit projects.conf and regenerate

### Persistence
- All volumes persist across down/up cycles
- Only `docker compose down -v` destroys data
- Installed software (apt, pip, npm) persists
- Browser configs (Chrome, Chromium) have dedicated volumes
- VS Code settings and extensions have dedicated volumes
- Config changes only apply after successful container rebuild (checksum-based)

### projects.conf Format (TOML)
```toml
# Global settings
[Settings]
screenshots = ~/Documents/Screenshots  # Optional: mounted at /screenshots

# Projects
[ProjectName]
path = /full/path/to/project
git = true|false
chrome = true|false

# Example:
[MyApp]
path = /Users/someone/projects/MyApp
git = false
chrome = true
```

- `git = true` - Include .git folder (for commits/pushes)
- `chrome = true` - Enable Chrome MCP when launching Claude
- `screenshots` - Host directory mounted read-only at `/screenshots`

Note: Old format (`/path:bool`) is auto-migrated on first use.

### Container Details
- Image: `lscr.io/linuxserver/webtop:ubuntu-kde`
- Desktop URL: http://localhost:3000
- Home directory inside container: `/config`
- Projects mount to: `/projects/<folder_name>`

### CPU Architecture
Two independent environments that can run in parallel:

- **native** (default): Uses host CPU, faster performance
  - Container: `iso-pod-ubuntu`
  - Ports: 3000, 2222, 9000-9999, 3010, 5010
  - Compose: `docker-compose.yml`

- **amd64**: Emulates x86_64 via Docker's QEMU
  - Container: `iso-pod-ubuntu-amd64`
  - Ports: 3100, 2322, 10000-10999, 3110, 5110
  - Compose: `docker-compose-amd64.yml`

Setting stored in `.arch` file. Use `isopod arch` to see status of both.
Setup runs automatically on first use of each environment.

## When Modifying

### Adding Features to isopod.sh
- Keep POSIX-compatible bash
- Update help text in `cmd_help()`
- Add case in main switch at bottom
- Test with both new and existing setups

### Changing scripts/setup-container.sh
- Script runs as root inside container
- Poetry installs to `/config/.local/bin`
- Consider idempotency (script may run multiple times)

### Volume/Port Changes
- Config changes auto-apply on next command (container auto-restarts)
- Adding new volumes requires `docker compose down -v` to take effect
- Update port mappings in `generate_compose()` function
- Document changes in README.md

## Testing Changes

```bash
# Full reset test
./isopod.sh down
docker compose -f docker-compose.yml down -v  # Remove volumes
./isopod.sh up
./isopod.sh setup
# Verify tools installed

# Persistence test
./isopod.sh down
./isopod.sh up
docker exec iso-pod-ubuntu python3.14 --version  # Should work
```

## Don't Commit

These files are gitignored and contain user-specific settings:
- `projects.conf`
- `docker-compose.yml`
- `docker-compose-amd64.yml`
- `.config_checksum`
- `.config_checksum_amd64`
- `.setup_native`
- `.setup_amd64`
- `.arch`

## Documentation

Keep `README.md` in sync with any user-facing changes (commands, features, behavior). The README should stay concise and focused on usage—implementation details belong in CLAUDE.md.
