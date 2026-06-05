# auto-nginx-proxy

Generate nginx reverse proxy config from simple domain-to-upstream mappings.

## Usage

```sh
./generate.sh
```

Default input:

```sh
config/proxies.conf
```

Default template:

```sh
templates/nginx.conf.tpl
```

Default output directory:

```sh
dist
```

You can also pass custom paths:

```sh
./generate.sh config/proxies.conf templates/nginx.conf.tpl /etc/nginx/conf.d
```

## Config

Edit `config/proxies.conf`:

```conf
domain = example.com
email = admin@example.com
cloudflare_api_token = replace-me

taskmate -> 192.0.2.10:29202
abc -> 127.0.0.1:8080
```

Mappings only need the subdomain prefix. For example, `taskmate -> 192.0.2.10:29202` generates `taskmate.example.com`.

Each mapping generates one file named exactly after the subdomain, without a suffix:

```sh
dist/taskmate
dist/abc
```

## Template

Edit `templates/nginx.conf.tpl`.

The template must contain these variables:

```conf
{{DOMAIN}}
{{UPSTREAM}}
{{CERT_DOMAIN}}
```

For each mapping, the generator replaces `{{DOMAIN}}` with the full subdomain, `{{UPSTREAM}}` with `ip:port`, and `{{CERT_DOMAIN}}` with the configured `domain`.

The cleaned main nginx config template is also included at:

```sh
templates/nginx.conf
```

Then test and reload nginx:

```sh
./reload.sh
```

## Sync

Copy generated files to `/etc/nginx/sites-enabled`:

```sh
./generate.sh
./sync.sh
```

Default sync target:

```sh
/etc/nginx/sites-enabled
```

Custom paths:

```sh
./sync.sh dist /etc/nginx/sites-enabled
```

## Install

Install nginx, install certbot with the Cloudflare DNS plugin, write Cloudflare credentials, request a Let’s Encrypt certificate for `domain` and `*.domain`, enable nginx on boot, replace `/etc/nginx/nginx.conf` with `templates/nginx.conf`, check config, and start nginx:

```sh
./install.sh
```

The Cloudflare token is written to:

```sh
/etc/letsencrypt/cloudflare.ini
```

The old main config is backed up as:

```sh
/etc/nginx/nginx.conf.bak.YYYYMMDDHHMMSS
```

## Reload

Check nginx config and reload nginx:

```sh
./reload.sh
```
