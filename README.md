# Welcome to Solution Y for sonarr

After numerous discussions where mitigation was discussed with me, and solutions proposed that would accomadate ~~my~~ prowlarr's shitty trackers, I decided I would "write" (jippity - GPT) (lmao is that how you write sonarr?) a script. FOSS isn't meant to have pull requests that improve software, but instead new repositories with hacky scripts that have READMEs that disrespect the entire FOSS project they rely on!

But I'm not just a script, with every script comes a monologue and compulsive committing to the README one line at a time. This is _completely_ necessary as a commit history of repeated "Update README.md" is the only way I can _REALLY_ let those pesky devoted FOSS developers who wont solve my problem for me know that I'm _SUPER_ mad! GRRR!!!

I really can't understand how people working for free in their spare time, who I am trying to siphon donations off of would [flat out refuse to even consider implementing](https://github.com/Sonarr/Sonarr/issues/3709#issuecomment-640946646) something that can already be solved with the mechanisms they have in place! Can you believe that they don't cater to every single user and their beligerance! It's astounding isn't it?!

## **Look how mad the prowlarr devs are ^^ they wrote that and made a pull request because theyre so angy they got called out**

## Blocklist Sonarr Downloads and automatically Redownload based on extensions

(or by state, status, or error messege)

Because sonarr is a huge security risk; softwre that automatically (blindly) downloads files (from shit trackers **made availible by prowlarr**) with random extensions from the trackers I chose to use because they were made availible by prowlarr. c'mon servarr devs.

### so heres my quick and dirty solution i might clean up later

By default, this will REDOWNLOAD and BLOCKLIST queue items that are 60 mins stale based on these (configurable) settings, every 5 minutes.

-   Error messege: "The download is stalled with no connections"
-   Extensions: zipx, lnk, exe, bat, arj
-   status messege: "One or more episodes expected in this release were not imported or missing from the release"
-   status: "warning"
-   states: "importBlocked"

you can configure in the config folder, the filters are line-separated.

[Please consider donating to the project that gives this project a purpose.](https://sonarr.tv/donate)

^^ prowlarr devs begging for money in my repo after refusing to assist their users. clearly they need it more than me. 


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
