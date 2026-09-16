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
tencentcloud_secret_id = replace-me
tencentcloud_secret_key = replace-me

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

## Install With Cloudflare DNS

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

## Install With Tencent Cloud DNSPod

Cloudflare and Tencent Cloud DNSPod use different APIs for the DNS-01 challenge. Both installers use the same `config/proxies.conf` file, but read only their own credentials.

Create a Tencent Cloud CAM API key with DNSPod write permission. Add its values to `config/proxies.conf`:

```conf
tencentcloud_secret_id = your-secret-id
tencentcloud_secret_key = your-secret-key
```

Then run:

```sh
./providers/tencentcloud/install.sh
```

The Tencent Cloud installer creates an isolated Certbot environment at `/opt/auto-nginx-proxy-certbot`, writes credentials to `/etc/letsencrypt/tencentcloud.ini`, requests `domain` and `*.domain`, and enables a daily systemd renewal timer. It waits 120 seconds for DNSPod TXT propagation before validation.

Generate and sync proxy files as usual:

```sh
./generate.sh
./sync.sh
./reload.sh
```

Do not commit production credentials. For a private configuration file outside this repository, pass its path as the first argument to either installer and to `generate.sh`.

## Reload

Check nginx config and reload nginx:

```sh
./reload.sh
```
