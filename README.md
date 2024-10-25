# Welcome to Solution Y for sonarr

ive been waiting, patiently, for the sonarr devs to wise up and implement this, but after dozens of closed issues and the ignored pleas of user, after user, it seems this matter will not resolve itself. 

idk if its unwillingness, a lack of ability, laziness or if **theyre being bought out by UseNet hosts and virus makers,** but the sonarr devs flat out refuse to allow us to automatically blocklist files based on failure or more importantly ...

## Blocklist Sonarr Downloads and automatically Redownload based on extensions 

### Quickstart
- Make a Directory for your config `mkdir -p /DockerData/SolutionY/sonarr`
- run the program to create initial config file 
```
docker run --rm \
  --hostname solution-y-sonarr --name solution-y-sonarr \
  -v /DockerData/SolutionY/sonarr:/opt/config \
  -e PUID=1000 \
  -e PGID=1000 \
  -e CronSchedule="*/1 * * * *" \
  ghcr.io/dabbingwowdevs/solution-y-sonarr:latest /opt/y.sh
```
- change host and apikey in /DockerData/SolutionY/sonarr/y.config

