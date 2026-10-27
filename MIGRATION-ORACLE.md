# Moving Roamwise from AWS to Oracle Cloud (Always Free)

The new `docker-compose.yml` runs Postgres and Redis as containers next to the app,
so RDS and ElastiCache are no longer needed. Images are built on the server, so the
ARM VM builds ARM images automatically. No workflow changes are needed.

## 1. Back up the database (on the EC2 box)

```bash
cd ~/roamwise-infra
docker run --rm -e PGPASSWORD="$(grep '^DB_PASSWORD=' .env | cut -d= -f2-)" postgres:17-alpine \
  pg_dump -Fc -h roamwise.cvwuekisyde6.eu-north-1.rds.amazonaws.com -U postgres -d roamwise > ~/roamwise.dump
ls -lh ~/roamwise.dump   # should be a few MB, not 0 bytes
```

If it fails with a "server version mismatch", use the image tag that matches the RDS major version.

From your laptop (PowerShell), copy the dump and the `.env` down:

```powershell
scp -i roamwise.pem ubuntu@<EC2_IP>:~/roamwise.dump .
scp -i roamwise.pem ubuntu@<EC2_IP>:~/roamwise-infra/.env .
```

## 2. Create the Oracle VM

- Shape: **VM.Standard.A1.Flex** (4 OCPU / 24 GB; use 2/12 if you get "out of capacity"). Image: **Ubuntu 24.04**. Upload your SSH public key.
- VCN → Security List → add ingress rules for TCP **80** and **443** from `0.0.0.0/0`.

## 3. Prepare the VM

```bash
# Oracle's Ubuntu image blocks every port except 22 at the OS level too
sudo iptables -I INPUT 6 -p tcp -m multiport --dports 80,443 -j ACCEPT
sudo netfilter-persistent save

curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker ubuntu
exit   # log back in so the docker group applies

cd ~
git clone https://github.com/subham22/roamwise-backend.git
git clone https://github.com/subham22/roamwise-frontend.git
git clone https://github.com/subham22/roamwise-infra.git
```

From your laptop:

```powershell
scp -i <oracle-key> roamwise.dump .env ubuntu@<ORACLE_IP>:~/
```

On the VM: `mv ~/.env ~/roamwise-infra/.env`

## 4. Restore and start

```bash
cd ~/roamwise-infra
docker compose up -d postgres
docker compose exec -T postgres pg_restore -U postgres -d roamwise --no-owner --no-privileges < ~/roamwise.dump
docker compose up -d --build
docker compose ps
```

Check the backend before switching DNS:

```bash
docker compose exec frontend wget -qO- http://backend:8080/api/guides | head -c 300
```

## 5. Cut over

1. Point the DNS **A records** for `roamwise.live` and `www.roamwise.live` at the Oracle IP. Caddy issues the certificates by itself once DNS resolves.
2. In GitHub, update the secrets in **both** `roamwise-backend` and `roamwise-frontend`: `EC2_HOST` = Oracle IP, `EC2_SSH_KEY` = Oracle private key, `EC2_USER` = `ubuntu`.
3. If the Google Places key is restricted by IP, swap in the Oracle IP.

## 6. Nightly backup (keeps 7 days)

`crontab -e` and add:

```
0 3 * * * cd ~/roamwise-infra && docker compose exec -T postgres pg_dump -Fc -U postgres roamwise > ~/backups/roamwise-$(date +\%F).dump && find ~/backups -name '*.dump' -mtime +7 -delete
```

(`mkdir ~/backups` first.) Copy one to your laptop now and then. The disk is the only copy.

## 7. Shut down AWS (after 2–3 good days)

Delete the EC2 instance, the **Elastic IP**, RDS, ElastiCache and any snapshots, then check Billing the next day.
