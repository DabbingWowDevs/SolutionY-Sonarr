# Welcome to Solution Y for sonarr

ive been waiting, patiently, for the sonarr devs to wise up and implement this, but after dozens of closed issues and the ignored pleas of user, after user, it seems this matter will not resolve itself. 

idk if its unwillingness, a lack of ability, laziness or if **theyre being bought out by UseNet hosts and virus makers,** but the sonarr devs flat out refuse to allow us to automatically blocklist files based on failure or more importantly ...

## Blocklist Sonarr Downloads and automatically Redownload based on extensions  

(or by state, status, or error messege)

### Quickstart
- run the program to create initial config files 
```
docker run --rm \
  --name solution-y-sonarr \
  -v /DockerData/SolutionY/sonarr:/opt/config \
  ghcr.io/dabbingwowdevs/solution-y-sonarr:latest /opt/y.sh
```
- fix permissions for your config `sudo chown -R $(id -u $(whoami)):$(id -g $(whoami)) /DockerData/SolutionY`
- change apikey in /DockerData/SolutionY/sonarr/y.config (or whatever youve changed the path to)
- run normally or add to compose
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
    container_name: "solution-y-sonarr"
    environment:
      - "QueueCheckWaitInMinutes=5"
      - "debug=0"
      - "quiet=1"
    image: "ghcr.io/dabbingwowdevs/solution-y-sonarr:latest"
    volumes:
      - "/DockerData/SolutionY/sonarr:/opt/config"
```
