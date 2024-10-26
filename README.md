# Welcome to Solution Y for sonarr

< redacted out of a modicum of respect for one person >

sonarr devs [flat out refuse to even consider implementing](https://github.com/Sonarr/Sonarr/issues/3709#issuecomment-640946646) this feature so i have for myself


## Blocklist Sonarr Downloads and automatically Redownload based on extensions

(or by state, status, or error messege)

made because sonarr is a huge security risk; softwre that automatically downloads files with random extensions and refuses to handle them afterwards. c'mon.

### so heres my quick and dirty solution i might clean up later

By default, this will REDOWNLOAD and BLOCKLIST queue items that are 60 mins stale based on these (configurable) settings, every 5 minutes.

-   Error messege: "The download is stalled with no connections"
-   Extensions: zipx, lnk, exe, bat, arj
-   status messege: "One or more episodes expected in this release were not imported or missing from the release"
-   status: "warning"
-   states: "importBlocked"

you can configure in the config folder, the filters are line-separated.

### Quickstart

-   run the program to create initial config files

```
docker run --rm \
  --name solution-y-sonarr \
  -v /DockerData/SolutionY/sonarr:/opt/config \
  ghcr.io/dabbingwowdevs/solution-y-sonarr:latest /opt/y.sh
```

-   fix permissions for your config `sudo chown -R $(id -u $(whoami)):$(id -g $(whoami)) /DockerData/SolutionY`
-   change apikey in /DockerData/SolutionY/sonarr/y.config (or whatever youve changed the path to)
-   run normally or add to compose

### runline

```
docker run -d \
  --name solution-y-sonarr \
  --network container:sonarr \
  -v /DockerData/SolutionY/sonarr:/opt/config \
  -e QueueCheckWaitInMinutes=5 \
  -e quiet=1 \
  ghcr.io/dabbingwowdevs/solution-y-sonarr:latest
```

### compose

```
 services:
  ...
  sonarr
  ...
  solution-y-sonarr:
    depends_on:
      sonarr:
        condition: service_started
    network_mode: "service:sonarr"
    container_name: "solution-y-sonarr"
    environment:
      - "QueueCheckWaitInMinutes=5"
      - "debug=0"
      - "quiet=1"
    image: "ghcr.io/dabbingwowdevs/solution-y-sonarr:latest"
    volumes:
      - "/DockerData/SolutionY/sonarr:/opt/config"
```
