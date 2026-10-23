# duncfrastructure

Scripts I run on my Laravel Forge servers.

## Installation

Add this to a Forge recipe, run as `root`:

```sh
git clone https://github.com/duncanmcclean/duncfrastructure.git /opt/duncfrastructure
/opt/duncfrastructure/bootstrap
```

The `bootstrap` script installs zsh and Oh My Zsh for the `forge` user, makes zsh its default shell and loads the [aliases](zsh/aliases.zsh). It's safe to run again.

## Firewall

Every script syncs [ufw](https://help.ubuntu.com/community/UFW) rules, so they're safe to run repeatedly. Rules added by these scripts are tagged with a `duncfrastructure:*` comment, which is how they know which rules they own.

The IP lists are validated before anything is changed. If a list can't be fetched, or contains anything that isn't an IP address, the script bails without touching the firewall. It also bails if it would remove more than half of its existing rules. If that happens because Forge or Cloudflare genuinely dropped a load of IPs, delete the old rules by hand and run the script again.

Prefix any script with `DRY_RUN=1` to see what it would change.

Forge doesn't notice firewall changes made outside of it. Sync the firewall rules in Forge afterwards to see them.

### `firewall/allow-forge-ssh`

Allows SSH (port 22) from [Forge's IP addresses](https://forge.laravel.com/ips-v4.txt), then removes the public SSH rule.

> [!WARNING]
> Once the public rule is removed, you can only SSH in from Forge's IPs. Add a firewall rule in Forge for anywhere else you SSH in from, like a jump box. The scripts never touch rules scoped to an IP address that were added in Forge.

### `firewall/allow-cloudflare-web`

Allows HTTP and HTTPS (ports 80 and 443) from [Cloudflare's IP addresses](https://www.cloudflare.com/ips/), then removes the public HTTP and HTTPS rules.

> [!WARNING]
> Every site on the server must be proxied through Cloudflare. Anything that isn't will become unreachable.

### `firewall/block-databases`

Removes public rules for MySQL (3306) and PostgreSQL (5432), so they can only be reached via an SSH tunnel. Rules scoped to specific IPs, like a separate app server, are left alone.

Unlike the other scripts, there's no IP list to keep up to date, so it only needs running once when setting up a server.

## Setting up a new server

1. Run the recipe to clone this repository.
2. In Forge, add a firewall rule allowing SSH (port 22) from your jump box.
3. SSH into the server and do a dry run of each script, to make sure nothing unexpected will be removed:
    ```sh
    DRY_RUN=1 /opt/duncfrastructure/firewall/allow-forge-ssh
    DRY_RUN=1 /opt/duncfrastructure/firewall/allow-cloudflare-web
    DRY_RUN=1 /opt/duncfrastructure/firewall/block-databases
    ```
4. Run them for real, without `DRY_RUN`.
5. Add these scheduled jobs in Forge, run as `root`:

    | Command | Frequency |
    | --- | --- |
    | `/opt/duncfrastructure/firewall/allow-forge-ssh` | Nightly |
    | `/opt/duncfrastructure/firewall/allow-cloudflare-web` | Nightly |

## Updating

Servers don't pull changes to this repository automatically. To update them, add this to a Forge recipe, run as `root`:

```sh
git -C /opt/duncfrastructure pull --ff-only
```
