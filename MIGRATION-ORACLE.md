# Moving Roamwise from AWS to Oracle Cloud (Always Free)

Layout on the two free **VM.Standard.E2.1.Micro** VMs (1 GB RAM each):

| VM | Runs | Public ports |
|---|---|---|
| `roamwise-app` | Caddy + Angular SSR | 80, 443 |
| `roamwise-api` | Spring Boot + Postgres + Redis | none (8080 only from inside the VCN) |

Images are built by GitHub Actions and pulled from `ghcr.io`, because 1 GB is too little to build on the server.
`COMPOSE_PROFILES` in each VM's `.env` picks which services run. (On a single big VM use `COMPOSE_PROFILES=app,api`.)

## 1. Back up the database (on EC2)

```bash
cd ~/roamwise-infra
docker run --rm -e PGPASSWORD="$(grep '^DB_PASSWORD=' .env | cut -d= -f2-)" postgres:18-alpine \
  pg_dump -Fc -h roamwise.cvwuekisyde6.eu-north-1.rds.amazonaws.com -U postgres -d roamwise > ~/roamwise.dump
ls -lh ~/roamwise.dump
```

Copy `~/roamwise.dump` and `~/roamwise-infra/.env` to your laptop with `scp`.

## 2. Create the two VMs (Oracle console → Compute → Instances → Create)

For each of `roamwise-app` and `roamwise-api`:
- Image **Canonical Ubuntu 24.04**, shape **VM.Standard.E2.1.Micro**, Shielded instance off
- Networking: existing VCN, **public subnet-roamwise**, public IPv4 **on**
- SSH key: paste the same public key for both

Note each VM's **public IP** and the api VM's **private IP** (instance page → Primary VNIC).

Security list (public subnet → Default Security List), add ingress:
- `0.0.0.0/0` TCP 80 and 443 (already done)
- `10.0.0.0/16` TCP **8080** (app VM → api VM)

## 3. Prepare both VMs

```bash
# Oracle's Ubuntu image blocks everything except SSH at the OS level
sudo iptables -I INPUT 6 -p tcp -m multiport --dports 80,443,8080 -j ACCEPT
sudo netfilter-persistent save

# 1 GB RAM needs swap
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker ubuntu
exit   # log back in

git clone https://github.com/subham22/roamwise-infra.git
cd roamwise-infra && git checkout oracle-migration && cd ~   # main once the PR is merged
```

Copy your `.env` into `~/roamwise-infra/.env` on **both** VMs, then append:

**api VM**
```
COMPOSE_PROFILES=api
BACKEND_BIND=<api private IP>
JAVA_OPTS=-Xmx320m -XX:+UseSerialGC -Xss512k -XX:MaxMetaspaceSize=160m
```

**app VM**
```
COMPOSE_PROFILES=app
BACKEND_UPSTREAM=<api private IP>:8080
NODE_OPTS=--max-old-space-size=256
```

## 4. Restore the database (api VM), before the backend ever starts

The backend must not start on an empty database first (it would create empty tables and the restore would clash).

```bash
cd ~/roamwise-infra
docker compose up -d postgres
docker compose exec -T postgres pg_restore -U postgres -d roamwise --no-owner --no-privileges < ~/roamwise.dump
docker compose exec postgres psql -U postgres -d roamwise -c "select count(*) from guide;"
```

## 5. Deploy and cut over

1. GitHub secrets: in **roamwise-backend** set `EC2_HOST` = api VM public IP; in **roamwise-frontend** set `EC2_HOST` = app VM public IP. Both: `EC2_USER` = `ubuntu`, `EC2_SSH_KEY` = the Oracle private key.
2. **Only now** merge the infra PR, then the backend and frontend PRs. Each merge builds its image, pushes it to ghcr and runs `docker compose up -d` on its VM. (Merged while the secrets still pointed at EC2, they would deploy onto EC2.)
3. Check from the app VM: `curl -s http://<api private IP>:8080/api/guides | head -c 200`
4. DNS: point `roamwise.live` and `www` A records at the **app VM** public IP. Caddy fetches certificates by itself.
5. If the Google Places key is IP-restricted, add the **api VM** public IP.

## 6. Nightly backup (api VM)

```bash
mkdir -p ~/backups && crontab -e
```
```
0 3 * * * cd ~/roamwise-infra && docker compose exec -T postgres pg_dump -Fc -U postgres roamwise > ~/backups/roamwise-$(date +\%F).dump && find ~/backups -name '*.dump' -mtime +7 -delete
```

## 7. Shut down AWS (after 2–3 good days)

Delete EC2, the Elastic IP, RDS, ElastiCache and snapshots, then check Billing the next day.
